data "aws_region" "current" {}

resource "aws_cloudwatch_log_group" "reverse_proxy" {
  name              = "/aws/${local.prefix}/reverse-proxy"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "wireguard" {
  name              = "/aws/${local.prefix}/wireguard"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "nat" {
  name              = "/aws/${local.prefix}/nat"
  retention_in_days = 30
}

locals {
  cloudwatch_region = data.aws_region.current.region

  reverse_proxy_logs_query = <<-EOT
SOURCE '/aws/${local.prefix}/reverse-proxy'
| fields @timestamp, @logStream, @message
| sort @timestamp desc
| limit 20
EOT

  wireguard_logs_query = <<-EOT
SOURCE '/aws/${local.prefix}/wireguard'
| filter @logStream like /wg-quick|wg-healthcheck/
| fields @timestamp, @logStream, @message
| sort @timestamp desc
| limit 20
EOT

  nat_logs_query = <<-EOT
SOURCE '/aws/${local.prefix}/nat'
| fields @timestamp, @logStream, @message
| sort @timestamp desc
| limit 20
EOT

  reverse_proxy_metrics = [
    [
      "AWS/EC2",
      "CPUUtilization",
      "AutoScalingGroupName",
      module.reverse_proxy.autoscaling_group_name,
      {
        id     = "m1"
        label  = "Reverse Proxy CPU Utilization"
        region = local.cloudwatch_region
      }
    ],
    [
      "AWS/EC2",
      "NetworkOut",
      "AutoScalingGroupName",
      module.reverse_proxy.autoscaling_group_name,
      {
        id     = "m2"
        label  = "Reverse Proxy Network Out"
        region = local.cloudwatch_region
        yAxis  = "right"
      }
    ]
  ]

  wireguard_metrics = [
    [
      "AWS/EC2",
      "CPUUtilization",
      "AutoScalingGroupName",
      module.wireguard.autoscaling_group_name,
      {
        id     = "m3"
        label  = "WireGuard CPU Utilization"
        region = local.cloudwatch_region
      }
    ],
    [
      "AWS/EC2",
      "NetworkOut",
      "AutoScalingGroupName",
      module.wireguard.autoscaling_group_name,
      {
        id     = "m4"
        label  = "WireGuard Network Out"
        region = local.cloudwatch_region
        yAxis  = "right"
      }
    ]
  ]

  nat_metrics = [
    [
      "AWS/EC2",
      "NetworkOut",
      "AutoScalingGroupName",
      module.nat.autoscaling_group_name,
      {
        id     = "m5"
        label  = "NAT Network Out"
        region = local.cloudwatch_region
      }
    ]
  ]

  status_metrics = [
    [
      "AWS/EC2",
      "StatusCheckFailed",
      "AutoScalingGroupName",
      module.reverse_proxy.autoscaling_group_name,
      {
        id     = "m6"
        label  = "Reverse Proxy Status Checks"
        region = local.cloudwatch_region
      }
    ],
    [
      "AWS/EC2",
      "StatusCheckFailed",
      "AutoScalingGroupName",
      module.nat.autoscaling_group_name,
      {
        id     = "m7"
        label  = "NAT Status Checks"
        region = local.cloudwatch_region
      }
    ]
  ]

  dashboard_widgets = [
    {
      type   = "log"
      x      = 0
      y      = 0
      width  = 8
      height = 6
      properties = {
        query  = local.reverse_proxy_logs_query
        region = local.cloudwatch_region
        title  = "Reverse Proxy Recent Logs"
      }
    },
    {
      type   = "log"
      x      = 8
      y      = 0
      width  = 8
      height = 6
      properties = {
        query  = local.wireguard_logs_query
        region = local.cloudwatch_region
        title  = "WireGuard Recent Logs"
      }
    },
    {
      type   = "log"
      x      = 16
      y      = 0
      width  = 8
      height = 6
      properties = {
        query  = local.nat_logs_query
        region = local.cloudwatch_region
        title  = "NAT Recent Logs"
      }
    },
    {
      type   = "metric"
      x      = 0
      y      = 6
      width  = 12
      height = 6
      properties = {
        metrics = local.reverse_proxy_metrics
        region  = local.cloudwatch_region
        title   = "Reverse Proxy Performance"
        view    = "timeSeries"
        period  = 300
        stacked = false
        stat    = "Average"
      }
    },
    {
      type   = "metric"
      x      = 12
      y      = 6
      width  = 12
      height = 6
      properties = {
        metrics = local.wireguard_metrics
        region  = local.cloudwatch_region
        title   = "WireGuard Performance"
        view    = "timeSeries"
        period  = 300
        stacked = false
        stat    = "Average"
      }
    },
    {
      type   = "metric"
      x      = 0
      y      = 12
      width  = 12
      height = 6
      properties = {
        metrics = local.nat_metrics
        region  = local.cloudwatch_region
        title   = "NAT Throughput"
        view    = "timeSeries"
        period  = 300
        stacked = false
        stat    = "Average"
      }
    },
    {
      type   = "metric"
      x      = 12
      y      = 12
      width  = 12
      height = 6
      properties = {
        metrics = local.status_metrics
        region  = local.cloudwatch_region
        title   = "EC2 Status Health"
        view    = "timeSeries"
        period  = 300
        stacked = false
        stat    = "Average"
      }
    }
  ]
}

resource "aws_cloudwatch_dashboard" "operations" {
  dashboard_name = "${local.prefix}-operations"
  dashboard_body = jsonencode({
    widgets = local.dashboard_widgets
  })
}
