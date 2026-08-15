import logging
import os
from datetime import date, datetime, timedelta
from decimal import Decimal

import pymysql
from flask import Flask, jsonify, request


# ─────────────────────────────────────────────────────────────
# Application
# ─────────────────────────────────────────────────────────────

app = Flask(__name__)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)

logger = logging.getLogger("cloud-cost-api")


# ─────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────

DEFAULT_DAYS = 30
MAX_DAYS = 365

DEFAULT_LIMIT = 8
MAX_LIMIT = 50

DEFAULT_CURRENCY = "USD"

FRONTEND_ORIGIN = os.environ.get("FRONTEND_ORIGIN", "*")


# ─────────────────────────────────────────────────────────────
# Database
# ─────────────────────────────────────────────────────────────

def get_db_connection():
    """
    Create a MySQL connection using credentials injected
    into the ECS container through Secrets Manager / SSM.
    """

    return pymysql.connect(
        host=os.environ["DB_HOST"],
        port=int(os.environ.get("DB_PORT", "3306")),
        user=os.environ["DB_USER"],
        password=os.environ["DB_PASSWORD"],
        database=os.environ.get(
            "DB_NAME",
            "costintelligence",
        ),
        cursorclass=pymysql.cursors.DictCursor,
        connect_timeout=5,
        read_timeout=10,
        write_timeout=10,
        autocommit=True,
    )


# ─────────────────────────────────────────────────────────────
# Serialization helpers
# ─────────────────────────────────────────────────────────────

def json_safe(value):
    """
    Convert MySQL/Python values into JSON-safe values.
    """

    if isinstance(value, Decimal):
        return float(value)

    if isinstance(value, (datetime, date)):
        return value.isoformat()

    return value


def serialize_row(row):
    """
    Convert every value in a database row into a JSON-safe value.
    """

    return {
        key: json_safe(value)
        for key, value in row.items()
    }


# ─────────────────────────────────────────────────────────────
# Request validation
# ─────────────────────────────────────────────────────────────

def get_positive_int_argument(
    name,
    default,
    maximum,
):
    """
    Read and validate a positive integer query parameter.
    """

    raw_value = request.args.get(name)

    if raw_value is None:
        return default

    try:
        value = int(raw_value)
    except (TypeError, ValueError):
        raise ValueError(
            f"{name} must be an integer."
        )

    if value < 1:
        raise ValueError(
            f"{name} must be greater than zero."
        )

    if value > maximum:
        raise ValueError(
            f"{name} cannot exceed {maximum}."
        )

    return value


# ─────────────────────────────────────────────────────────────
# CORS
# ─────────────────────────────────────────────────────────────

@app.after_request
def add_cors_headers(response):
    """
    Allow the CloudFront-hosted frontend to call the ECS API.
    """

    response.headers["Access-Control-Allow-Origin"] = (
        FRONTEND_ORIGIN
    )

    response.headers["Access-Control-Allow-Headers"] = (
        "Content-Type"
    )

    response.headers["Access-Control-Allow-Methods"] = (
        "GET, OPTIONS"
    )

    response.headers["Cache-Control"] = (
        "no-store"
    )

    return response


# ─────────────────────────────────────────────────────────────
# Health
# ─────────────────────────────────────────────────────────────

@app.route("/health", methods=["GET"])
def health():
    """
    ALB health check.

    Verifies that the Flask application is running and
    that RDS is reachable.
    """

    connection = None

    try:
        connection = get_db_connection()

        with connection.cursor() as cursor:
            cursor.execute("SELECT 1 AS healthy")
            result = cursor.fetchone()

        return jsonify(
            {
                "status": "healthy",
                "database": "connected",
                "database_check": bool(result),
            }
        ), 200

    except Exception:
        logger.exception(
            "Health check failed."
        )

        return jsonify(
            {
                "status": "unhealthy",
                "database": "unavailable",
            }
        ), 503

    finally:
        if connection:
            connection.close()


# ─────────────────────────────────────────────────────────────
# Dashboard Forecast
# ─────────────────────────────────────────────────────────────

