#!/usr/bin/env python3
"""
Backup Status Report
----------------------
Generates a daily HTML backup status report for all RDS instances
and sends it via AWS SES.

Usage:
    python backup_status_report.py --region eu-central-1 --email ops@company.com

Author: Manicharan Ravi
"""

import boto3
import argparse
import logging
from datetime import datetime, timezone, timedelta

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger(__name__)


def get_all_db_instances(rds_client):
    instances = []
    paginator = rds_client.get_paginator("describe_db_instances")
    for page in paginator.paginate():
        instances.extend(page["DBInstances"])
    return instances


def get_latest_snapshot(rds_client, db_id):
    try:
        resp = rds_client.describe_db_snapshots(
            DBInstanceIdentifier=db_id,
            SnapshotType="automated"
        )
        snapshots = [s for s in resp["DBSnapshots"] if s["Status"] == "available"]
        if not snapshots:
            return None
        return max(snapshots, key=lambda x: x["SnapshotCreateTime"])
    except Exception as e:
        logger.warning(f"Could not fetch snapshots for {db_id}: {e}")
        return None


def build_html_report(instance_data, report_date):
    rows = ""
    for item in instance_data:
        status_color = "#2ecc71" if item["status"] == "✅ OK" else "#e74c3c"
        rows += f"""
        <tr>
            <td>{item['db_id']}</td>
            <td>{item['engine']}</td>
            <td>{item['snapshot_id']}</td>
            <td>{item['snapshot_time']}</td>
            <td>{item['age_hours']}</td>
            <td>{item['size_gb']} GB</td>
            <td style="color:{status_color}; font-weight:bold;">{item['status']}</td>
        </tr>"""

    return f"""
    <html><body style="font-family:Arial,sans-serif;padding:20px;">
    <h2>🗄️ Daily Backup Status Report — {report_date}</h2>
    <table border="1" cellpadding="8" cellspacing="0" style="border-collapse:collapse;width:100%;">
        <thead style="background:#2c3e50;color:white;">
            <tr>
                <th>DB Instance</th><th>Engine</th><th>Latest Snapshot</th>
                <th>Created At</th><th>Age (hours)</th><th>Size</th><th>Status</th>
            </tr>
        </thead>
        <tbody>{rows}</tbody>
    </table>
    <p style="color:#7f8c8d;font-size:12px;">
        Generated: {report_date} UTC | Backup Monitoring System
    </p>
    </body></html>"""


def send_email(ses_client, recipient, subject, html_body, sender="backup-monitor@company.com"):
    ses_client.send_email(
        Source=sender,
        Destination={"ToAddresses": [recipient]},
        Message={
            "Subject": {"Data": subject},
            "Body": {"Html": {"Data": html_body}}
        }
    )
    logger.info(f"Report sent to {recipient}")


def main():
    parser = argparse.ArgumentParser(description="Daily backup status report")
    parser.add_argument("--region", required=True)
    parser.add_argument("--email",  required=True)
    args = parser.parse_args()

    rds_client = boto3.client("rds",  region_name=args.region)
    ses_client = boto3.client("ses",  region_name=args.region)

    now = datetime.now(timezone.utc)
    report_date = now.strftime("%Y-%m-%d %H:%M UTC")

    instances = get_all_db_instances(rds_client)
    instance_data = []

    for inst in instances:
        db_id  = inst["DBInstanceIdentifier"]
        engine = f"{inst['Engine']} {inst['EngineVersion']}"
        snap   = get_latest_snapshot(rds_client, db_id)

        if snap:
            snap_time  = snap["SnapshotCreateTime"]
            age_hours  = round((now - snap_time).total_seconds() / 3600, 1)
            size_gb    = snap.get("AllocatedStorage", "N/A")
            snap_id    = snap["DBSnapshotIdentifier"]
            status     = "✅ OK" if age_hours <= 25 else "❌ STALE"
        else:
            snap_time = age_hours = size_gb = "N/A"
            snap_id   = "No snapshot found"
            status    = "❌ MISSING"

        instance_data.append({
            "db_id":         db_id,
            "engine":        engine,
            "snapshot_id":   snap_id,
            "snapshot_time": str(snap_time)[:19] if snap_time != "N/A" else "N/A",
            "age_hours":     age_hours,
            "size_gb":       size_gb,
            "status":        status
        })

    html = build_html_report(instance_data, report_date)
    subject = f"[Backup Report] {report_date} — {len(instances)} DB(s) checked"
    send_email(ses_client, args.email, subject, html)
    logger.info("Done.")


if __name__ == "__main__":
    main()
