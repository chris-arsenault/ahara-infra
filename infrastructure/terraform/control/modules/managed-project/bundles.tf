# Module bundles — map ahara-tf-patterns module names to the set of policy
# primitives they need. Projects declare which shared modules they use via
# `module_bundles`, and we expand that to the full primitive set.
#
# When a shared module's resource usage changes (e.g. the website module
# starts creating CloudFront Functions), update the corresponding bundle
# here and all consumers automatically pick up the new permissions on the
# next ahara-control deploy.

locals {
  bundle_expansions = {
    website = toset([
      "s3-website",
      "cloudfront-distribution",
      "acm-dns",
      "wafv2",
      "kms-admin",
      "iam-roles",
      "lambda-deploy", # for the optional OG server Lambda
    ])

    "alb-api" = toset([
      "lambda-deploy",
      "alb-target-group",
      "acm-dns",
      "iam-roles",
    ])

    "cognito-app" = toset([
      "cognito-client",
    ])

    lambda = toset([
      "lambda-deploy",
      "iam-roles",
    ])
  }

  # Validate that every requested bundle is known
  unknown_bundles = setsubtract(var.module_bundles, keys(local.bundle_expansions))

  # Expand bundles into the full set of primitive policies, then union with
  # the caller's explicit policy_modules
  expanded_bundle_policies = toset(flatten([
    for bundle in var.module_bundles : tolist(local.bundle_expansions[bundle])
  ]))

  effective_policy_modules = setunion(var.policy_modules, local.expanded_bundle_policies)
}

# Fail fast if an unknown bundle is passed
check "module_bundles_valid" {
  assert {
    condition     = length(local.unknown_bundles) == 0
    error_message = "Unknown module_bundles: ${join(", ", tolist(local.unknown_bundles))}. Valid bundles: ${join(", ", sort(keys(local.bundle_expansions)))}"
  }
}
