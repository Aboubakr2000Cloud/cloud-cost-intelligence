CREATE DATABASE IF NOT EXISTS cloudcost;
USE cloudcost;

-- Daily cost records per AWS service
CREATE TABLE IF NOT EXISTS daily_costs (
    id          INT AUTO_INCREMENT PRIMARY KEY,
    date        DATE NOT NULL,
    service     VARCHAR(100) NOT NULL,
    region      VARCHAR(50) NOT NULL DEFAULT 'global',
    amount      DECIMAL(10, 4) NOT NULL DEFAULT 0,
    currency    VARCHAR(10) NOT NULL DEFAULT 'USD',
    unit        VARCHAR(50),
    is_synthetic BOOLEAN DEFAULT FALSE,
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_date_service_region (date, service, region),
    INDEX idx_date (date),
    INDEX idx_service (service),
    INDEX idx_date_service (date, service)
);

-- Monthly cost summaries (pre-aggregated for performance)
CREATE TABLE IF NOT EXISTS monthly_summaries (
    id          INT AUTO_INCREMENT PRIMARY KEY,
    year_month  VARCHAR(7) NOT NULL,  -- e.g. '2026-06'
    service     VARCHAR(100) NOT NULL,
    total_amount DECIMAL(10, 4) NOT NULL DEFAULT 0,
    currency    VARCHAR(10) NOT NULL DEFAULT 'USD',
    updated_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_month_service (year_month, service),
    INDEX idx_year_month (year_month)
);

-- Anomaly detection results
CREATE TABLE IF NOT EXISTS anomalies (
    id              INT AUTO_INCREMENT PRIMARY KEY,
    detected_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    date            DATE NOT NULL,
    service         VARCHAR(100) NOT NULL,
    expected_amount DECIMAL(10, 4),
    actual_amount   DECIMAL(10, 4),
    deviation_pct   DECIMAL(8, 2),
    severity        ENUM('low', 'medium', 'high', 'critical') DEFAULT 'medium',
    alert_sent      BOOLEAN DEFAULT FALSE,
    resolved        BOOLEAN DEFAULT FALSE,
    notes           TEXT,
    INDEX idx_detected_at (detected_at),
    INDEX idx_service_date (service, date),
    INDEX idx_severity (severity)
);

-- Collection job log
CREATE TABLE IF NOT EXISTS collection_log (
    id              INT AUTO_INCREMENT PRIMARY KEY,
    collected_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    date_range_start DATE,
    date_range_end   DATE,
    records_collected INT DEFAULT 0,
    anomalies_found  INT DEFAULT 0,
    alerts_sent      INT DEFAULT 0,
    status          ENUM('success', 'partial', 'failed') DEFAULT 'success',
    error_message   TEXT,
    duration_ms     INT
);
