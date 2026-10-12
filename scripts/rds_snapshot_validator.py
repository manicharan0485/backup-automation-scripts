#!/usr/bin/env python3
"""
RDS Snapshot Integrity Validator
---------------------------------
Validates RDS snapshot status, size, and age.
Sends CloudWatch metric and triggers alert if snapshot is missing,
too old, or suspiciously small.

Usage:
    python rds_snapshot_validator.py --region eu-central-1 --db-identifier prod-db

Author: Manicharan Ravi
"""

import boto3
import argparse
import logging
import sys
from datetime import datetime, timezone, timedelta

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)
logger = logging.getLogger(__name__)

# Configuration
MAX_SNAPSHOT_AGE_HOURS = 25       # Alert if latest snapshot older than this
MIN_SNAPSHOT_SIZE_GB   = 1        # Alert if snapshot size below this (sanity check)
CLOUDWATCH_NAMESPACE   = "BackupMonitoring"


def get_latest_snapshot(rds_client, db_identifier):
    """Return the most recent automated or manual snapshot for a DB instance."""
    response = rds_client.describe_db_snapshots(
        DBInstanceIdentifier=db_identifier,
        SnapshotType="automated"
    )
    snapshots = response.get("DBSnapshots", [])

    # Also check manual snapshots
    manual = rds_client.describe_db_snapshots(
        DBInstanceIdentifier=db_identifier,
        SnapshotType="manual"
    ).get("DBSnapshots", [])

    all_snapshots = snapshots + manual
    completed = [s for s in all_snapshots if s["Status"] == "available"]

    if not completed:
        return None

    latest = max(completed, key=lambda x: x["SnapshotCreateTime"])
    return latest


def validate_snapshot(snapshot, db_identifier):
    """Validate snapshot age and size. Returns (is_valid, issues)."""
    issues = []
    now = datetime.now(timezone.utc)

    snapshot_time = snapshot["SnapshotCreateTime"]
    age_hours = (now - snapshot_time).total_seconds() / 3600

    if age_hours > MAX_SNAPSHOT_AGE_HOURS:
        issues.append(
            f"Snapshot is {age_hours:.1f} hours old (threshold: {MAX_SNAPSHOT_AGE_HOURS}h)"
        )

    size_gb = snapshot.get("AllocatedStorage", 0)
    if size_gb < MIN_SNAPSHOT_SIZE_GB:
        issues.append(
            f"Snapshot size {size_gb}GB is suspiciously small (threshold: {MIN_SNAPSHOT_SIZE_GB}GB)"
        )

    status = snapshot["Status"]
    if status != "available":
        issues.append(f"Snapshot status is '{status}' (expected: available)")

    return len(issues) == 0, issues


def put_cloudwatch_metric(cw_client, db_identifier, is_valid):
    """Publish backup health metric to CloudWatch (1=healthy, 0=unhealthy)."""
    cw_client.put_metric_data(
        Namespace=CLOUDWATCH_NAMESPACE,
        MetricData=[
            {
                "MetricName": "SnapshotValid",
                "Dimensions": [
                    {"Name": "DBIdentifier", "Value": db_identifier}
                ],
                "Value": 1 if is_valid else 0,
                "Unit": "Count"
            }
        ]
    )
    logger.info(f"CloudWatch metric published: SnapshotValid={1 if is_valid else 0}")


def main():
    parser = argparse.ArgumentParser(description="Validate RDS snapshot integrity")
    parser.add_argument("--region",        required=True, help="AWS region")
    parser.add_argument("--db-identifier", required=True, help="RDS DB instance identifier")
    args = parser.parse_args()

    rds_client = boto3.client("rds",         region_name=args.region)
    cw_client  = boto3.client("cloudwatch",  region_name=args.region)

    logger.info(f"Checking snapshots for: {args.db_identifier} in {args.region}")

    snapshot = get_latest_snapshot(rds_client, args.db_identifier)

    if not snapshot:
        logger.error("❌ No snapshots found!")
        put_cloudwatch_metric(cw_client, args.db_identifier, is_valid=False)
        sys.exit(1)

    snapshot_id   = snapshot["DBSnapshotIdentifier"]
    snapshot_time = snapshot["SnapshotCreateTime"]
    size_gb       = snapshot.get("AllocatedStorage", "N/A")

    logger.info(f"Latest snapshot : {snapshot_id}")
    logger.info(f"Created at      : {snapshot_time}")
    logger.info(f"Size            : {size_gb} GB")
    logger.info(f"Status          : {snapshot['Status']}")

    is_valid, issues = validate_snapshot(snapshot, args.db_identifier)

    if is_valid:
        logger.info("✅ Snapshot validation PASSED")
    else:
        logger.error("❌ Snapshot validation FAILED:")
        for issue in issues:
            logger.error(f"   - {issue}")

    put_cloudwatch_metric(cw_client, args.db_identifier, is_valid)
    sys.exit(0 if is_valid else 1)


if __name__ == "__main__":
    main()
