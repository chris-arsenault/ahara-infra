# Grafana Dashboard Deploy Lambda

Direct-invoked platform Lambda for product-owned Grafana dashboard deployment.

Product CI sends dashboard JSON plus folder metadata. The Lambda reads the
Grafana service-account token from SSM, validates the dashboard JSON, ensures
the target folder exists, upserts dashboards, and optionally prunes dashboards
previously managed for the same project.

## Runtime Contract

- Function name is published to
  `/ahara/observability/grafana-dashboard-deployer/function-name`.
- Grafana token is read from
  `/ahara/observability/grafana-dashboard-deployer-token`.
- Product deployer roles need the `grafana-dashboard-deploy` policy module.
- Product repos should declare `observability.dashboards` in `platform.yml`.

The token parameter must contain a Grafana service-account token with folder and
dashboard write permissions. Product repos never receive the token.
