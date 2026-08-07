# SNS Topic for all alerts
resource "aws_sns_topic" "alerts" {
  name = "${var.monitor_prefix}-alerts"
  tags = merge(
    var.tags,
    {
      Name = "${var.monitor_prefix}-alerts"
    }
  )
}

# Email subscription
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ── ECS ALARMS ───────────────────────────────────────────────────────────
# High CPU
resource "aws_cloudwatch_metric_alarm" "ecs_high_cpu" {
  alarm_name        = "${var.monitor_prefix}-ecs-high-cpu"
  alarm_description = "ECS service CPU above 80% for 10 minutes"
  namespace         = "AWS/ECS"
  metric_name       = "CPUUtilization"
  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = var.ecs_service_name
  }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"
  tags = merge(
    var.tags,
    {
      Name = "${var.monitor_prefix}-ecs-high-cpu"
    }
  )
}

# High Memory
resource "aws_cloudwatch_metric_alarm" "ecs_high_memory" {
  alarm_name        = "${var.monitor_prefix}-ecs-high-memory"
  alarm_description = "ECS service memory above 80% for 10 minutes"
  namespace         = "AWS/ECS"
  metric_name       = "MemoryUtilization"
  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = var.ecs_service_name
  }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"
  tags = merge(
    var.tags,
    {
      Name = "${var.monitor_prefix}-ecs-high-memory"
    }
  )
}

# ── ALB ALARMS ───────────────────────────────────────────────────────────
# High 5XX error count
resource "aws_cloudwatch_metric_alarm" "alb_5xx_errors" {
  alarm_name        = "${var.monitor_prefix}-alb-5xx-errors"
  alarm_description = "ALB target 5XX errors above threshold"
  namespace         = "AWS/ApplicationELB"
  metric_name       = "HTTPCode_Target_5XX_Count"
  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 10
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"
  tags = merge(
    var.tags,
    {
      Name = "${var.monitor_prefix}-alb-5xx-errors"
    }
  )
}

# High response latency
resource "aws_cloudwatch_metric_alarm" "alb_high_latency" {
  alarm_name        = "${var.monitor_prefix}-alb-high-latency"
  alarm_description = "ALB target response time above 2 seconds"
  namespace         = "AWS/ApplicationELB"
  metric_name       = "TargetResponseTime"
  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 2
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"
  tags = merge(
    var.tags,
    {
      Name = "${var.monitor_prefix}-alb-high-latency"
    }
  )
}

# ── RDS ALARMS ───────────────────────────────────────────────────────────
# High CPU
resource "aws_cloudwatch_metric_alarm" "rds_high_cpu" {
  alarm_name        = "${var.monitor_prefix}-rds-high-cpu"
  alarm_description = "RDS CPU above 80% for 10 minutes"
  namespace         = "AWS/RDS"
  metric_name       = "CPUUtilization"
  dimensions = {
    DBInstanceIdentifier = var.db_instance_identifier
  }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"
  tags = merge(
    var.tags,
    {
      Name = "${var.monitor_prefix}-rds-high-cpu"
    }
  )
}

# Low free storage — critical
resource "aws_cloudwatch_metric_alarm" "rds_low_storage" {
  alarm_name        = "${var.monitor_prefix}-rds-low-storage"
  alarm_description = "RDS free storage below 2GB — action required"
  namespace         = "AWS/RDS"
  metric_name       = "FreeStorageSpace"
  dimensions = {
    DBInstanceIdentifier = var.db_instance_identifier
  }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 1
  threshold           = 2000000000 # 2GB in bytes
  comparison_operator = "LessThanThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "breaching" # if no data, assume problem
  tags = merge(
    var.tags,
    {
      Name = "${var.monitor_prefix}-rds-low-storage"
    }
  )
}

# High connection count
resource "aws_cloudwatch_metric_alarm" "rds_high_connections" {
  alarm_name        = "${var.monitor_prefix}-rds-high-connections"
  alarm_description = "RDS connections above 50 (approaching db.t3.micro limit)"
  namespace         = "AWS/RDS"
  metric_name       = "DatabaseConnections"
  dimensions = {
    DBInstanceIdentifier = var.db_instance_identifier
  }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 50
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"
  tags = merge(
    var.tags,
    {
      Name = "${var.monitor_prefix}-rds-high-connections"
    }
  )
}

resource "aws_cloudwatch_metric_alarm" "collector_errors" {
  alarm_name        = "${var.monitor_prefix}-collector-errors"
  alarm_description = "Collector Lambda encountered one or more errors"

  namespace   = "AWS/Lambda"
  metric_name = "Errors"

  dimensions = {
    FunctionName = var.collector_function_name
  }

  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"

  treat_missing_data = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = merge(
    var.tags,
    {
      Name = "${var.monitor_prefix}-collector-errors"
    }
  )
}

resource "aws_cloudwatch_metric_alarm" "collector_duration" {
  alarm_name        = "${var.monitor_prefix}-collector-duration"
  alarm_description = "Collector Lambda execution duration is unusually high"

  namespace   = "AWS/Lambda"
  metric_name = "Duration"

  dimensions = {
    FunctionName = var.collector_function_name
  }

  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 60000
  comparison_operator = "GreaterThanThreshold"

  treat_missing_data = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = merge(
    var.tags,
    {
      Name = "${var.monitor_prefix}-collector-duration"
    }
  )
}

