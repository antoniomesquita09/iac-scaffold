# CI/CD with GitHub Actions

The CI/CD pipeline uses **OIDC (OpenID Connect)** to authenticate GitHub Actions with AWS — no long-lived credentials stored as GitHub secrets.

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
        │  3. Verify JWT signature against GitHub's public keys
        │  4. Check subject claim matches your repo/branch
        │  5. Issue temporary AWS credentials (1 hour TTL)
        ▼
  GitHub Actions step runs with those credentials
```

Result: no `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` stored anywhere. The temporary credentials expire automatically.

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

Verify:

```bash
aws iam list-open-id-connect-providers
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

### Secrets (sensitive — encrypted)

| Secret name | Value |
|---|---|
| `AWS_ROLE_ARN` | `arn:aws:iam::YOUR_ACCOUNT_ID:role/GitHubActionsDeployRole` |

### Variables (non-sensitive — visible in logs)

Run `terraform output` in `backend/` and `frontend/` to get these values:

| Variable name | Where to get it | Example |
|---|---|---|
| `AWS_REGION` | Your choice | `us-east-1` |
| `ECR_REPOSITORY` | `terraform output ecr_repository_url` | `123456789.dkr.ecr.us-east-1.amazonaws.com/myapp` |
| `ECS_CLUSTER` | `terraform output ecs_cluster_name` | `myapp-cluster` |
| `ECS_SERVICE` | `terraform output ecs_service_name` | `myapp-service` |
| `ECS_TASK_DEFINITION` | `terraform output ecs_task_definition_family` | `myapp` |
| `CONTAINER_NAME` | `terraform output container_name` | `myapp` |
| `S3_BUCKET` | `terraform output s3_bucket_name` (frontend) | `myapp-frontend-123456789` |
| `CF_DISTRIBUTION_ID` | `terraform output cloudfront_distribution_id` (frontend) | `E1234ABCDE` |
| `NEXT_PUBLIC_API_URL` | Your API URL | `https://api.example.com` |

---

## Step 4 — Configure path filters for your monorepo

The workflows trigger only when relevant files change. Update the `paths:` filters to match your directory structure:

**`backend-deploy.yml`** — change `app/**` to wherever your Go code lives:
```yaml
paths:
  - 'app/**'                         # ← update this
  - '.github/workflows/backend-deploy.yml'
```

**`frontend-deploy.yml`** — change `web/**` to wherever your Next.js project lives:
```yaml
paths:
  - 'web/**'                         # ← update this
  - '.github/workflows/frontend-deploy.yml'
```

Also update `working-directory` in the frontend workflow to match:
```yaml
- name: Install dependencies
  working-directory: web             # ← update this
```

---

## Deployment flows

### Backend deploy (on push to `main` with Go changes)

```
Push to main
     │
     ▼
Checkout code
     │
     ▼
Assume GitHubActionsDeployRole via OIDC
     │
     ▼
Login to ECR
     │
     ▼
docker build -t <ecr>:<sha> ./app
docker push
     │
     ▼
aws ecs describe-task-definition → task-definition.json
     │
     ▼
Render new task def with updated image URI
     │
     ▼
aws ecs update-service (rolling deploy, waits for stability)
     │
     ▼
Done ✓
```

### Frontend deploy (on push to `main` with Next.js changes)

```
Push to main
     │
     ▼
Checkout code
     │
     ▼
npm ci && npm run build → out/
     │
     ▼
Assume GitHubActionsDeployRole via OIDC
     │
     ▼
aws s3 sync out/ s3://bucket --delete
(HTML: no-cache | JS/CSS: 1-year immutable)
     │
     ▼
aws cloudfront create-invalidation --paths "/*"
     │
     ▼
Done ✓
```

---

## Troubleshooting

### "Not authorized to perform sts:AssumeRoleWithWebIdentity"

- Check the role's trust policy: the `sub` condition must exactly match `repo:ORG/REPO:ref:refs/heads/main`
- Confirm the OIDC provider exists in IAM in the same account as the role
- Check that `permissions: id-token: write` is set in the workflow

### "Error: Cannot connect to the Docker daemon"

Not relevant here — GitHub-hosted runners include Docker. If you're using self-hosted runners, install Docker on them.

### ECS deployment stuck "waiting for service stability"

- Check ECS → Cluster → Service → Events tab in the console
- Common cause: container health check failing on `/health` endpoint
- Check CloudWatch logs: `aws logs tail /ecs/myapp --follow`

### CloudFront still serving old content after deploy

The workflow invalidates `/*` after sync. If you're still seeing old content:
1. Hard refresh your browser (Cmd+Shift+R)
2. Check the invalidation completed: CloudFront → Distributions → Invalidations tab
3. Wait up to 60 seconds for edge propagation
