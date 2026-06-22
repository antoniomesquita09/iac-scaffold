# IAM Roles

Five IAM roles/users are required to run this stack. This document lists each one with its trust policy, permissions, and creation instructions.

---

## Overview

| Name | Type | Used by |
|---|---|---|
| `TerraformDeployUser` | IAM User | You, when running `terraform apply` locally |
| `GitHubActionsDeployRole` | IAM Role (OIDC) | All GitHub Actions workflows |
| `<project>-ecs-execution-role` | IAM Role | ECS control plane (pull images, write logs) |
| `<project>-ecs-task-role` | IAM Role | Your running Go application |
| `rds-enhanced-monitoring` | IAM Role | RDS Enhanced Monitoring (optional) |

Roles 3 and 4 are **created automatically by Terraform** (`infra/backend/iam.tf`).  
Roles 1, 2, and 5 must be created manually.

---

## 1. Terraform Execution User (`TerraformDeployUser`)

Used for running `terraform plan` and `terraform apply` from your laptop. Not used in CI (CI uses OIDC).

### Create via AWS console

1. IAM → Users → Create user → name: `terraform-deploy`
2. Attach the inline policy below
3. Security credentials → Create access key → CLI → save key ID + secret
4. Run `aws configure` with those credentials

### Permissions policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ComputeAndNetworking",
      "Effect": "Allow",
      "Action": [
        "ec2:*",
        "ecs:*",
        "ecr:*",
        "elasticloadbalancing:*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "Database",
      "Effect": "Allow",
      "Action": ["rds:*"],
      "Resource": "*"
    },
    {
      "Sid": "DNS",
      "Effect": "Allow",
      "Action": ["route53:*", "acm:*"],
      "Resource": "*"
    },
    {
      "Sid": "Storage",
      "Effect": "Allow",
      "Action": ["s3:*", "cloudfront:*"],
      "Resource": "*"
    },
    {
      "Sid": "Secrets",
      "Effect": "Allow",
      "Action": ["secretsmanager:*"],
      "Resource": "*"
    },
    {
      "Sid": "Logging",
      "Effect": "Allow",
      "Action": ["logs:*"],
      "Resource": "*"
    },
    {
      "Sid": "IAMForECSRoles",
      "Effect": "Allow",
      "Action": ["iam:*"],
      "Resource": "*"
    },
    {
      "Sid": "TerraformStateLock",
      "Effect": "Allow",
      "Action": ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"],
      "Resource": "arn:aws:dynamodb:*:*:table/*-tfstate-lock"
    }
  ]
}
```

> **Security note:** These are broad permissions suitable for a personal/small-team setup. For stricter environments, scope each `Resource` to specific ARNs (e.g. `arn:aws:s3:::myapp-*`).

---

## 2. GitHub Actions OIDC Role (`GitHubActionsDeployRole`)

Used by **all four GitHub Actions workflows** — both Terraform (infra) and app deploys (ECS, S3/CloudFront). Uses OIDC — **no long-lived credentials stored in GitHub**.

This role needs two sets of permissions:
- **Terraform permissions** — to create/modify/destroy all AWS resources (used by `infra-backend.yml` and `infra-frontend.yml`)
- **Deploy permissions** — to push images to ECR, update ECS, sync S3, invalidate CloudFront (used by `backend-deploy.yml` and `frontend-deploy.yml`)

### Create via AWS console

1. IAM → Roles → Create role
2. Trusted entity type: **Web identity**
3. Identity provider: `token.actions.githubusercontent.com` *(create it first — see [cicd.md](cicd.md))*
4. Audience: `sts.amazonaws.com`
5. Add condition: `token.actions.githubusercontent.com:sub` = `repo:YOUR_ORG/YOUR_REPO:ref:refs/heads/main`
6. Attach the two policies below
7. Name the role `GitHubActionsDeployRole`
8. Copy the role ARN — add it as `AWS_ROLE_ARN` in GitHub Secrets

### Trust policy (auto-generated from steps 2–5)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::YOUR_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
          "token.actions.githubusercontent.com:sub": "repo:YOUR_ORG/YOUR_REPO:ref:refs/heads/main"
        }
      }
    }
  ]
}
```

