# =============================================================================
# aws_backup_lifecycle.tf
# -----------------------------------------------------------------------------
# Terraform configuration for AWS Backup lifecycle policies.
# Creates backup plans with daily, weekly, and monthly retention rules
# across multiple resource tiers.
#
# Author: Manicharan Ravi
# =============================================================================

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "aws_region"    { default = "eu-central-1" }
variable "environment"   { default = "production" }
variable "alert_email"   { default = "ops@company.com" }

provider "aws" {
  region = var.aws_region
}

# ── IAM Role for AWS Backup ────────────────────────────────────────────────────
resource "aws_iam_role" "backup_role" {
  name = "aws-backup-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "backup.amazonaws.com" }
    }]
  })

  tags = { Environment = var.environment, ManagedBy = "Terraform" }
}

resource "aws_iam_role_policy_attachment" "backup_policy" {
  role       = aws_iam_role.backup_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_iam_role_policy_attachment" "restore_policy" {
  role       = aws_iam_role.backup_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

# ── Backup Vault ───────────────────────────────────────────────────────────────
resource "aws_backup_vault" "main" {
  name = "backup-vault-${var.environment}"
  tags = { Environment = var.environment, ManagedBy = "Terraform" }
}

# ── Backup Plan — Critical Tier (RTO: 2h / RPO: 1h) ──────────────────────────
resource "aws_backup_plan" "critical" {
  name = "backup-plan-critical-${var.environment}"

  rule {
    rule_name         = "hourly-backup"
    target_vault_name = aws_backup_vault.main.name
    schedule          = "cron(0 * * * ? *)"    # Every hour
    start_window      = 60
    completion_window = 120

    lifecycle {
      delete_after = 7    # Keep hourly backups for 7 days
    }
  }

  rule {
    rule_name         = "daily-backup"
    target_vault_name = aws_backup_vault.main.name
    schedule          = "cron(0 2 * * ? *)"    # Daily at 02:00 UTC
    start_window      = 60
    completion_window = 180

    lifecycle {
      delete_after = 30   # Keep daily backups for 30 days
    }

    copy_action {
      destination_vault_arn = aws_backup_vault.dr.arn   # Cross-region DR copy
      lifecycle {
        delete_after = 30
      }
    }
  }

  rule {
    rule_name         = "monthly-backup"
    target_vault_name = aws_backup_vault.main.name
    schedule          = "cron(0 3 1 * ? *)"    # 1st of each month at 03:00 UTC
    start_window      = 60
    completion_window = 360

    lifecycle {
      delete_after = 365  # Keep monthly backups for 1 year
    }
  }

  tags = { Tier = "critical", ManagedBy = "Terraform" }
}

# ── Backup Plan — Standard Tier (RTO: 4h / RPO: 4h) ─────────────────────────
resource "aws_backup_plan" "standard" {
  name = "backup-plan-standard-${var.environment}"

  rule {
    rule_name         = "daily-backup"
    target_vault_name = aws_backup_vault.main.name
    schedule          = "cron(0 3 * * ? *)"
    start_window      = 60
    completion_window = 180

    lifecycle {
      delete_after = 14
    }
  }

  rule {
    rule_name         = "weekly-backup"
    target_vault_name = aws_backup_vault.main.name
    schedule          = "cron(0 4 ? * SUN *)"  # Every Sunday at 04:00 UTC
    start_window      = 60
    completion_window = 360

    lifecycle {
      delete_after = 90
    }
  }

  tags = { Tier = "standard", ManagedBy = "Terraform" }
}

# ── DR Vault (different region) ───────────────────────────────────────────────
resource "aws_backup_vault" "dr" {
  provider = aws.dr
  name     = "backup-vault-dr-${var.environment}"
  tags     = { Environment = var.environment, Purpose = "DR", ManagedBy = "Terraform" }
}

provider "aws" {
  alias  = "dr"
  region = "eu-west-1"   # DR region
}

# ── SNS Alert for Backup Failures ─────────────────────────────────────────────
resource "aws_sns_topic" "backup_alerts" {
  name = "backup-alerts-${var.environment}"
}

resource "aws_sns_topic_subscription" "email_alert" {
  topic_arn = aws_sns_topic.backup_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ── Outputs ───────────────────────────────────────────────────────────────────
output "backup_vault_arn"       { value = aws_backup_vault.main.arn }
output "backup_role_arn"        { value = aws_iam_role.backup_role.arn }
output "backup_alert_topic_arn" { value = aws_sns_topic.backup_alerts.arn }
