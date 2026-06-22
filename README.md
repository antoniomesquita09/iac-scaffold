# IaC Scaffold

Terraform scaffold to deploy a Golang backend and Next.js static frontend to AWS.

## Architecture

```
                        ┌─────────────────────────────────────────┐
                        │                  AWS                     │
                        │                                          │
  Users ──HTTPS──▶  Route53 ──▶ ALB ──▶ ECS Fargate (Go app)    │
                        │                      │                   │
  Users ──HTTPS──▶  Route53 ──▶ CloudFront ──▶ S3 (Next.js)     │
                        │                      │                   │
                        │               RDS PostgreSQL             │
                        └─────────────────────────────────────────┘
```

**Backend stack:** ECR → ECS Fargate → ALB → Route53 → RDS PostgreSQL  
**Frontend stack:** S3 (static export) → CloudFront → Route53

## Structure

```
iac-scaffold/
├── infra/
│   ├── backend/      # Terraform for Go API (ECS, ECR, ALB, RDS, Route53)
│   └── frontend/     # Terraform for Next.js (S3, CloudFront, Route53)
├── .github/
│   └── workflows/
│       ├── infra-backend.yml    # plan on PR, apply on merge
│       ├── infra-frontend.yml   # plan on PR, apply on merge
│       ├── backend-deploy.yml   # build Go → ECR → ECS
│       └── frontend-deploy.yml  # next build → S3 → CloudFront
└── docs/
    ├── getting-started.md   # Step-by-step first-time setup
    ├── iam-roles.md         # All IAM roles and policy JSON
    └── cicd.md              # GitHub Actions OIDC + Terraform CI setup
```

## Quick start

Read **[docs/getting-started.md](docs/getting-started.md)** — it covers everything from buying a domain to having traffic flowing.

## CI/CD overview

| Workflow | Trigger | What it does |
|---|---|---|
| `infra-backend.yml` | PR touching `infra/backend/**` | Posts `terraform plan` as PR comment |
| `infra-backend.yml` | Merge to main | Runs `terraform apply` |
| `infra-frontend.yml` | PR touching `infra/frontend/**` | Posts `terraform plan` as PR comment |
| `infra-frontend.yml` | Merge to main | Runs `terraform apply` |
| `backend-deploy.yml` | Merge to main touching `app/**` | Build Docker → push ECR → redeploy ECS |
| `frontend-deploy.yml` | Merge to main touching `web/**` | `next build` → S3 sync → CloudFront invalidate |

## Key decisions

| Decision | Choice | Reason |
|---|---|---|
| Compute | ECS Fargate | No EC2 to manage |
| Frontend hosting | S3 + CloudFront | Cheapest, fastest for static exports |
| Secrets | AWS Secrets Manager | Never stored in task definitions |
| CI/CD auth | OIDC (no long-lived keys) | AWS-recommended best practice |
| Terraform in CI | Plan on PR, apply on merge | Review infra diffs before they land |
| Terraform state | S3 + DynamoDB lock | Standard, free |

## IAM roles at a glance

| Role | Used by |
|---|---|
| `TerraformDeployUser` | You, when running `terraform apply` locally |
| `GitHubActionsDeployRole` | All GitHub Actions workflows (OIDC — no passwords) |
| `ecsTaskExecutionRole` | ECS control plane (pull images, write logs) |
| `ecsTaskRole` | Your running Go app (add permissions here) |

See **[docs/iam-roles.md](docs/iam-roles.md)** for full policy JSON.
