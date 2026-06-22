# CI/CD with GitHub Actions

There are four workflows in `.github/workflows/`:

| Workflow | Trigger | What it does |
|---|---|---|
| `infra-backend.yml` | PR touching `infra/backend/**` | Posts `terraform plan` as PR comment |
| `infra-backend.yml` | Merge to `main` | Runs `terraform apply` |
| `infra-frontend.yml` | PR touching `infra/frontend/**` | Posts `terraform plan` as PR comment |
| `infra-frontend.yml` | Merge to `main` | Runs `terraform apply` |
| `backend-deploy.yml` | Merge to `main` touching `app/**` | Build Docker → ECR → redeploy ECS |
| `frontend-deploy.yml` | Merge to `main` touching `web/**` | `next build` → S3 sync → CloudFront invalidate |

All workflows use **OIDC** to authenticate with AWS — no long-lived credentials stored as GitHub secrets.

---

## How OIDC works

```
GitHub Actions runner
        │
        │  1. Request short-lived OIDC token from GitHub
        ▼
  GitHub OIDC Provider
        │
        │  2. Provide JWT signed by GitHub
        ▼
  AWS IAM (STS AssumeRoleWithWebIdentity)
        │
        │  3. Verify JWT against GitHub's public keys
        │  4. Check subject claim matches your repo/branch
        │  5. Issue temporary credentials (1 hour TTL)
        ▼
  GitHub Actions step runs with those credentials
```

Result: no `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` stored anywhere.

---

## Step 1 — Add the GitHub OIDC provider to your AWS account

This only needs to be done once per AWS account.

### Via AWS console

1. Go to **IAM → Identity providers → Add provider**
2. Provider type: **OpenID Connect**
3. Provider URL: `https://token.actions.githubusercontent.com`
4. Click **Get thumbprint**
5. Audience: `sts.amazonaws.com`
6. Click **Add provider**

### Via AWS CLI

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

---

## Step 2 — Create the `GitHubActionsDeployRole`

Follow the instructions in [docs/iam-roles.md](iam-roles.md#2-github-actions-oidc-role-githubactionsdeployrole).

After creating the role, copy its ARN:

```
arn:aws:iam::YOUR_ACCOUNT_ID:role/GitHubActionsDeployRole
```

---

## Step 3 — Configure GitHub repository secrets and variables

Go to your GitHub repo → **Settings → Secrets and variables → Actions**.

### Secrets (sensitive — encrypted, never visible in logs)

| Secret name | Value |
|---|---|
| `AWS_ROLE_ARN` | `arn:aws:iam::YOUR_ACCOUNT_ID:role/GitHubActionsDeployRole` |
| `TF_VAR_DB_PASSWORD` | Your database password |

### Variables (non-sensitive — visible in logs)

**Shared:**

| Variable | Value |
|---|---|
| `AWS_REGION` | `us-east-1` |
| `TF_VAR_AWS_REGION` | `us-east-1` |
| `TF_VAR_PROJECT_NAME` | `myapp` |
| `TF_VAR_DOMAIN_NAME` | `example.com` |

**Backend-specific** (from `terraform output` in `infra/backend/`):

| Variable | Source | Example |
|---|---|---|
| `TF_VAR_API_SUBDOMAIN` | your choice | `api` |
| `TF_VAR_APP_PORT` | your Go app | `8080` |
| `TF_VAR_APP_COUNT` | your choice | `1` |
| `TF_VAR_FARGATE_CPU` | your choice | `256` |
| `TF_VAR_FARGATE_MEMORY` | your choice | `512` |
| `TF_VAR_DB_NAME` | your choice | `appdb` |
| `TF_VAR_DB_USERNAME` | your choice | `appuser` |
| `TF_VAR_DB_INSTANCE_CLASS` | your choice | `db.t3.micro` |
| `ECR_REPOSITORY` | `terraform output ecr_repository_url` | `123456789.dkr.ecr.us-east-1.amazonaws.com/myapp` |
| `ECS_CLUSTER` | `terraform output ecs_cluster_name` | `myapp-cluster` |
| `ECS_SERVICE` | `terraform output ecs_service_name` | `myapp-service` |
| `ECS_TASK_DEFINITION` | `terraform output ecs_task_definition_family` | `myapp` |
| `CONTAINER_NAME` | `terraform output container_name` | `myapp` |

**Frontend-specific** (from `terraform output` in `infra/frontend/`):

| Variable | Source | Example |
|---|---|---|
| `TF_VAR_ROUTE53_ZONE_ID` | Route53 console | `Z0123456789ABCDEFGHIJ` |
| `S3_BUCKET` | `terraform output s3_bucket_name` | `myapp-frontend-123456789` |
| `CF_DISTRIBUTION_ID` | `terraform output cloudfront_distribution_id` | `E1234ABCDE` |
| `NEXT_PUBLIC_API_URL` | your API URL | `https://api.example.com` |

---

## Step 4 — Update path filters

The app deploy workflows trigger on changes to your app directories. Update the `paths:` filters to match your repo layout:

**`backend-deploy.yml`** — change `app/**` to wherever your Go code lives:
```yaml
paths:
  - 'app/**'           # ← update to your Go project directory
```

**`frontend-deploy.yml`** — change `web/**` to wherever your Next.js project lives:
```yaml
paths:
  - 'web/**'           # ← update to your Next.js project directory
```

Also update `working-directory` in `frontend-deploy.yml` to match:
```yaml
- name: Install dependencies
  working-directory: web    # ← update this
```

---

## Deployment flows

### Infrastructure change (PR → merge)

```
Open PR with infra/backend/** changes
     │
     ▼
infra-backend.yml (plan job)
  terraform init + validate + plan
  Post plan diff as PR comment
     │
     ▼
Review plan, merge PR
     │
     ▼
infra-backend.yml (apply job)
  terraform init + apply -auto-approve
     │
     ▼
Infrastructure updated ✓
```

### Backend app deploy

```
Push to main with app/** changes
     │
     ▼
backend-deploy.yml
  docker build → push to ECR
  Render new ECS task definition
  aws ecs update-service (rolling, waits for stability)
     │
     ▼
New Go version live ✓
```

### Frontend deploy

```
Push to main with web/** changes
     │
     ▼
frontend-deploy.yml
  npm ci && npm run build → out/
  aws s3 sync (HTML: no-cache | JS/CSS: 1-year immutable)
  CloudFront invalidation
     │
     ▼
New Next.js version live ✓
```

---

## Troubleshooting

### "Not authorized to perform sts:AssumeRoleWithWebIdentity"

- Check the role's trust policy: the `sub` condition must exactly match `repo:ORG/REPO:ref:refs/heads/main`
- Confirm the OIDC provider exists in IAM in the same account as the role
- Check that `permissions: id-token: write` is set in the workflow

### Terraform plan fails with "Error acquiring the state lock"

A previous run crashed mid-apply. Manually release the lock:

```bash
terraform force-unlock <LOCK_ID>
# Lock ID is shown in the error message
```

### ECS deployment stuck "waiting for service stability"

- Check ECS → Cluster → Service → Events tab in the console
- Common cause: container health check failing on `/health` endpoint
- Check CloudWatch logs: `aws logs tail /ecs/myapp --follow`

### CloudFront still serving old content after deploy

The workflow invalidates `/*` after sync. If you're still seeing old content:
1. Hard refresh your browser (Cmd+Shift+R)
2. Check the invalidation completed: CloudFront → Distributions → Invalidations tab
3. Wait up to 60 seconds for edge propagation
