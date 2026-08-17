import json
import logging
import os
import random
from datetime import datetime, timedelta

import boto3
import pymysql


# ─────────────────────────────────────────────────────────────
# Logging
# ─────────────────────────────────────────────────────────────

logger = logging.getLogger()
logger.setLevel(logging.INFO)


# ─────────────────────────────────────────────────────────────
# AWS clients
# ─────────────────────────────────────────────────────────────

secrets_client = boto3.client("secretsmanager")
ssm_client = boto3.client("ssm")

AWS_REGION = os.environ.get("REGION", "eu-west-1")

# ─────────────────────────────────────────────────────────────
# Synthetic AWS service cost profiles
# ─────────────────────────────────────────────────────────────

SERVICE_PROFILES = {
    "Amazon Elastic Compute Cloud - Compute": {
        "base": 45.0,
        "variance": 0.15,
        "spike_chance": 0.05,
    },
    "Amazon Relational Database Service": {
        "base": 25.0,
        "variance": 0.10,
        "spike_chance": 0.03,
    },
    "Amazon Simple Storage Service": {
        "base": 8.0,
        "variance": 0.20,
        "spike_chance": 0.02,
    },
    "AWS Lambda": {
        "base": 2.0,
        "variance": 0.30,
        "spike_chance": 0.08,
    },
    "Amazon Virtual Private Cloud": {
        "base": 15.0,
        "variance": 0.05,
        "spike_chance": 0.01,
    },
    "AWS Secrets Manager": {
        "base": 0.80,
        "variance": 0.10,
        "spike_chance": 0.01,
    },
    "Amazon Elastic Container Service": {
        "base": 18.0,
        "variance": 0.15,
        "spike_chance": 0.04,
    },
    "Amazon Elastic Load Balancing": {
        "base": 7.0,
        "variance": 0.15,
        "spike_chance": 0.03,
    },
    "Amazon DynamoDB": {
        "base": 1.50,
        "variance": 0.30,
        "spike_chance": 0.05,
    },
    "AmazonCloudWatch": {
        "base": 4.0,
        "variance": 0.20,
        "spike_chance": 0.04,
    },
    "Amazon EC2 Container Registry (ECR)": {
        "base": 1.0,
        "variance": 0.20,
        "spike_chance": 0.02,
    },
    "AWS Key Management Service": {
        "base": 0.50,
        "variance": 0.10,
        "spike_chance": 0.01,
    },
    "Amazon Simple Notification Service": {
        "base": 0.30,
        "variance": 0.30,
        "spike_chance": 0.02,
    },
    "Amazon API Gateway": {
        "base": 1.0,
        "variance": 0.25,
        "spike_chance": 0.03,
    },
    "AWS CloudTrail": {
        "base": 1.0,
        "variance": 0.20,
        "spike_chance": 0.02,
    },
    "Amazon CloudFront": {
        "base": 5.0,
        "variance": 0.25,
        "spike_chance": 0.04,
    },
    "Amazon EventBridge": {
        "base": 0.50,
        "variance": 0.25,
        "spike_chance": 0.03,
    },
}


# ─────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────


def get_db_credentials():
    """Load database configuration from SSM and Secrets Manager."""

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
        parameter["Name"]: parameter["Value"] for parameter in response["Parameters"]
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
# Synthetic cost generation
# ─────────────────────────────────────────────────────────────


def generate_daily_amount(base, variance, spike_chance, date_offset):
    """
    Generate a realistic daily AWS cost.

    Includes:
    - Slight upward trend over time
    - Lower weekend usage
    - Random daily variance
    - Occasional cost spikes
    """

    # Slight upward trend
    trend_factor = 1 + (date_offset * 0.001)

    # Weekend usage is slightly lower
    date = datetime.now() - timedelta(days=date_offset)
    day_of_week = date.weekday()

    dow_factor = 0.85 if day_of_week >= 5 else 1.0

    # Normal daily variation
    variance_factor = 1 + random.uniform(-variance, variance)

    # Occasional cost spike
    if random.random() < spike_chance:
        spike_factor = random.uniform(1.5, 2.5)
    else:
        spike_factor = 1.0

    amount = base * trend_factor * dow_factor * variance_factor * spike_factor

    return max(0.01, round(amount, 4))


# ─────────────────────────────────────────────────────────────
# Database connection
# ─────────────────────────────────────────────────────────────


def get_database_connection():
    """
    Retrieve database credentials from Secrets Manager
    and establish a MySQL connection.
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
# Lambda handler
# ─────────────────────────────────────────────────────────────


def lambda_handler(event, context):
    """
    Generate and insert synthetic AWS cost data.

    Default:
        90 days × 17 services = 1530 records
    """

    event = event or {}

    days_back = int(event.get("days_back", 90))

    if days_back <= 0:
        raise ValueError("days_back must be greater than zero")

    logger.info(
        "Starting synthetic cost data generation: " "days=%s, services=%s, region=%s",
        days_back,
        len(SERVICE_PROFILES),
        AWS_REGION,
    )

    connection = get_database_connection()
    records_inserted = 0

    try:
        # ─────────────────────────────────────────────────────
        # Insert daily cost records
        # ─────────────────────────────────────────────────────

        with connection.cursor() as cursor:

            for day_offset in range(days_back, 0, -1):

                date = (datetime.now() - timedelta(days=day_offset)).strftime(
                    "%Y-%m-%d"
                )

                for service, profile in SERVICE_PROFILES.items():

                    amount = generate_daily_amount(
                        base=profile["base"],
                        variance=profile["variance"],
                        spike_chance=profile["spike_chance"],
                        date_offset=day_offset,
                    )

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
                        VALUES
                            (%s, %s, %s, %s, %s, %s)

                        ON DUPLICATE KEY UPDATE
                            amount = VALUES(amount)
                        """,
                        (
                            date,
                            service,
                            AWS_REGION,
                            amount,
                            "USD",
                            True,
                        ),
                    )

                    records_inserted += 1

            connection.commit()

        logger.info(
            "Inserted %s synthetic daily cost records",
            records_inserted,
        )

        # ─────────────────────────────────────────────────────
        # Rebuild monthly summaries
        # ─────────────────────────────────────────────────────

        with connection.cursor() as cursor:

            cursor.execute(
                """
                INSERT INTO monthly_summaries
                    (
                        `year_month`,
                        service,
                        total_amount
                    )
                SELECT
                    DATE_FORMAT(date, '%%Y-%%m'),
                    service,
                    SUM(amount)
                FROM daily_costs
                GROUP BY
                    DATE_FORMAT(date, '%%Y-%%m'),
                    service

                ON DUPLICATE KEY UPDATE
                    total_amount = VALUES(total_amount)
                """
            )

            connection.commit()

        logger.info("Monthly cost summaries successfully updated")

        # ─────────────────────────────────────────────────────
        # Final result
        # ─────────────────────────────────────────────────────

        result = {
            "status": "success",
            "records_inserted": records_inserted,
            "days": days_back,
            "services": len(SERVICE_PROFILES),
            "region": AWS_REGION,
        }

        logger.info(
            "Synthetic data seeding completed: %s",
            result,
        )

        return result

    except Exception:
        connection.rollback()

        logger.exception("Synthetic data seeding failed")

        raise

    finally:
        connection.close()

        logger.info("Database connection closed")