@app.route(
    "/api/costs/forecast",
    methods=["GET"],
)
def costs_forecast():
    """
    Return current-month spending and a simple
    end-of-month projection.

    This endpoint matches the premium frontend contract:

    {
        mtd_total,
        forecast_total,
        daily_rate,
        days_elapsed,
        days_remaining
    }
    """

    today = date.today()

    first_day = today.replace(day=1)

    if today.month == 12:
        next_month = date(
            today.year + 1,
            1,
            1,
        )
    else:
        next_month = date(
            today.year,
            today.month + 1,
            1,
        )

    days_in_month = (
        next_month - first_day
    ).days

    days_elapsed = today.day
    days_remaining = (
        days_in_month - days_elapsed
    )

    connection = None

    try:
        connection = get_db_connection()

        with connection.cursor() as cursor:
            cursor.execute(
                """
                SELECT
                    COALESCE(SUM(amount), 0) AS mtd_total
                FROM daily_costs
                WHERE date >= %s
                  AND date <= %s
                """,
                (
                    first_day,
                    today,
                ),
            )

            result = cursor.fetchone()

        mtd_total = float(
            result["mtd_total"] or 0
        )

        daily_rate = (
            mtd_total / days_elapsed
            if days_elapsed > 0
            else 0
        )

        forecast_total = (
            daily_rate * days_in_month
        )

        return jsonify(
            {
                "month": today.strftime(
                    "%Y-%m"
                ),
                "mtd_total": round(
                    mtd_total,
                    4,
                ),
                "forecast_total": round(
                    forecast_total,
                    4,
                ),
                "daily_rate": round(
                    daily_rate,
                    4,
                ),
                "days_elapsed": days_elapsed,
                "days_remaining": days_remaining,
                "days_in_month": days_in_month,
                "currency": DEFAULT_CURRENCY,
            }
        )

    except Exception:
        logger.exception(
            "Failed to calculate cost forecast."
        )

        return jsonify(
            {
                "error": "Unable to calculate cost forecast."
            }
        ), 500

    finally:
        if connection:
            connection.close()


# ─────────────────────────────────────────────────────────────
# Daily Costs
# ─────────────────────────────────────────────────────────────

@app.route(
    "/api/costs/daily",
    methods=["GET"],
)
def costs_daily():
    """
    Return aggregated daily spending.

    Frontend request:

        /api/costs/daily?days=30

    Response:

        {
            "days": 30,
            "data": [
                {
                    "date": "2026-08-01",
                    "total": 123.45
                }
            ]
        }
    """

    try:
        days = get_positive_int_argument(
            "days",
            DEFAULT_DAYS,
            MAX_DAYS,
        )

    except ValueError as exc:
        return jsonify(
            {"error": str(exc)}
        ), 400

    start_date = (
        date.today()
        - timedelta(days=days - 1)
    )

    end_date = date.today()

    connection = None

    try:
        connection = get_db_connection()

        with connection.cursor() as cursor:
            cursor.execute(
                """
                SELECT
                    date,
                    COALESCE(SUM(amount), 0) AS total
                FROM daily_costs
                WHERE date BETWEEN %s AND %s
                GROUP BY date
                ORDER BY date ASC
                """,
                (
                    start_date,
                    end_date,
                ),
            )

            rows = cursor.fetchall()

        data = [
            {
                "date": str(row["date"]),
                "total": round(
                    float(row["total"] or 0),
                    4,
                ),
            }
            for row in rows
        ]

        return jsonify(
            {
                "days": days,
                "start_date": str(start_date),
                "end_date": str(end_date),
                "currency": DEFAULT_CURRENCY,
                "data": data,
            }
        )

    except Exception:
        logger.exception(
            "Failed to retrieve daily costs."
        )

        return jsonify(
            {
                "error": "Unable to retrieve daily costs."
            }
        ), 500

    finally:
        if connection:
            connection.close()


# ─────────────────────────────────────────────────────────────
# Top Services
# ─────────────────────────────────────────────────────────────

@app.route(
    "/api/costs/top-services",
    methods=["GET"],
)
def top_services():
    """
    Return the highest-spending AWS services.

    Frontend request:

        /api/costs/top-services?days=30&limit=8
    """

    try:
        days = get_positive_int_argument(
            "days",
            DEFAULT_DAYS,
            MAX_DAYS,
        )

        limit = get_positive_int_argument(
            "limit",
            DEFAULT_LIMIT,
            MAX_LIMIT,
        )

    except ValueError as exc:
        return jsonify(
            {"error": str(exc)}
        ), 400

    start_date = (
        date.today()
        - timedelta(days=days - 1)
    )

    connection = None

    try:
        connection = get_db_connection()

        with connection.cursor() as cursor:
            cursor.execute(
                f"""
                SELECT
                    service,
                    COALESCE(SUM(amount), 0) AS total,
                    COUNT(DISTINCT date) AS days_active
                FROM daily_costs
                WHERE date >= %s
                GROUP BY service
                ORDER BY total DESC
                LIMIT {limit}
                """,
                (start_date,),
            )

            rows = cursor.fetchall()

        services = [
            {
                "service": row["service"],
                "total": round(
                    float(row["total"] or 0),
                    4,
                ),
                "days_active": int(
                    row["days_active"] or 0
                ),
            }
            for row in rows
        ]

        return jsonify(
            {
                "days": days,
                "limit": limit,
                "currency": DEFAULT_CURRENCY,
                "services": services,
            }
        )

    except Exception:
        logger.exception(
            "Failed to retrieve top services."
        )

        return jsonify(
            {
                "error": "Unable to retrieve top services."
            }
        ), 500

    finally:
        if connection:
            connection.close()


