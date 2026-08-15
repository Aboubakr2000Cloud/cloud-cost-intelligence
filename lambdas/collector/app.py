import json
import logging
import os
from datetime import datetime, timedelta, timezone
from decimal import Decimal

import boto3
import pymysql


# ─────────────────────────────────────────────────────────────
# Logging
# ─────────────────────────────────────────────────────────────

logger = logging.getLogger()
logger.setLevel(logging.INFO)


# ─────────────────────────────────────────────────────────────
# AWS clients
# Created outside the handler so Lambda can reuse them
# across warm invocations.
# ─────────────────────────────────────────────────────────────

ce_client = boto3.client("ce", region_name="us-east-1")
secrets_client = boto3.client("secretsmanager")
ssm_client = boto3.client("ssm")


# ─────────────────────────────────────────────────────────────
# Secrets Manager
# ─────────────────────────────────────────────────────────────

def get_db_credentials():
    """
    Retrieve RDS credentials from Secrets Manager.

    Credentials are cached between warm Lambda invocations
    to avoid calling Secrets Manager unnecessarily.
    """
    parameter_names = [
        os.environ["DB_HOST_PARAMETER"],
        os.environ["DB_PORT_PARAMETER"],
        os.environ["DB_NAME_PARAMETER"],
        os.environ["DB_USER_PARAMETER"],
    ]

    response = ssm_client.get_parameters(
        Names=parameter_names,
        WithDecryption=True,
    )

    parameters = {
        parameter["Name"]: parameter["Value"]
        for parameter in response["Parameters"]
    }

    secret_response = secrets_client.get_secret_value(
        SecretId=os.environ["DB_PASSWORD_SECRET"]
    )

    secret = json.loads(secret_response["SecretString"])

    return {
        "host": parameters[os.environ["DB_HOST_PARAMETER"]],
        "port": int(parameters[os.environ["DB_PORT_PARAMETER"]]),
        "database": parameters[os.environ["DB_NAME_PARAMETER"]],
        "user": parameters[os.environ["DB_USER_PARAMETER"]],
        "password": secret["password"],
    }


# ─────────────────────────────────────────────────────────────
# Database connection
# ─────────────────────────────────────────────────────────────

def get_db():
    """
    Create a connection to the RDS MySQL database.
    """
    db = get_db_credentials()

    return pymysql.connect(
        host=db["host"],
        port=db["port"],
        user=db["user"],
        password=db["password"],
        database=db["database"],
        cursorclass=pymysql.cursors.DictCursor,
        connect_timeout=5,
    )


# ─────────────────────────────────────────────────────────────
# Cost Explorer
# ─────────────────────────────────────────────────────────────

def fetch_cost_data(start_date, end_date):
    """
    Fetch daily AWS cost data from Cost Explorer.

    Costs are grouped by AWS service and region.
    """
    response = ce_client.get_cost_and_usage(
        TimePeriod={
            "Start": start_date,
            "End": end_date,
        },
        Granularity="DAILY",
        Metrics=["BlendedCost"],
        GroupBy=[
            {
                "Type": "DIMENSION",
                "Key": "SERVICE",
            },
            {
                "Type": "DIMENSION",
                "Key": "REGION",
            },
        ],
    )

    return response["ResultsByTime"]


# ─────────────────────────────────────────────────────────────
# Store Cost Explorer data
# ─────────────────────────────────────────────────────────────

def store_cost_data(conn, results, is_synthetic=False):
    """
    Store Cost Explorer results in the daily_costs table.

    Existing records are updated instead of duplicated.
    """
    stored = 0

    with conn.cursor() as cursor:
        for day_result in results:
            date = day_result["TimePeriod"]["Start"]

            for group in day_result["Groups"]:
                service = group["Keys"][0]

                region = (
                    group["Keys"][1]
                    if len(group["Keys"]) > 1 and group["Keys"][1]
                    else "global"
                )

                amount = Decimal(
                    group["Metrics"]["BlendedCost"]["Amount"]
                )

                # Ignore zero-cost records.
                if amount == 0:
                    continue

                cursor.execute(
                    """
                    INSERT INTO daily_costs
                        (
                            date,
                            service,
                            region,
                            amount,
                            currency,
                            is_synthetic
                        )
                    VALUES (%s, %s, %s, %s, %s, %s)
                    ON DUPLICATE KEY UPDATE
                        amount = VALUES(amount),
                        is_synthetic = VALUES(is_synthetic)
                    """,
                    (
                        date,
                        service,
                        region,
                        float(amount),
                        "USD",
                        is_synthetic,
                    ),
                )

                stored += 1

        conn.commit()

    return stored


