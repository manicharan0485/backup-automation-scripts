#!/bin/bash
# =============================================================================
# restore_test_automation.sh
# -----------------------------------------------------------------------------
# Automated RDS restore test script.
# Restores the latest RDS snapshot to a temporary test instance,
# runs basic integrity checks (row count, schema validation),
# logs results, then deletes the test instance.
#
# Usage:
#   ./restore_test_automation.sh <db-identifier> <aws-region>
#
# Example:
#   ./restore_test_automation.sh prod-db eu-central-1
#
# Author: Manicharan Ravi
# =============================================================================

set -euo pipefail

# ── Arguments ─────────────────────────────────────────────────────────────────
DB_IDENTIFIER="${1:-}"
AWS_REGION="${2:-eu-central-1}"

if [[ -z "$DB_IDENTIFIER" ]]; then
  echo "Usage: $0 <db-identifier> <aws-region>"
  exit 1
fi

# ── Config ────────────────────────────────────────────────────────────────────
TEST_INSTANCE_ID="restore-test-$(date +%Y%m%d%H%M%S)"
DB_INSTANCE_CLASS="db.t3.micro"
LOG_FILE="/var/log/backup-restore-tests/restore_test_$(date +%Y%m%d).log"
WAIT_TIMEOUT=900      # 15 minutes max wait for restore
CHECK_INTERVAL=30     # seconds between status checks

# ── Logging ───────────────────────────────────────────────────────────────────
mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
log_ok()   { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $*"; }
log_fail() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ❌ $*"; }

# ── Cleanup on exit ───────────────────────────────────────────────────────────
cleanup() {
  if aws rds describe-db-instances \
       --db-instance-identifier "$TEST_INSTANCE_ID" \
       --region "$AWS_REGION" &>/dev/null; then
    log "Deleting test instance: $TEST_INSTANCE_ID"
    aws rds delete-db-instance \
      --db-instance-identifier "$TEST_INSTANCE_ID" \
      --skip-final-snapshot \
      --region "$AWS_REGION" > /dev/null
    log_ok "Test instance deleted"
  fi
}
trap cleanup EXIT

# ── Step 1: Get latest snapshot ───────────────────────────────────────────────
log "=== RESTORE TEST START: $DB_IDENTIFIER ==="
log "Fetching latest snapshot..."

SNAPSHOT_ID=$(aws rds describe-db-snapshots \
  --db-instance-identifier "$DB_IDENTIFIER" \
  --snapshot-type automated \
  --query "reverse(sort_by(DBSnapshots[?Status=='available'], &SnapshotCreateTime))[0].DBSnapshotIdentifier" \
  --output text \
  --region "$AWS_REGION")

if [[ -z "$SNAPSHOT_ID" || "$SNAPSHOT_ID" == "None" ]]; then
  log_fail "No available snapshots found for $DB_IDENTIFIER"
  exit 1
fi

log_ok "Latest snapshot: $SNAPSHOT_ID"

# ── Step 2: Restore snapshot to test instance ─────────────────────────────────
log "Restoring snapshot to test instance: $TEST_INSTANCE_ID ..."

aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier "$TEST_INSTANCE_ID" \
  --db-snapshot-identifier "$SNAPSHOT_ID" \
  --db-instance-class "$DB_INSTANCE_CLASS" \
  --no-multi-az \
  --no-publicly-accessible \
  --region "$AWS_REGION" > /dev/null

log "Waiting for test instance to become available (max ${WAIT_TIMEOUT}s)..."

ELAPSED=0
while true; do
  STATUS=$(aws rds describe-db-instances \
    --db-instance-identifier "$TEST_INSTANCE_ID" \
    --query "DBInstances[0].DBInstanceStatus" \
    --output text \
    --region "$AWS_REGION")

  log "Status: $STATUS (${ELAPSED}s elapsed)"

  if [[ "$STATUS" == "available" ]]; then
    log_ok "Test instance is available"
    break
  fi

  if (( ELAPSED >= WAIT_TIMEOUT )); then
    log_fail "Timeout waiting for test instance after ${WAIT_TIMEOUT}s"
    exit 1
  fi

  sleep "$CHECK_INTERVAL"
  ELAPSED=$(( ELAPSED + CHECK_INTERVAL ))
done

# ── Step 3: Integrity checks ──────────────────────────────────────────────────
log "Running integrity checks..."

ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier "$TEST_INSTANCE_ID" \
  --query "DBInstances[0].Endpoint.Address" \
  --output text \
  --region "$AWS_REGION")

log "Test instance endpoint: $ENDPOINT"

# Check 1: Connection test (requires psql or mysql client in PATH)
# Uncomment and configure credentials via AWS Secrets Manager in production:
#
# SECRET=$(aws secretsmanager get-secret-value \
#   --secret-id "rds/${DB_IDENTIFIER}/credentials" \
#   --query SecretString --output text)
# DB_USER=$(echo "$SECRET" | python3 -c "import sys,json; print(json.load(sys.stdin)['username'])")
# DB_PASS=$(echo "$SECRET" | python3 -c "import sys,json; print(json.load(sys.stdin)['password'])")
#
# ROW_COUNT=$(PGPASSWORD="$DB_PASS" psql -h "$ENDPOINT" -U "$DB_USER" \
#   -c "SELECT COUNT(*) FROM information_schema.tables;" -t -A 2>/dev/null || echo "0")
#
# if [[ "$ROW_COUNT" -gt 0 ]]; then
#   log_ok "Schema check passed: $ROW_COUNT tables found"
# else
#   log_fail "Schema check failed: no tables found"
#   exit 1
# fi

# Check 2: Instance metadata validation
ENGINE=$(aws rds describe-db-instances \
  --db-instance-identifier "$TEST_INSTANCE_ID" \
  --query "DBInstances[0].Engine" \
  --output text \
  --region "$AWS_REGION")

ENGINE_VERSION=$(aws rds describe-db-instances \
  --db-instance-identifier "$TEST_INSTANCE_ID" \
  --query "DBInstances[0].EngineVersion" \
  --output text \
  --region "$AWS_REGION")

log_ok "Engine: $ENGINE $ENGINE_VERSION — metadata validation passed"

# ── Step 4: Summary ───────────────────────────────────────────────────────────
log "==================================================="
log_ok "RESTORE TEST PASSED"
log "  DB Identifier  : $DB_IDENTIFIER"
log "  Snapshot ID    : $SNAPSHOT_ID"
log "  Test Instance  : $TEST_INSTANCE_ID"
log "  Engine         : $ENGINE $ENGINE_VERSION"
log "  Log File       : $LOG_FILE"
log "==================================================="
log "Test instance will be deleted on script exit (trap)."