resource "aws_cloudwatch_metric_alarm" "anomaly_detector_errors" {
  alarm_name        = "${var.monitor_prefix}-anomaly-errors"
  alarm_description = "Anomaly Detector Lambda encountered one or more errors"

  namespace   = "AWS/Lambda"
  metric_name = "Errors"

  dimensions = {
    FunctionName = var.anomaly_detector_function_name
  }

  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"

  treat_missing_data = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = merge(
    var.tags,
    {
      Name = "${var.monitor_prefix}-anomaly-errors"
    }
  )
}

resource "aws_cloudwatch_metric_alarm" "anomaly_detector_duration" {
  alarm_name        = "${var.monitor_prefix}-anomaly-duration"
  alarm_description = "Anomaly Detector Lambda execution duration is unusually high"

  namespace   = "AWS/Lambda"
  metric_name = "Duration"

  dimensions = {
    FunctionName = var.anomaly_detector_function_name
  }

  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 60000
  comparison_operator = "GreaterThanThreshold"

  treat_missing_data = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = merge(
    var.tags,
    {
      Name = "${var.monitor_prefix}-anomaly-duration"
    }
  )
}

# Only alert if BOTH CPU is high AND errors are high
resource "aws_cloudwatch_composite_alarm" "service_degraded" {
  alarm_name        = "${var.monitor_prefix}-service-degraded"
  alarm_description = "Service degraded: high CPU AND high error rate"

  alarm_rule = "ALARM(${aws_cloudwatch_metric_alarm.ecs_high_cpu.alarm_name}) AND ALARM(${aws_cloudwatch_metric_alarm.alb_5xx_errors.alarm_name})"

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = merge(
    var.tags,
    {
      Name = "${var.monitor_prefix}-service_degraded"
    }
  )
}

# ── CLOUDWATCH DASHBOARD ───────────────────────────────────────────────────────────
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.monitor_prefix}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      # Row 1: ECS Health
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "ECS CPU & Memory Utilization"
          region = var.region
          period = 300
          stat   = "Average"
          view   = "timeSeries"
          metrics = [
            ["AWS/ECS", "CPUUtilization",
              "ClusterName", var.ecs_cluster_name,
              "ServiceName", var.ecs_service_name,
            { label = "CPU %" }],
            ["AWS/ECS", "MemoryUtilization",
              "ClusterName", var.ecs_cluster_name,
              "ServiceName", var.ecs_service_name,
            { label = "Memory %" }]
          ]
          annotations = {
            horizontal = [{
              value = 80
              label = "Alert threshold"
              color = "#d62728"
            }]
          }
        }
      },
      # ALB Traffic
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "ALB Request Count & 5XX Errors"
          region = var.region
          period = 60
          stat   = "Sum"
          view   = "timeSeries"
          metrics = [
            ["AWS/ApplicationELB", "RequestCount",
              "LoadBalancer", var.alb_arn_suffix,
            { stat = "Sum", label = "Requests", color = "#1f77b4" }],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count",
              "LoadBalancer", var.alb_arn_suffix,
            { stat = "Sum", label = "5XX Errors", color = "#d62728" }]
          ]
        }
      },
      # Row 2: RDS + Latency
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "RDS Connections & CPU"
          region = var.region
          period = 300
          stat   = "Average"
          metrics = [
            ["AWS/RDS", "DatabaseConnections",
              "DBInstanceIdentifier", var.db_instance_identifier,
            { label = "Connections" }],
            ["AWS/RDS", "CPUUtilization",
              "DBInstanceIdentifier", var.db_instance_identifier,
            { label = "CPU %" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "ALB Response Latency"
          region = var.region
          period = 60
          stat   = "p95"
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime",
              "LoadBalancer", var.alb_arn_suffix,
            { label = "p95 latency (seconds)" }]
          ]
          annotations = {
            horizontal = [{
              value = 2
              label = "2s threshold"
              color = "#d62728"
            }]
          }
        }
      },
      # Row 3: Alarm status + Recent errors
      {
        type   = "alarm"
        x      = 0
        y      = 12
        width  = 12
        height = 6
        properties = {
          title  = "Alarm Status"
          region = var.region
          alarms = [
            aws_cloudwatch_metric_alarm.ecs_high_cpu.arn,
            aws_cloudwatch_metric_alarm.ecs_high_memory.arn,
            aws_cloudwatch_metric_alarm.alb_5xx_errors.arn,
            aws_cloudwatch_metric_alarm.alb_high_latency.arn,
            aws_cloudwatch_metric_alarm.rds_high_cpu.arn,
            aws_cloudwatch_metric_alarm.rds_low_storage.arn,
            aws_cloudwatch_metric_alarm.collector_errors.arn,
            aws_cloudwatch_metric_alarm.collector_duration.arn,
            aws_cloudwatch_composite_alarm.service_degraded.arn
          ]
        }
      },
      {
        type   = "log"
        x      = 12
        y      = 12
        width  = 12
        height = 6
        properties = {
          title  = "Recent Application Errors"
          region = var.region
          query  = "SOURCE '${var.log_group_name}' | fields @timestamp, @message | filter @message like /ERROR/ or @message like /Exception/ | sort @timestamp desc | limit 20"
          region = var.region
          view   = "table"
        }
      }
    ]
  })
}

# ── AWS BUDGET ───────────────────────────────────────────────────────────
resource "aws_budgets_budget" "main" {
  name         = "${var.monitor_prefix}-monthly-budget"
  budget_type  = "COST"
  limit_amount = var.monthly_budget_limit
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 80
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.alerts.arn]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.alerts.arn]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    notification_type         = "FORECASTED"
    subscriber_sns_topic_arns = [aws_sns_topic.alerts.arn]
  }
}
