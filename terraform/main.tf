# main.tf

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ============================================
# 1. VPC (Networking)
# ============================================
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.5.1"

  name = "${var.cluster_name}-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["${var.aws_region}a", "${var.aws_region}b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  # EKS requires these tags so it knows which subnets to use
  enable_nat_gateway   = true
  single_nat_gateway   = true # Keep it to 1 to save costs in this lab
  enable_dns_hostnames = true

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"           = 1
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }

  public_subnet_tags = {
    "kubernetes.io/role/elb"                    = 1
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

# ============================================
# 2. ECR (Container Registry)
# ============================================
resource "aws_ecr_repository" "app_repo" {
  name                 = "capstone-app"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

# ============================================
# 3. EKS (Kubernetes Cluster)
# ============================================
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.8.4"

  cluster_name    = var.cluster_name
  cluster_version = "1.31"

  vpc_id                         = module.vpc.vpc_id
  subnet_ids                     = module.vpc.private_subnets
  cluster_endpoint_public_access = true # So we can connect via kubectl from our laptop

  # EKS Managed Node Group (The EC2 instances that run our Pods)
  eks_managed_node_groups = {
    main = {
      min_size     = 1
      max_size     = 3
      desired_size = 2

      instance_types = ["t3.small"] # Needs at least t3.small for EKS
      capacity_type  = "ON_DEMAND"
    }
  }
}

# ============================================
# 4. RDS (PostgreSQL Database)
# ============================================
resource "aws_db_subnet_group" "db_subnets" {
  name       = "capstone-db-subnets"
  subnet_ids = module.vpc.private_subnets
}

resource "aws_security_group" "rds_sg" {
  name        = "capstone-rds-sg"
  description = "Allow traffic from EKS worker nodes"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"] # Allow traffic from inside the VPC
  }
}

resource "aws_db_instance" "postgres" {
  identifier             = "capstone-db"
  engine                 = "postgres"
  engine_version         = "15"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  db_name                = "tasks"
  username               = "postgres"
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.db_subnets.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot    = true # Required for easy destruction
}

