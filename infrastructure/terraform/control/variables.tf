data "aws_ssm_parameter" "github_pat" {
  name = "/ahara/control/github-pat"
}

locals {
  github_pat = nonsensitive(data.aws_ssm_parameter.github_pat.value)
}
