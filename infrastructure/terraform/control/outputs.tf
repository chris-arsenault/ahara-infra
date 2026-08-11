output "ahara_infra_deployment_revision" {
  description = "Revision of the active ahara-infra deployer permissions"
  value = sha256(join(":", [
    module.ahara_infra_project.deployment_revision,
    aws_iam_role_policy.ahara_infra_platform_migrations.policy,
  ]))
}