# ─────────────────────────────────────────────────────────────
# Monthly summaries
# ─────────────────────────────────────────────────────────────

def update_monthly_summaries(conn):
    """
    Refresh monthly cost summaries for the recent billing period.

    Recalculating the last two months allows Cost Explorer data
    that changes after initial collection to be reflected.
    """
    with conn.cursor() as cursor:
        cursor.execute(
            """
            INSERT INTO monthly_summaries
                (
                    `year_month`,
                    service,
                    total_amount
                )
            SELECT
                DATE_FORMAT(date, '%Y-%m'),
                service,
                SUM(amount)
            FROM daily_costs
            WHERE date >= DATE_FORMAT(
                NOW() - INTERVAL 2 MONTH,
                '%Y-%m-01'
            )
            GROUP BY
                DATE_FORMAT(date, '%Y-%m'),
                service
            ON DUPLICATE KEY UPDATE
                total_amount = VALUES(total_amount),
                updated_at = NOW()
            """
        )

        conn.commit()


# ─────────────────────────────────────────────────────────────
# Collection logging
# ─────────────────────────────────────────────────────────────

def log_collection(
    conn,
    start_date,
    end_date,
    records,
    anomalies,
    alerts,
    status,
    error=None,
    duration=None,
):
    """
    Record the result of a Collector execution.
    """
    with conn.cursor() as cursor:
        cursor.execute(
            """
            INSERT INTO collection_log
                (
                    date_range_start,
                    date_range_end,
                    records_collected,
                    anomalies_found,
                    alerts_sent,
                    status,
                    error_message,
                    duration_ms
                )
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
            """,
            (
                start_date,
                end_date,
                records,
                anomalies,
                alerts,
                status,
                error,
                duration,
            ),
        )

        conn.commit()


# ─────────────────────────────────────────────────────────────
# Lambda handler
# ─────────────────────────────────────────────────────────────

def lambda_handler(event, context):
    """
    Main Lambda entry point.

    Collects the previous seven days of AWS Cost Explorer data,
    stores it in RDS, refreshes monthly summaries, and records
    the collection result.
    """
    start_time = datetime.now(timezone.utc)

    logger.info(
        "Cost collection started at %s",
        start_time.isoformat(),
    )

    # Collect the previous seven days.
    # The overlapping window helps catch billing updates or gaps.
    end_date = datetime.now(timezone.utc).strftime("%Y-%m-%d")

    start_date = (
        datetime.now(timezone.utc)
        - timedelta(days=7)
    ).strftime("%Y-%m-%d")

    conn = None
    records_stored = 0

    try:
        # Connect to RDS.
        conn = get_db()

        logger.info(
            "Fetching cost data from %s to %s",
            start_date,
            end_date,
        )

        # Fetch real AWS billing data.
        results = fetch_cost_data(
            start_date,
            end_date,
        )

        # Store real Cost Explorer data.
        records_stored = store_cost_data(
            conn,
            results,
            is_synthetic=False,
        )

        logger.info(
            "Stored %s cost records",
            records_stored,
        )

        # Refresh monthly aggregates.
        update_monthly_summaries(conn)

        # Calculate execution duration.
        duration_ms = int(
            (
                datetime.now(timezone.utc)
                - start_time
            ).total_seconds()
            * 1000
        )

        # Record successful collection.
        log_collection(
            conn,
            start_date,
            end_date,
            records_stored,
            0,
            0,
            "success",
            duration=duration_ms,
        )

        return {
            "status": "success",
            "records_stored": records_stored,
            "date_range": f"{start_date} to {end_date}",
            "duration_ms": duration_ms,
        }

    except Exception as e:
        logger.error(
            "Collection failed: %s",
            e,
            exc_info=True,
        )

        # Attempt to record the failure.
        if conn:
            try:
                log_collection(
                    conn,
                    start_date,
                    end_date,
                    records_stored,
                    0,
                    0,
                    "failed",
                    error=str(e),
                )
            except Exception:
                logger.exception(
                    "Failed to write collection failure log"
                )

        # Re-raise so Lambda reports the invocation as failed.
        raise

    finally:
        # Always close the database connection.
        if conn:
            conn.close()

