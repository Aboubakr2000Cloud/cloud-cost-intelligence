import json
import logging
import os
from decimal import Decimal

import boto3
import pymysql

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ssm = boto3.client("ssm")
secrets = boto3.client("secretsmanager")


def get_parameter(name):
    response = ssm.get_parameter(
        Name=name,
        WithDecryption=True,
    )
    return response["Parameter"]["Value"]


def get_db_password(secret_name):
    response = secrets.get_secret_value(
        SecretId=secret_name,
    )

    secret = response["SecretString"]

    try:
        secret_data = json.loads(secret)
        return secret_data.get("password") or secret_data.get("DB_PASSWORD")
    except json.JSONDecodeError:
        return secret


def lambda_handler(event, context):
    logger.info("Database verification started.")

    host = get_parameter(os.environ["DB_HOST_PARAMETER"])
    port = int(get_parameter(os.environ["DB_PORT_PARAMETER"]))
    database = get_parameter(os.environ["DB_NAME_PARAMETER"])
    username = get_parameter(os.environ["DB_USER_PARAMETER"])
    password = get_db_password(os.environ["DB_PASSWORD_SECRET"])

    logger.info(
        "Connecting to %s:%s database=%s",
        host,
        port,
        database,
    )

    connection = pymysql.connect(
        host=host,
        port=port,
        user=username,
        password=password,
        database=database,
        connect_timeout=10,
        read_timeout=10,
        write_timeout=10,
        cursorclass=pymysql.cursors.DictCursor,
    )

    try:
        with connection.cursor() as cursor:
            cursor.execute("SELECT COUNT(*) AS count FROM daily_costs")
            daily_costs = cursor.fetchone()["count"]

            cursor.execute(
                """
                DELETE a1
                FROM anomalies a1
                JOIN anomalies a2
                  ON a1.date = a2.date
                 AND a1.service = a2.service
                 AND a1.id < a2.id
                """
            )

            cursor.execute(
                """
                SELECT COUNT(*) AS count
                FROM information_schema.statistics
                WHERE table_schema = DATABASE()
                AND table_name = 'anomalies'
                AND index_name = 'uq_anomaly_service_date'
                """
            )

            unique_index_exists = cursor.fetchone()["count"] > 0

            if not unique_index_exists:

                cursor.execute(
                    """
                    ALTER TABLE anomalies
                    ADD UNIQUE KEY uq_anomaly_service_date
                        (service, date)
                    """
                )

            connection.commit()

            cursor.execute("SELECT COUNT(DISTINCT service) AS count FROM daily_costs")
            distinct_services = cursor.fetchone()["count"]

            cursor.execute(
                """
                SELECT
                    MIN(`date`) AS min_date,
                    MAX(`date`) AS max_date
                FROM daily_costs
                """
            )
            date_range = cursor.fetchone()

            cursor.execute("SELECT COUNT(*) AS count FROM monthly_summaries")
            monthly_summaries = cursor.fetchone()["count"]

            cursor.execute("SELECT COUNT(*) AS count FROM anomalies")
            anomalies = cursor.fetchone()["count"]

            cursor.execute("SELECT COUNT(*) AS count FROM collection_log")
            collection_log = cursor.fetchone()["count"]

            cursor.execute(
                """
                SELECT
                    service,
                    COUNT(*) AS records,
                    SUM(amount) AS total_amount
                FROM daily_costs
                GROUP BY service
                ORDER BY total_amount DESC
                LIMIT 10
                """
            )
            service_breakdown = cursor.fetchall()

            cursor.execute("SHOW CREATE TABLE anomalies")
            anomalies_schema = cursor.fetchone()

        result = {
            "status": "success",
            "database": database,
            "daily_costs": daily_costs,
            "anomalies_schema": anomalies_schema,
            "distinct_services": distinct_services,
            "date_range": {
                "min": str(date_range["min_date"]),
                "max": str(date_range["max_date"]),
            },
            "monthly_summaries": monthly_summaries,
            "anomalies": anomalies,
            "collection_log": collection_log,
            "top_services": [
                {
                    "service": row["service"],
                    "records": row["records"],
                    "total_amount": (
                        float(row["total_amount"])
                        if isinstance(row["total_amount"], Decimal)
                        else row["total_amount"]
                    ),
                }
                for row in service_breakdown
            ],
        }

        logger.info("Database verification completed successfully.")

        return result

    finally:
        connection.close()
