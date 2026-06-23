# Getting Started

This guide walks you through deploying the entire stack from scratch — a first-time setup that takes roughly 30–45 minutes.

---

## What's manual vs. automated

### Manual — one-time bootstrap (this guide)

Do these steps in order before GitHub Actions can take over:

1. [Prerequisites](#prerequisites) — install Terraform, AWS CLI, Docker
2. [Create TerraformDeployUser IAM user + `aws configure`](#step-1--create-an-aws-iam-user-for-terraform)
3. [Buy or delegate domain in Route53](#step-2--register-or-delegate-your-domain-in-route53)
4. [Create S3 state bucket + DynamoDB lock table](#step-3--create-the-terraform-remote-state-bucket)
5. [Configure backend variables](#step-4--configure-backend-variables)
6. [Deploy backend infrastructure — `terraform apply`](#step-5--deploy-the-backend)
7. [Push first Docker image to ECR](#step-6--push-your-first-docker-image)
8. [Configure frontend variables](#step-7--configure-frontend-variables)
9. [Deploy frontend infrastructure — `terraform apply`](#step-8--deploy-the-frontend)
10. [Set up GitHub Actions — OIDC provider, role, secrets](#step-9--set-up-github-actions)
11. [Verify end-to-end](#step-10--verify-end-to-end)

### Automated via GitHub Actions (everything after bootstrap)

See [docs/cicd.md](cicd.md) for the full workflow reference. In short:

- **Infra changes** — open a PR touching `infra/backend/**` or `infra/frontend/**`, review the `terraform plan` comment, merge to apply
- **App deploys** — push to `main`; backend and frontend deploy automatically on file changes

---

## Prerequisites

Install these tools before continuing:

| Tool | Version | Install |
|---|---|---|
| [Terraform](https://developer.hashicorp.com/terraform/downloads) | ≥ 1.6 | `brew install terraform` |
| [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) | v2 | `brew install awscli` |
| [Docker](https://docs.docker.com/get-docker/) | any recent | Docker Desktop |

Verify installations:

```bash
terraform version
aws --version
docker --version
```

---

## Step 1 — Create an AWS IAM user for Terraform

You need an IAM user (or role) with broad permissions to create all the infrastructure.

1. Go to **IAM → Users → Create user** in the AWS console
2. Name it `terraform-deploy`
3. Attach the permissions listed in [docs/iam-roles.md](iam-roles.md#1-terraform-execution-user-terraformdeployuser)
4. Go to **Security credentials → Create access key** → choose "CLI"
5. Save the **Access Key ID** and **Secret Access Key**

Configure the AWS CLI with those credentials:

```bash
aws configure
# AWS Access Key ID:     <paste key ID>
# AWS Secret Access Key: <paste secret>
# Default region:        us-east-1
# Default output format: json
```

Verify it works:

```bash
aws sts get-caller-identity
```

---

## Step 2 — Register or delegate your domain in Route53

The backend Terraform looks up your hosted zone by domain name, and both stacks create DNS records automatically. The zone must exist before you run `terraform apply`.

### Option A — Buy a new domain through Route53 (simplest)

1. Go to **Route53 → Registered domains → Register domain**
2. Search for your domain, purchase it
3. AWS automatically creates a hosted zone — note the **Hosted Zone ID** (starts with `Z`)

### Option B — Use a domain registered elsewhere

1. In Route53, go to **Hosted Zones → Create hosted zone**
2. Enter your domain name, type: Public
3. After creation, copy the 4 **NS records** shown
4. Log into your registrar and update the domain's nameservers to those 4 values
5. DNS propagation can take up to 48 hours (usually under 1 hour)

Either way, confirm your zone exists:

```bash
aws route53 list-hosted-zones-by-name --dns-name example.com
```

Note the **Hosted Zone ID** — you will need it for the frontend `terraform.tfvars` and GitHub variables.

---

## Step 3 — Create the Terraform remote state bucket

Terraform stores its state in S3 and uses DynamoDB to prevent simultaneous applies.  
Run these commands once — replace `myapp` with your project name:

```bash
# State bucket (versioned so you can recover old state)
aws s3api create-bucket \
  --bucket myapp-tfstate \
  --region us-east-1

aws s3api put-bucket-versioning \
  --bucket myapp-tfstate \
  --versioning-configuration Status=Enabled

aws s3api put-public-access-block \
  --bucket myapp-tfstate \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# DynamoDB lock table
aws dynamodb create-table \
  --table-name myapp-tfstate-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

Now update both `backend.tf` files with your actual bucket and table names:

```bash
# infra/backend/backend.tf  and  infra/frontend/backend.tf
bucket         = "myapp-tfstate"
dynamodb_table = "myapp-tfstate-lock"
```

---

## Step 4 — Configure backend variables

```bash
cd infra/backend
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
aws_region        = "us-east-1"
project_name      = "myapp"           # short, lowercase, no spaces
domain_name       = "example.com"     # your actual domain
api_subdomain     = "api"             # → api.example.com
app_port          = 8080
app_count         = 1
fargate_cpu       = 256
fargate_memory    = 512
db_name           = "appdb"
db_username       = "appuser"
db_instance_class = "db.t3.micro"
```

> There is **no `db_password`** — RDS generates and manages the master password in Secrets Manager (`manage_master_user_password = true`), so it never lands in `terraform.tfvars` or in the Terraform state. Keep `terraform.tfvars` out of git anyway (it's in `.gitignore`).

---

## Step 5 — Deploy the backend

```bash
cd infra/backend
terraform init
terraform plan    # review what will be created
terraform apply   # type 'yes' to confirm
```

This creates (in order): VPC → public subnets → internet gateway → security groups → ECR → IAM roles → RDS → ALB → ACM cert → ECS cluster → Route53 records.

**Takes ~15 minutes** — mostly waiting for RDS to provision and ACM to validate DNS.

After apply, note the outputs:

```bash
terraform output
```

Key values to save for later:
- `ecr_repository_url` — your Docker push target
- `ecs_cluster_name`, `ecs_service_name`, `ecs_task_definition_family`, `container_name` — for GitHub Actions
- `db_host` — RDS host, for the migration job (GitHub variable `DB_HOST`)
- `db_secret_arn` — RDS-managed secret ARN, for the migration job (GitHub variable `DB_SECRET_ARN`)

> **How the app gets its DB credentials:** the ECS task receives `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER` and `DB_SSLMODE` as plain environment variables, plus `DB_PASSWORD` injected from the RDS-managed secret. Your app should build its own connection string from these — it does **not** receive a ready-made `DATABASE_URL`.

---

## Step 6 — Push your first Docker image

The ECS service starts but will fail health checks until a real image is in ECR. Do this bootstrap push once:

```bash
# From your Go project directory (where your Dockerfile lives)
ECR_URL=$(cd /path/to/iac-scaffold/infra/backend && terraform output -raw ecr_repository_url)
REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Authenticate Docker to ECR
aws ecr get-login-password --region $REGION | \
  docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

# Build and push
docker build -t $ECR_URL:latest ./app
docker push $ECR_URL:latest
```

Then force ECS to redeploy:

```bash
aws ecs update-service \
  --cluster myapp-cluster \
  --service myapp-service \
  --force-new-deployment \
  --region us-east-1
```

Wait ~2 minutes, then test:

```bash
curl https://api.example.com/health
```

---

## Step 7 — Configure frontend variables

```bash
cd ../../infra/frontend
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
aws_region      = "us-east-1"
project_name    = "myapp"
domain_name     = "example.com"
route53_zone_id = "Z0123456789ABCDEFGHIJ"   # from Step 2
```

Also configure your Next.js project for static export. In `next.config.js`:

```js
/** @type {import('next').NextConfig} */
const nextConfig = {
  output: 'export',
  trailingSlash: true,   // ensures S3/CloudFront routing works correctly
}

module.exports = nextConfig
```

---

## Step 8 — Deploy the frontend

```bash
cd infra/frontend
terraform init
terraform plan
terraform apply
```

This creates: S3 bucket → CloudFront distribution → ACM certificate (us-east-1) → Route53 records.

**Takes ~10 minutes** — mostly waiting for CloudFront to deploy globally.

Note the outputs:

```bash
terraform output
```

Key values:
- `s3_bucket_name` → GitHub Actions variable `S3_BUCKET`
- `cloudfront_distribution_id` → GitHub Actions variable `CF_DISTRIBUTION_ID`

---

## Step 9 — Set up GitHub Actions

Follow **[docs/cicd.md](cicd.md)** to configure OIDC authentication and add the required secrets/variables to your GitHub repository.

---

## Step 10 — Verify end-to-end

```bash
# Backend
curl -s https://api.example.com/health

# Frontend
curl -sI https://example.com | head -5
```

Both should return HTTP 200.

---

## Useful commands

```bash
# View running ECS tasks
aws ecs list-tasks --cluster myapp-cluster

# Tail container logs
aws logs tail /ecs/myapp --follow

# Force redeploy without a code change
aws ecs update-service \
  --cluster myapp-cluster \
  --service myapp-service \
  --force-new-deployment

# Invalidate CloudFront cache manually
aws cloudfront create-invalidation \
  --distribution-id <id> \
  --paths "/*"

# Destroy everything (be careful!)
cd infra/backend && terraform destroy
cd infra/frontend && terraform destroy
```

---

## Estimated monthly cost (us-east-1, minimal config)

| Resource | Cost |
|---|---|
| ECS Fargate (256 CPU / 512 MB, 1 task) | ~$9 |
| RDS db.t3.micro PostgreSQL | ~$15 |
| ALB | ~$16 |
| S3 + CloudFront (low traffic) | ~$1 |
| Route53 hosted zone | $0.50 |
| **Total** | **~$41/month** |

> **Networking note (cost & simplicity trade-off):** everything runs in public subnets, so there's no NAT Gateway (~$32/mo saved). ECS tasks get a public IP (`assign_public_ip = true`) but inbound is still restricted to the ALB via security groups. The **RDS instance is publicly reachable** (`publicly_accessible = true`) so migrations can run from GitHub Actions — it's protected by its security group and the RDS-managed master password. For production, consider: move ECS tasks and RDS to private subnets (add a NAT Gateway, set `assign_public_ip = false`, `publicly_accessible = false`), restrict the RDS security group to known IPs, and run migrations via an in-VPC ECS run-task instead.

> **Migrations:** schema migrations run automatically in `backend-deploy.yml` (Flyway, before the new image deploys). Put your `.sql` files in a `migrations/` directory — see [docs/cicd.md](cicd.md).
