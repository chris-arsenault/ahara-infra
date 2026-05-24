# ahara-infra

Consolidated AWS infrastructure for the Ahara platform. Replaces the three
previous split repos (`platform-control`, `platform-network`, `platform-services`)
with a single Terraform root state plus three internal layer modules.

## Layout

```
infrastructure/terraform/
├── main.tf         # provider, backend, module calls
├── locals.tf       # prefix = "ahara"
├── control/        # IAM, OIDC, deployer roles, policy library
├── network/        # VPC, subnets, ALB, WireGuard, NAT, SGs, Route53
└── services/       # Cognito, RDS, auth-trigger, db-migrate, CORS,
                    # CI-ingest, komodo-proxy, observability, OG server
backend/            # Rust Lambda workspace (7 crates)
db/migrations/      # Platform-level migrations (ci_builds, etc.)
scripts/deploy.sh   # cargo lambda build + terraform apply
```

## Module dependency graph (DAG)

```
control   ->  standalone (IAM, OIDC, policy library)
network   ->  standalone (VPC, SGs, ALB, WG, NAT)
services  ->  depends on network (takes VPC, subnets, ALB, SGs as inputs)
```

No circular dependencies. Cross-layer references use direct module outputs
(not SSM parameters), so `terraform apply` resolves ordering via the graph.

## Public contracts (consumed by other repos)

**Tag-based network lookups** — used by `ahara-tf-patterns/modules/platform-context`:
- `vpc:role = "ahara"` on VPC
- `lb:role = "ahara"` on ALB
- `subnet:access = "private"` on private subnets
- `sg:role = "lambda"` + `sg:scope = "ahara"` on the shared Lambda SG
- `sg:role = "vpn-client"` + `sg:scope = "ahara"` on the VPN client SG

**SSM parameters** — published by the services layer:
- `/ahara/cognito/*` — user pool ID/ARN/domain/issuer, client IDs
- `/ahara/rds/*` — endpoint, address, port, master creds, SG id
- `/ahara/db/<project>/*` — per-project app creds (published by db-migrate Lambda)
- `/ahara/auth-trigger/clients/*` — client ID → project key map (written by consumers)
- `/ahara/sonarqube/*`, `/ahara/truenas/*`, `/ahara/komodo/*` — operational params
- `/ahara/og-server/*` — OG Lambda artifact location

**Route53** — `ahara.io.` zone looked up by name (not SSM).

## Deploy

```bash
./scripts/deploy.sh
```

Single apply. No two-pass. No bootstrap variable. `terraform apply` figures
out the order via the module dependency graph.

## Pre-commit CI check

**Run `make ci` before committing any change.** This runs the same lint,
format, typecheck, and test steps as GitHub Actions. Do not commit if it fails.
