import json
import logging
import os

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

ssm_client = boto3.client("ssm")
secrets_client = boto3.client("secretsmanager")


# ─────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────

DB_HOST_PARAMETER = os.environ["DB_HOST_PARAMETER"]
DB_PORT_PARAMETER = os.environ["DB_PORT_PARAMETER"]
DB_NAME_PARAMETER = os.environ["DB_NAME_PARAMETER"]
DB_USER_PARAMETER = os.environ["DB_USER_PARAMETER"]

DB_PASSWORD_SECRET = os.environ["DB_PASSWORD_SECRET"]


# ─────────────────────────────────────────────────────────────
# Parameter Store
# ─────────────────────────────────────────────────────────────

def get_parameter(name):
    """
    Retrieve a database configuration value from SSM Parameter Store.
    """
    response = ssm_client.get_parameter(
        Name=name,
        WithDecryption=True,
    )

    return response["Parameter"]["Value"]


def get_database_configuration():
    """
    Retrieve all database connection settings from SSM.
    """
    return {
        "host": get_parameter(DB_HOST_PARAMETER),
        "port": int(get_parameter(DB_PORT_PARAMETER)),
        "database": get_parameter(DB_NAME_PARAMETER),
        "username": get_parameter(DB_USER_PARAMETER),
    }


# ─────────────────────────────────────────────────────────────
# Secrets Manager
# ─────────────────────────────────────────────────────────────

def get_db_password():
    """
    Retrieve the database password from Secrets Manager.

    The secret is expected to contain JSON such as:

    {
        "username": "...",
        "password": "..."
    }
    """
    response = secrets_client.get_secret_value(
        SecretId=DB_PASSWORD_SECRET
    )

    secret_string = response["SecretString"]

    try:
        secret = json.loads(secret_string)
    except json.JSONDecodeError:
        raise ValueError(
            "DB password secret must contain valid JSON."
        )

    if "password" not in secret:
        raise ValueError(
            "DB password secret does not contain a 'password' field."
        )

    return secret["password"]


# ─────────────────────────────────────────────────────────────
# Database connection
# ─────────────────────────────────────────────────────────────

def get_connection(config, password, database=None):
    """
    Create a MySQL connection.

    When database is None, the connection is made without
    selecting a database. This allows the migration to create
    the application database first.
    """
    connection_args = {
        "host": config["host"],
        "port": config["port"],
        "user": config["username"],
        "password": password,
        "connect_timeout": 10,
        "autocommit": True,
        "cursorclass": pymysql.cursors.DictCursor,
    }

    if database:
        connection_args["database"] = database

    return pymysql.connect(**connection_args)


# ─────────────────────────────────────────────────────────────
# Schema migration
# ─────────────────────────────────────────────────────────────

def run_schema_migration(config, password):
    """
    Execute the SQL schema migration.

    The migration file is packaged inside the Lambda ZIP at:

        migrations/001_schema.sql
    """
    migration_path = os.path.join(
        os.path.dirname(__file__),
        "migrations",
        "001_schema.sql",
    )

    if not os.path.exists(migration_path):
        raise FileNotFoundError(
            f"Migration file not found: {migration_path}"
        )

    with open(migration_path, "r", encoding="utf-8") as migration_file:
        sql = migration_file.read()

    # Remove the CREATE DATABASE / USE statements from the
    # migration because the database has already been created
    # and the connection below explicitly selects it.
    statements = []

    for statement in sql.split(";"):
        statement = statement.strip()

        if not statement:
            continue

        statements.append(statement)

    connection = get_connection(
        config,
        password,
        database=config["database"],
    )

    executed = 0

    try:
        with connection.cursor() as cursor:
            for statement in statements:
                logger.info(
                    "Executing migration statement %d.",
                    executed + 1,
                )

                logger.info(
                    "SQL statement being executed:\n%s",
                    statement,
                )
                cursor.execute(statement)
                executed += 1

    finally:
        connection.close()

    return executed


# ─────────────────────────────────────────────────────────────
# Lambda handler
# ─────────────────────────────────────────────────────────────

def lambda_handler(event, context):
    """
    Lambda entry point.

    The migration is designed to be safely executed multiple times
    because the SQL schema uses CREATE TABLE IF NOT EXISTS.
    """
    logger.info("Database migration started.")

    config = get_database_configuration()

    logger.info(
        "Target database: %s on %s:%s",
        config["database"],
        config["host"],
        config["port"],
    )

    password = get_db_password()


    # Run the schema migration.
    statements_executed = run_schema_migration(
        config,
        password,
    )

    logger.info(
        "Database migration completed successfully. "
        "Executed %d SQL statements.",
        statements_executed,
    )

    return {
        "status": "success",
        "database": config["database"],
        "statements_executed": statements_executed,
    }

