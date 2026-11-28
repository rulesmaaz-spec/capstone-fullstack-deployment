terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-south-1"
}

# 1. Remote State Storage (S3 + DynamoDB)
resource "aws_s3_bucket" "tf_state" {
  bucket = "capstone-tfstate-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_versioning" "tf_state_versioning" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_dynamodb_table" "tf_lock" {
  name           = "capstone-tfstate-lock"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "LockID"
  attribute {
    name = "LockID"
    type = "S"
  }
}

# 2. GitHub OIDC Provider
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# 3. IAM Role for Infrastructure Pipeline
resource "aws_iam_role" "infra_role" {
  name = "github-actions-infra-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          # our GitHub repo 
          "token.actions.githubusercontent.com:sub" = "repo:rulesmaaz-spec/capstone-fullstack-deployment:environment:infrastructure"
        }
      }
    }]
  })
}

# Lab only: Admin access. In production, scope this down!
resource "aws_iam_role_policy_attachment" "infra_admin" {
  role       = aws_iam_role.infra_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# 4. IAM Role for Application Pipeline
resource "aws_iam_role" "app_role" {
  name = "github-actions-app-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:YOUR_GITHUB_USERNAME/YOUR_REPO_NAME:environment:production"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "app_permissions" {
  name = "app-pipeline-permissions"
  role = aws_iam_role.app_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*" },
      { 
        Effect = "Allow", 
        Action = ["ecr:BatchCheckLayerAvailability", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload", "ecr:PutImage", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"], 
        Resource = "arn:aws:ecr:ap-south-1:*:repository/capstone-app" 
      },
      { Effect = "Allow", Action = ["eks:DescribeCluster"], Resource = "*" },
      { Effect = "Allow", Action = ["ssm:GetParameter"], Resource = "arn:aws:ssm:ap-south-1:*:parameter/capstone/*" }
    ]
  })
}

data "aws_caller_identity" "current" {}

output "infra_role_arn" { value = aws_iam_role.infra_role.arn }
output "app_role_arn" { value = aws_iam_role.app_role.arn }