### Policy 1 — Terraform permissions (for `infra-*.yml` workflows)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ComputeAndNetworking",
      "Effect": "Allow",
      "Action": [
        "ec2:*",
        "ecs:*",
        "ecr:*",
        "elasticloadbalancing:*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "Database",
      "Effect": "Allow",
      "Action": ["rds:*"],
      "Resource": "*"
    },
    {
      "Sid": "DNS",
      "Effect": "Allow",
      "Action": ["route53:*", "acm:*"],
      "Resource": "*"
    },
    {
      "Sid": "Storage",
      "Effect": "Allow",
      "Action": ["s3:*", "cloudfront:*"],
      "Resource": "*"
    },
    {
      "Sid": "Secrets",
      "Effect": "Allow",
      "Action": ["secretsmanager:*"],
      "Resource": "*"
    },
    {
      "Sid": "Logging",
      "Effect": "Allow",
      "Action": ["logs:*"],
      "Resource": "*"
    },
    {
      "Sid": "IAMForECSRoles",
      "Effect": "Allow",
      "Action": ["iam:*"],
      "Resource": "*"
    },
    {
      "Sid": "TerraformStateLock",
      "Effect": "Allow",
      "Action": ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"],
      "Resource": "arn:aws:dynamodb:*:*:table/*-tfstate-lock"
    }
  ]
}
```

### Policy 2 — Deploy permissions (for `backend-deploy.yml` and `frontend-deploy.yml`)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ECRAuth",
      "Effect": "Allow",
      "Action": ["ecr:GetAuthorizationToken"],
      "Resource": "*"
    },
    {
      "Sid": "ECRPush",
      "Effect": "Allow",
      "Action": [
        "ecr:BatchCheckLayerAvailability",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:BatchGetImage"
      ],
      "Resource": "arn:aws:ecr:*:YOUR_ACCOUNT_ID:repository/YOUR_PROJECT_NAME"
    },
    {
      "Sid": "ECSDeploy",
      "Effect": "Allow",
      "Action": [
        "ecs:RegisterTaskDefinition",
        "ecs:UpdateService",
        "ecs:DescribeServices",
        "ecs:DescribeTaskDefinition",
        "ecs:DescribeTasks",
        "ecs:ListTasks"
      ],
      "Resource": "*"
    },
    {
      "Sid": "PassRoleToECS",
      "Effect": "Allow",
      "Action": ["iam:PassRole"],
      "Resource": [
        "arn:aws:iam::YOUR_ACCOUNT_ID:role/YOUR_PROJECT_NAME-ecs-execution-role",
        "arn:aws:iam::YOUR_ACCOUNT_ID:role/YOUR_PROJECT_NAME-ecs-task-role"
      ]
    },
    {
      "Sid": "S3Deploy",
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:GetBucketLocation",
        "s3:GetObject"
      ],
      "Resource": [
        "arn:aws:s3:::YOUR_PROJECT_NAME-frontend-*",
        "arn:aws:s3:::YOUR_PROJECT_NAME-frontend-*/*"
      ]
    },
    {
      "Sid": "CloudFrontInvalidate",
      "Effect": "Allow",
      "Action": ["cloudfront:CreateInvalidation"],
      "Resource": "*"
    }
  ]
}
```

> You can combine both policies into a single inline policy or attach them as two separate managed policies — either works. Replace `YOUR_ACCOUNT_ID`, `YOUR_ORG/YOUR_REPO`, and `YOUR_PROJECT_NAME` with actual values.

---

## 3. ECS Task Execution Role (`<project>-ecs-execution-role`)

**Created automatically by Terraform** in `infra/backend/iam.tf`. No manual steps needed.

Used by the ECS control plane to:
- Pull container images from ECR
- Write logs to CloudWatch
- Read the `DATABASE_URL` secret from Secrets Manager

Attached policies:
- `arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy` (managed)
- Inline policy granting `secretsmanager:GetSecretValue` on the `<project>/db-url` secret

---

## 4. ECS Task Role (`<project>-ecs-task-role`)

**Created automatically by Terraform** in `infra/backend/iam.tf`. No manual steps needed.

This is the role your **Go application** runs as. It starts empty — add permissions here as your app grows.

Common additions to make in `infra/backend/iam.tf`:

```hcl
# Example: allow the app to send emails via SES
resource "aws_iam_role_policy" "ecs_task_ses" {
  name = "${var.project_name}-ecs-task-ses"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ses:SendEmail", "ses:SendRawEmail"]
      Resource = "*"
    }]
  })
}

# Example: allow the app to read/write a specific S3 bucket
resource "aws_iam_role_policy" "ecs_task_s3" {
  name = "${var.project_name}-ecs-task-s3"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject"]
      Resource = "arn:aws:s3:::my-uploads-bucket/*"
    }]
  })
}
```

---

## 5. RDS Enhanced Monitoring Role (optional)

Only needed if you enable `monitoring_interval` on the RDS instance (provides OS-level metrics in CloudWatch). Not enabled by default in this scaffold.

### Create via AWS console

1. IAM → Roles → Create role
2. Trusted entity: **AWS service** → use case: **RDS** → RDS - Enhanced Monitoring
3. Attach managed policy: `arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole`
4. Name it `rds-enhanced-monitoring`

### Enable in Terraform

Add to `aws_db_instance` in `infra/backend/rds.tf`:

```hcl
monitoring_interval = 60
monitoring_role_arn = "arn:aws:iam::YOUR_ACCOUNT_ID:role/rds-enhanced-monitoring"
```
