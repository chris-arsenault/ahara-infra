# ahara-infra

Consolidated Terraform + Rust Lambda infrastructure for Ahara.

## Quick start

```bash
# Build all Rust Lambdas
cd backend && cargo lambda build --release

# Apply the full stack (control + network + services in one state)
./scripts/deploy.sh
```

## Layers

| Layer | Owns | Terraform path |
|---|---|---|
| control | OIDC provider, deployer IAM roles, policy library, per-project deployer modules | `infrastructure/terraform/control/` |
| network | VPC, subnets, NAT, ALB, WireGuard, Route53, WAF, CloudFront reverse proxy | `infrastructure/terraform/network/` |
| services | Cognito, RDS, 7 Rust Lambdas (auth-trigger, ci-ingest, cors-handler, db-migrate, db-migrate-truenas, komodo-proxy, og-server) | `infrastructure/terraform/services/` |

All three layers share a single Terraform state (`ahara/infra.tfstate` in
`tfstate-559098897826`) and are applied as one operation.

## Integration

Consumer projects depend on:
- Tag-based network lookups (VPC, ALB, SGs) via `ahara-tf-patterns/modules/platform-context`
- SSM under `/ahara/cognito/*`, `/ahara/rds/*`, `/ahara/db/<project>/*`
- Route53 zone `ahara.io.`

See [`ahara-tf-patterns`](https://github.com/chris-arsenault/ahara-tf-patterns) for the
reusable module library that consuming projects use, and the `ahara` index
repo's `INTEGRATION.md` for the full handshake contract.
