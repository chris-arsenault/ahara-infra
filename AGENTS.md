# ahara-infra

Consolidated AWS infrastructure for the Ahara platform. Replaces the three
previous split repos (`platform-control`, `platform-network`, `platform-services`)
with a single Terraform root state plus three internal layer modules.

## CRITICAL — Cost analysis is mandatory before adding billable AWS resources

This is a personal AWS account with a baseline of roughly $60/month. An
unreviewed change once added an AWS Private CA (~$400/month) and multiplied the
bill by 7x. That must never happen again.

Before writing Terraform that introduces ANY new AWS resource type not already
present in this repo, or any resource with a fixed hourly/monthly charge:

1. **State the monthly cost** of the resource, citing current AWS pricing.
   "Free tier" or "pay per request" claims must be verified, not assumed.
2. **Flag anything over $10/month explicitly** to the user and get their
   approval BEFORE the resource appears in a plan or apply. Do not bury the
   cost in a summary paragraph — surface it as a direct question.
3. **Never introduce these without explicit user sign-off**, regardless of
   how natural they seem for the design (all carry large fixed costs):
   AWS Private CA / ACM PCA (~$400/mo), NAT Gateway (~$32/mo + data),
   dedicated load balancers beyond the existing shared ALB, VPC endpoints
   (interface type, ~$7/mo each), RDS instance class changes, ElastiCache,
   OpenSearch, EKS control planes, Transit Gateway, Global Accelerator,
   Shield Advanced, static Elastic IPs on new resources, KMS keys beyond
   existing ones, CloudWatch high-resolution/custom metrics at volume,
   Kinesis, MSK, and any "provisioned capacity" mode of any service.
4. **Prefer designs that reuse what exists** (shared ALB, shared Lambda SG,
   existing NAT, SSM parameters, Cognito) over designs that add new billable
   infrastructure. If a design seems to require an expensive managed service,
   present the cost trade-off and at least one cheaper alternative first.

A change that is architecturally elegant but silently adds fixed monthly cost
is a failed change. When in doubt, ask before applying.

## Layout

```
infrastructure/terraform/
├── main.tf         # provider, backend, module calls
├── locals.tf       # prefix = "ahara"
├── control/        # IAM, OIDC, deployer roles, policy library
├── network/        # VPC, subnets, ALB, NAT, SGs, Route53, VPN routes
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
- `/ahara/truenas-roles-anywhere/*` — TrueNAS IAM Roles Anywhere discovery, workload registrations, short-lived enrollment tokens, and the self-managed CA cert/key (the CA is self-managed specifically to avoid AWS Private CA's ~$400/mo fixed cost)
- `/ahara/og-server/*` — OG Lambda artifact location

**Route53** — `ahara.io.` zone looked up by name (not SSM).

**ahara-vpn route contract** — ahara-vpn exclusively owns the WireGuard
endpoint, tunnel secrets, and `wg.ahara.io`. This stack owns only the VPC routes
to the endpoint and resolves its pinned ENI by `eni:role = "wireguard"`.

## Deploy

```bash
./scripts/deploy.sh
```

Single apply. No two-pass. No bootstrap variable. `terraform apply` figures
out the order via the module dependency graph.

## Pre-commit CI check

**Run `make ci` before committing any change.** This runs the same lint,
format, typecheck, and test steps as GitHub Actions. Do not commit if it fails.