# ─────────────────────────────────────────────────────────────
# Alerts / Anomalies
# ─────────────────────────────────────────────────────────────

@app.route(
    "/api/alerts",
    methods=["GET"],
)
def alerts():
    """
    Return recent cost anomalies.

    Frontend request:

        /api/alerts?limit=10
    """

    try:
        limit = get_positive_int_argument(
            "limit",
            10,
            MAX_LIMIT,
        )

    except ValueError as exc:
        return jsonify(
            {"error": str(exc)}
        ), 400

    severity = request.args.get(
        "severity"
    )

    allowed_severities = {
        "low",
        "medium",
        "high",
        "critical",
    }

    if severity and severity not in allowed_severities:
        return jsonify(
            {
                "error": (
                    "Invalid severity. "
                    "Allowed values: "
                    "low, medium, high, critical."
                )
            }
        ), 400

    connection = None

    try:
        connection = get_db_connection()

        with connection.cursor() as cursor:

            if severity:
                cursor.execute(
                    f"""
                    SELECT
                        date,
                        service,
                        expected_amount,
                        actual_amount,
                        deviation_pct,
                        severity,
                        detected_at
                    FROM anomalies
                    WHERE severity = %s
                    ORDER BY detected_at DESC
                    LIMIT {limit}
                    """,
                    (severity,),
                )

            else:
                cursor.execute(
                    f"""
                    SELECT
                        date,
                        service,
                        expected_amount,
                        actual_amount,
                        deviation_pct,
                        severity,
                        detected_at
                    FROM anomalies
                    ORDER BY detected_at DESC
                    LIMIT {limit}
                    """,
                )

            rows = cursor.fetchall()

        alerts_data = []

        for row in rows:
            alerts_data.append(
                {
                    "date": str(
                        row["date"]
                    ),
                    "service": row[
                        "service"
                    ],
                    "severity": row[
                        "severity"
                    ],
                    "expected_amount": round(
                        float(
                            row[
                                "expected_amount"
                            ]
                            or 0
                        ),
                        4,
                    ),
                    "actual_amount": round(
                        float(
                            row[
                                "actual_amount"
                            ]
                            or 0
                        ),
                        4,
                    ),
                    "deviation_pct": round(
                        float(
                            row[
                                "deviation_pct"
                            ]
                            or 0
                        ),
                        2,
                    ),
                    "detected_at": (
                        row[
                            "detected_at"
                        ].isoformat()
                        if row[
                            "detected_at"
                        ]
                        else None
                    ),
                }
            )

        return jsonify(
            {
                "count": len(
                    alerts_data
                ),
                "limit": limit,
                "alerts": alerts_data,
            }
        )

    except Exception:
        logger.exception(
            "Failed to retrieve anomalies."
        )

        return jsonify(
            {
                "error": "Unable to retrieve alerts."
            }
        ), 500

    finally:
        if connection:
            connection.close()


# ─────────────────────────────────────────────────────────────
# Error handlers
# ─────────────────────────────────────────────────────────────

@app.errorhandler(404)
def not_found(_error):
    return jsonify(
        {
            "error": "Endpoint not found."
        }
    ), 404


@app.errorhandler(405)
def method_not_allowed(_error):
    return jsonify(
        {
            "error": "HTTP method not allowed."
        }
    ), 405


@app.errorhandler(500)
def internal_error(_error):
    logger.exception(
        "Unhandled application error."
    )

    return jsonify(
        {
            "error": "Internal server error."
        }
    ), 500


# ─────────────────────────────────────────────────────────────
# Local development
# ─────────────────────────────────────────────────────────────

if __name__ == "__main__":
    app.run(
        host="0.0.0.0",
        port=int(
            os.environ.get(
                "PORT",
                "8080",
            )
        ),
        debug=False,
    )

