#!/usr/bin/env bash
# =============================================================================
# pre-setup.sh — Terraform S3 Backend Bootstrap
# Creates S3 state buckets (prod + qa) with versioning, encryption, locking,
# and enterprise-grade security controls.
#
# Prerequisites:
#   - AWS CLI configured (aws configure / env vars / IAM role)
#   - .env file present alongside this script (see .env.example)
#
# Usage:
#   ./pre-setup.sh              # creates both prod and qa buckets
#   ./pre-setup.sh prod         # creates only prod bucket
#   ./pre-setup.sh qa           # creates only qa bucket
# =============================================================================
# Handy error handling and strict mode for safer scripting
set -euo pipefail

# ─── Helpers ─────────────────────────────────────────────────────────────────
# interactive logging functions with color output for better UX
log()  { echo -e "\n\033[1;34m ▶   $*\033[0m"; }
ok()   { echo -e "\033[0;32m ✔   $*\033[0m"; }
warn() { echo -e "\033[0;33m ⚠   $*\033[0m"; }
die()  { echo -e "\033[0;31m ✘   $*\033[0m"; exit 1; }

require_cmd() { command -v "$1" &>/dev/null || die "'$1' is required but not installed."; }

# ─── Load .env ────────────────────────────────────────────────────────────────

ENV_FILE="$(dirname "$0")/../../.env"
[[ -f "$ENV_FILE" ]] || die ".env file not found at $ENV_FILE\n"
# shellcheck disable=SC1090
source "$ENV_FILE"

# ─── Config ───────────────────────────────────────────────────────────────────

# Validate required variables were loaded from .env
: "${ENV_TF_STATE_BUCKET:?ENV_TF_STATE_BUCKET is not set in .env}"

REGION="$TF_STATE_REGION"
ENVIRONMENT="${1:-all}"   # prod | qa | all

# ─── Pre-flight ───────────────────────────────────────────────────────────────

require_cmd aws
require_cmd jq

log "Verifying AWS credentials…"
CALLER=$(aws sts get-caller-identity --output json 2>/dev/null) \
  || die "AWS credentials not configured or insufficient permissions."
ok "Account : $(echo "$CALLER" | jq -r '.Account')"
ok "IAM ARN : $(echo "$CALLER" | jq -r '.Arn')"

# ─── Core bucket-creation function ───────────────────────────────────────────

setup_bucket() {
  local BUCKET="$1"
  
  log "Setting up bucket: s3://$BUCKET (region: $REGION)"

  # ── 1. Create bucket ──────────────────────────────────────────────────────
  if aws s3api head-bucket --bucket "$BUCKET" --region "$REGION" 2>/dev/null; then
    warn "Bucket already exists — skipping creation."
  else
    if [[ "$REGION" == "us-east-1" ]]; then
      aws s3api create-bucket \
        --bucket "$BUCKET" \
        --region "$REGION" \
        --output text > /dev/null
    else
      aws s3api create-bucket \
        --bucket "$BUCKET" \
        --region "$REGION" \
        --create-bucket-configuration LocationConstraint="$REGION" \
        --output text > /dev/null
    fi
    ok "Bucket created."
  fi

  # ── 2. Block all public access ────────────────────────────────────────────
  log "Enabling public-access block…"
  aws s3api put-public-access-block \
    --bucket "$BUCKET" \
    --public-access-block-configuration \
      "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" \
    --region "$REGION"
  ok "Public access blocked."

  # ── 3. Versioning ─────────────────────────────────────────────────────────
  log "Enabling versioning…"
  aws s3api put-bucket-versioning \
    --bucket "$BUCKET" \
    --versioning-configuration Status=Enabled \
    --region "$REGION"
  ok "Versioning enabled."

  # ── 4. Server-side encryption (AES-256; swap to aws:kms + CMK if required)
  log "Enabling default encryption (AES-256)…"
  aws s3api put-bucket-encryption \
    --bucket "$BUCKET" \
    --server-side-encryption-configuration '{
      "Rules": [{
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "AES256"
        },
        "BucketKeyEnabled": true
      }]
    }' \
    --region "$REGION"
  ok "Server-side encryption enabled."

  # ── 5. Enforce TLS-only bucket policy ─────────────────────────────────────
  log "Attaching TLS-enforcement bucket policy…"
  aws s3api put-bucket-policy \
    --bucket "$BUCKET" \
    --region "$REGION" \
    --policy "{
      \"Version\": \"2012-10-17\",
      \"Statement\": [
        {
          \"Sid\": \"DenyNonTLS\",
          \"Effect\": \"Deny\",
          \"Principal\": \"*\",
          \"Action\": \"s3:*\",
          \"Resource\": [
            \"arn:aws:s3:::${BUCKET}\",
            \"arn:aws:s3:::${BUCKET}/*\"
          ],
          \"Condition\": {
            \"Bool\": { \"aws:SecureTransport\": \"false\" }
          }
        }
      ]
    }"
  ok "TLS-only policy applied."

  # ── 6. Lifecycle: expire old non-current versions after 90 days ───────────
  log "Adding lifecycle policy (non-current version expiry: 90 days)…"
  aws s3api put-bucket-lifecycle-configuration \
    --bucket "$BUCKET" \
    --region "$REGION" \
    --lifecycle-configuration '{
      "Rules": [{
        "ID": "expire-old-state-versions",
        "Status": "Enabled",
        "Filter": { "Prefix": "" },
        "NoncurrentVersionExpiration": { "NoncurrentDays": 90 },
        "AbortIncompleteMultipartUpload": { "DaysAfterInitiation": 7 }
      }]
    }'
  ok "Lifecycle rule applied."

  # ── 7. Tagging ────────────────────────────────────────────────────────────
  log "Applying tags…"
  aws s3api put-bucket-tagging \
    --bucket "$BUCKET" \
    --region "$REGION" \
    --tagging "{
      \"TagSet\": [
        {\"Key\": \"ManagedBy\",    \"Value\": \"terraform-bootstrap\"},
        {\"Key\": \"Purpose\",      \"Value\": \"terraform-state\"},
        {\"Key\": \"Environment\",  \"Value\": \"qa-prov\"},
        {\"Key\": \"Owner\",        \"Value\": \"platform-team\"}
      ]
    }"
  ok "Tags applied."

  # ── 8. S3-native locking (native lock file — no DynamoDB needed) ──────────
  #  Terraform >= 1.10 supports use_lockfile = true, which stores a .tflock
  #  object in S3 alongside the state file to prevent concurrent applies.
  #  No DynamoDB table or Object Lock is required — S3 versioning is enough.
  ok "S3-native locking (use_lockfile=true) is handled by Terraform — no extra AWS resource needed."

  log "Bucket s3://$BUCKET is ready.\n"
}

# ─── Entrypoint ───────────────────────────────────────────────────────────────

setup_bucket "$ENV_TF_STATE_BUCKET"



log "All done!"
echo ""
echo "  Bucket : s3://$ENV_TF_STATE_BUCKET"

echo ""
echo "  Run 'terraform init -backend-config=backend-prod.conf' to initialise."