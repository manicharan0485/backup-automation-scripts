# 🗄️ Backup Automation Scripts

A collection of production-ready scripts and Terraform configs for automating backup workflows across AWS and Azure environments.

Built from real-world experience managing backup and recovery environments for enterprise clients.

---

## 📁 Repository Structure

```
backup-automation-scripts/
├── scripts/
│   ├── rds_snapshot_validator.py       # Validates RDS snapshot integrity
│   ├── restore_test_automation.sh      # Automated restore validation
│   └── backup_status_report.py        # Daily backup status email report
├── alerts/
│   └── cloudwatch_backup_alerts.json  # CloudWatch alarm definitions
├── terraform/
│   └── aws_backup_lifecycle.tf        # AWS Backup lifecycle policy via Terraform
└── README.md
```

---

## 🚀 Features

- ✅ Automated RDS snapshot integrity validation
- ✅ Scheduled restore testing for PostgreSQL and MS-SQL on AWS RDS
- ✅ CloudWatch alerting for backup anomalies (size, status, duration)
- ✅ Daily backup status reporting via email (SES)
- ✅ Terraform-managed AWS Backup lifecycle policies
- ✅ 20% reduction in manual operational effort

---

## 🛠️ Technologies

| Tool | Purpose |
|------|---------|
| Python 3.x | Snapshot validation, reporting |
| Bash/Shell | Restore automation |
| Terraform | Infrastructure as Code |
| AWS Backup | Native backup policies |
| AWS RDS | Database snapshot management |
| AWS CloudWatch | Alerting and monitoring |
| AWS SES | Email notifications |

---

## 🔧 Prerequisites

```bash
pip install boto3 python-dotenv
terraform >= 1.0
aws cli configured with appropriate IAM permissions
```

Required IAM permissions:
- `rds:DescribeDBSnapshots`
- `rds:RestoreDBInstanceFromDBSnapshot`
- `rds:DeleteDBInstance`
- `cloudwatch:PutMetricAlarm`
- `backup:*`

---

## 📋 Usage

### 1. RDS Snapshot Validator
```bash
python scripts/rds_snapshot_validator.py --region eu-central-1 --db-identifier prod-db
```

### 2. Restore Test Automation
```bash
chmod +x scripts/restore_test_automation.sh
./scripts/restore_test_automation.sh prod-db eu-central-1
```

### 3. Backup Status Report
```bash
python scripts/backup_status_report.py --region eu-central-1 --email ops@company.com
```

### 4. Deploy CloudWatch Alerts
```bash
aws cloudformation deploy \
  --template-file alerts/cloudwatch_backup_alerts.json \
  --stack-name backup-alerts \
  --region eu-central-1
```

### 5. Apply Terraform Backup Lifecycle
```bash
cd terraform/
terraform init
terraform plan
terraform apply
```

---

## 📊 RTO / RPO Targets

| Tier | RPO | RTO | Backup Frequency |
|------|-----|-----|-----------------|
| Critical (Production DB) | 1 hour | 2 hours | Every 1 hour (incremental) |
| Standard (App Servers) | 4 hours | 4 hours | Every 4 hours |
| Low (Dev/Test) | 24 hours | 8 hours | Daily |

---

## 🔒 Security

- All snapshots encrypted at rest (AES-256)
- IAM least-privilege for backup service accounts
- Cross-region snapshot replication for DR
- No credentials stored in code — use AWS IAM roles or `.env`

---

## 👤 Author

**Manicharan Ravi** — IT Specialist & Cloud Engineer  
📧 manicharan.ravi999@gmail.com  
🔗 [linkedin.com/in/manicharan-ravi](https://linkedin.com/in/manicharan-ravi)
