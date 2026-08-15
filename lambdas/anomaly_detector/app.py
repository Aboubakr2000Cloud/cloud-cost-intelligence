import json
import logging
import os
from datetime import datetime, timedelta, timezone

import boto3
import pymysql


# ─────────────────────────────────────────────────────────────
# Logging
# ─────────────────────────────────────────────────────────────

logger = logging.getLogger()
logger.setLevel(logging.INFO)


# ─────────────────────────────────────────────────────────────
# AWS clients
# Created outside the handler for Lambda warm-start reuse.
# ─────────────────────────────────────────────────────────────

REGION = os.environ.get("REGION", "eu-west-1")

secrets_client = boto3.client("secretsmanager")
ssm_client = boto3.client("ssm")

sns_client = boto3.client(
    "sns",
    region_name=REGION,
)


# ─────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────

ANOMALY_THRESHOLD_PCT = float(
    os.environ.get("ANOMALY_THRESHOLD_PCT", "25")
)

SNS_TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN")


# ─────────────────────────────────────────────────────────────
# Database credentials
# ─────────────────────────────────────────────────────────────

def get_db_credentials():
    """
    Retrieve database credentials from Secrets Manager.

    Cache the credentials during warm Lambda invocations
    to avoid unnecessary Secrets Manager API calls.
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
# Anomaly detection
# ─────────────────────────────────────────────────────────────

def detect_anomalies(conn, target_date):
    """
    Compare the target day's cost for each service against
    its average cost during the previous seven days.

    A service is considered anomalous when its cost is more
    than ANOMALY_THRESHOLD_PCT above its historical average.
    """

    target = datetime.strptime(
        target_date,
        "%Y-%m-%d",
    )

    history_start = (
        target - timedelta(days=8)
    ).strftime("%Y-%m-%d")

    history_end = (
        target - timedelta(days=1)
    ).strftime("%Y-%m-%d")

    with conn.cursor() as cursor:
        cursor.execute(
            """
            SELECT
                t.service,
                t.amount AS actual_amount,
                h.avg_amount AS expected_amount,
                CASE
                    WHEN h.avg_amount > 0
                    THEN (
                        (t.amount - h.avg_amount)
                        / h.avg_amount
                    ) * 100
                    ELSE 0
                END AS deviation_pct

            FROM daily_costs t

            JOIN (
                SELECT
                    service,
                    AVG(amount) AS avg_amount
                FROM daily_costs
                WHERE date BETWEEN %s AND %s
                GROUP BY service
            ) h
                ON t.service = h.service

            WHERE t.date = %s
              AND t.amount > 0

            HAVING deviation_pct > %s

            ORDER BY deviation_pct DESC
            """,
            (
                history_start,
                history_end,
                target_date,
                ANOMALY_THRESHOLD_PCT,
            ),
        )

        return cursor.fetchall()


# ─────────────────────────────────────────────────────────────
# Severity classification
# ─────────────────────────────────────────────────────────────

def classify_severity(deviation_pct):
    """
    Convert percentage deviation into a severity level.
    """

    if deviation_pct >= 100:
        return "critical"

    if deviation_pct >= 50:
        return "high"

    if deviation_pct >= 25:
        return "medium"

    return "low"


# ─────────────────────────────────────────────────────────────
# Store anomaly
# ─────────────────────────────────────────────────────────────

def store_anomaly(conn, date, anomaly):
    """
    Store or update an anomaly.

    Returns True when a new anomaly was created.
    Returns False when the anomaly already existed.
    """

    deviation_pct = float(
        anomaly["deviation_pct"]
    )

    severity = classify_severity(
        deviation_pct
    )

    with conn.cursor() as cursor:

        cursor.execute(
            """
            SELECT id
            FROM anomalies
            WHERE service = %s
              AND date = %s
            LIMIT 1
            """,
            (
                anomaly["service"],
                date,
            ),
        )

        existing = cursor.fetchone()

        cursor.execute(
            """
            INSERT INTO anomalies
                (
                    date,
                    service,
                    expected_amount,
                    actual_amount,
                    deviation_pct,
                    severity
                )
            VALUES (%s, %s, %s, %s, %s, %s)

            ON DUPLICATE KEY UPDATE
                expected_amount = VALUES(expected_amount),
                actual_amount = VALUES(actual_amount),
                deviation_pct = VALUES(deviation_pct),
                severity = VALUES(severity)
            """,
            (
                date,
                anomaly["service"],
                float(
                    anomaly["expected_amount"] or 0
                ),
                float(
                    anomaly["actual_amount"]
                ),
                deviation_pct,
                severity,
            ),
        )

        conn.commit()

        return existing is None

# ─────────────────────────────────────────────────────────────
# SNS alert
# ─────────────────────────────────────────────────────────────

def send_alert(anomaly, date):
    """
    Send an SNS notification for a detected anomaly.
    """

    if not SNS_TOPIC_ARN:
        logger.warning(
            "SNS_TOPIC_ARN is not configured. "
            "Skipping alert."
        )
        return False

    deviation_pct = float(
        anomaly["deviation_pct"]
    )

    severity = classify_severity(
        deviation_pct
    )

    expected_amount = float(
        anomaly["expected_amount"] or 0
    )

    actual_amount = float(
        anomaly["actual_amount"]
    )

    message = (
        "AWS Cost Anomaly Detected\n\n"
        f"Severity: {severity.upper()}\n"
        f"Service: {anomaly['service']}\n"
        f"Date: {date}\n"
        f"Expected: ${expected_amount:.2f}\n"
        f"Actual: ${actual_amount:.2f}\n"
        f"Deviation: +{deviation_pct:.1f}%\n\n"
        "View the Cloud Cost Intelligence dashboard "
        "for more details."
    )

    sns_client.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject=(
            "[CloudCost] Cost Anomaly: "
            f"{anomaly['service']} "
            f"(+{deviation_pct:.0f}%)"
        ),
        Message=message,
    )

    return True


# ─────────────────────────────────────────────────────────────
# Lambda handler
# ─────────────────────────────────────────────────────────────

def handler(event, context):
    """
    Run anomaly detection for a target date.

    By default, analyzes yesterday's AWS costs.
    A specific date can be supplied through the event.
    """

    target_date = event.get(
        "date",
        (
            datetime.now(timezone.utc)
            - timedelta(days=1)
        ).strftime("%Y-%m-%d"),
    )

    logger.info(
        "Running anomaly detection for %s",
        target_date,
    )

    conn = get_db()

    anomalies_found = 0
    alerts_sent = 0

    try:
        # Detect unusual service-level spending.
        anomalies = detect_anomalies(
            conn,
            target_date,
        )

        logger.info(
            "Found %s anomalies for %s",
            len(anomalies),
            target_date,
        )

        for anomaly in anomalies:

            # Persist anomaly.
            is_new_anomaly = store_anomaly(
                conn,
                target_date,
                anomaly,
            )

            anomalies_found += 1

            # Send alerts for medium or higher severity.
            severity = classify_severity(
                float(
                    anomaly["deviation_pct"]
                )
            )

            if (
                is_new_anomaly
                and severity in (
                  "medium",
                  "high",
                  "critical",
               )
            ):
               if send_alert(
                    anomaly,
                    target_date,
               ):
                    alerts_sent += 1

                    logger.info(
                        "Alert sent for %s: +%.1f%%",
                        anomaly["service"],
                        float(
                            anomaly[
                                "deviation_pct"
                            ]
                        ),
                    )

        return {
            "status": "success",
            "date": target_date,
            "anomalies_found": anomalies_found,
            "alerts_sent": alerts_sent,
        }

    finally:
        conn.close()

