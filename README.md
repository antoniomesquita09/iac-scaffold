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
├── backend/          # Terraform for Go API (ECS, ECR, ALB, RDS, Route53)
├── frontend/         # Terraform for Next.js (S3, CloudFront, Route53)
├── .github/
│   └── workflows/    # GitHub Actions CI/CD
└── docs/
    ├── getting-started.md   # Step-by-step first-time setup
    ├── iam-roles.md         # All IAM roles and policy JSON
    └── cicd.md              # GitHub Actions OIDC setup
```

## Quick start

Read **[docs/getting-started.md](docs/getting-started.md)** — it covers everything from buying a domain to having traffic flowing.

## Key decisions

| Decision | Choice | Reason |
|---|---|---|
| Compute | ECS Fargate | No EC2 to manage |
| Frontend hosting | S3 + CloudFront | Cheapest, fastest for static exports |
| Secrets | AWS Secrets Manager | Never stored in task definitions |
| CI/CD auth | OIDC (no long-lived keys) | AWS-recommended best practice |
| Terraform state | S3 + DynamoDB lock | Standard, free |

## IAM roles at a glance

| Role | Used by |
|---|---|
| `TerraformDeployUser` | You, when running `terraform apply` locally |
| `GitHubActionsDeployRole` | GitHub Actions (via OIDC — no passwords) |
| `ecsTaskExecutionRole` | ECS control plane (pull images, write logs) |
| `ecsTaskRole` | Your running Go app (add permissions here) |

See **[docs/iam-roles.md](docs/iam-roles.md)** for full policy JSON.
