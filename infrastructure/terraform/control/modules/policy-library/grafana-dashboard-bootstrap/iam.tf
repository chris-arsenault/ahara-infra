data "aws_iam_policy_document" "this" {
  statement {
    sid    = "ReadGrafanaDashboardBootstrapFunctionName"
    effect = "Allow"
    actions = [
      "ssm:GetParameter"
    ]
    resources = [
      "arn:aws:ssm:*:${var.account_id}:parameter/ahara/observability/grafana-dashboard-deployer/bootstrap-function-name"
    ]
  }

  statement {
    sid    = "InvokeGrafanaDashboardBootstrap"
    effect = "Allow"
    actions = [
      "lambda:InvokeFunction"
    ]
    resources = [
      "arn:aws:lambda:*:${var.account_id}:function:ahara-grafana-dashboard-bootstrap"
    ]
  }
}
