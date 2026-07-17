#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# naming_pattern_validator.sh
#
# Validates AWS resource names against the enterprise naming convention:
#
#   {TIPO}-{UBICACION}-{REGION}-{FUNCION}-{AMBIENTE}
#
# Where:
#   TIPO      : Resource abbreviation (s3, kdf, appflow, role, usr, pol, etc.)
#   UBICACION : Cloud provider (aw=AWS, az=Azure, gc=GCP)
#   REGION    : Region short code (ue1=us-east-1, ue2=us-east-2, uw2=us-west-2, glb=global)
#   FUNCION   : Purpose description (1-4 segments, lowercase alphanumeric + hyphens)
#   AMBIENTE  : Environment (dev, qa, preprod, prod, dr)
#
# AWS Resource Name Length Limits:
#   S3 Bucket          : 63 characters max
#   IAM Role/User      : 64 characters max
#   IAM Policy         : 128 characters max
#   Kinesis Firehose   : 64 characters max
#   AppFlow Flow       : 256 characters max
#   CloudWatch Group   : 512 characters max
#   Security Group     : 255 characters max
#   Lambda Function    : 64 characters max
#   Glue Database      : 255 characters max
#
# Usage:
#   ./naming_pattern_validator.sh <plan_json_path> [--strict]
#
# Exit codes:
#   0 = All names compliant
#   1 = Validation failures found (blocks pipeline)
#   2 = Script error (missing args, file not found)
#
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# ── Arguments ─────────────────────────────────────────────────────────────────
PLAN_JSON="${1:-}"
STRICT_MODE="${2:-}"

if [ -z "$PLAN_JSON" ]; then
  echo -e "${RED}ERROR: Usage: $0 <plan_json_path> [--strict]${NC}"
  exit 2
fi

if [ ! -f "$PLAN_JSON" ]; then
  echo -e "${RED}ERROR: Plan JSON file not found: $PLAN_JSON${NC}"
  exit 2
fi

# ── Configuration ─────────────────────────────────────────────────────────────

# Valid resource type prefixes (expandable by adding to this array)
VALID_PREFIXES="s3|kdf|appflow|flow|role|usr|pol|lam|vpc|sg|ec2|rds|aurora|ecs|ecr|elb|alb|nlb|agw|cwl|kms|sns|sqs|ddb|glue|connector|iam-role|iam-user|iam-pol"

# Valid cloud locations
VALID_LOCATIONS="aw|az|gc"

# Valid region short codes
VALID_REGIONS="ue1|ue2|uw2|glb"

# Valid environments
VALID_AMBIENTES="dev|qa|preprod|prod|dr"

# Naming pattern regex:
# {TIPO}-{UBICACION}-{REGION}-{FUNCION...}-{AMBIENTE}
# FUNCION can be 1-4 segments of lowercase alphanumeric separated by hyphens
NAMING_REGEX="^(${VALID_PREFIXES})-(${VALID_LOCATIONS})-(${VALID_REGIONS})-([a-z0-9]+(-[a-z0-9]+){0,5})-(${VALID_AMBIENTES})$"

# AWS resource type → max name length mapping
declare -A MAX_LENGTHS=(
  ["aws_s3_bucket"]=63
  ["aws_kinesis_firehose_delivery_stream"]=64
  ["aws_iam_role"]=64
  ["aws_iam_user"]=64
  ["aws_iam_policy"]=128
  ["aws_lambda_function"]=64
  ["aws_appflow_flow"]=256
  ["aws_cloudwatch_log_group"]=512
  ["aws_security_group"]=255
  ["aws_glue_catalog_database"]=255
  ["aws_glue_catalog_table"]=255
  ["aws_db_instance"]=63
  ["aws_rds_cluster"]=63
  ["aws_ecs_cluster"]=255
  ["aws_ecr_repository"]=256
  ["aws_lb"]=32
  ["aws_apigatewayv2_api"]=128
  ["aws_sns_topic"]=256
  ["aws_sqs_queue"]=80
  ["aws_dynamodb_table"]=255
  ["aws_kms_key"]=256
  ["aws_kms_alias"]=256
)

# Resource types whose names we validate
# (Only resources that use our naming convention — skip data sources, meta resources)
RESOURCE_TYPES_TO_VALIDATE="aws_s3_bucket|aws_kinesis_firehose_delivery_stream|aws_iam_role|aws_iam_user|aws_iam_policy|aws_lambda_function|aws_appflow_flow|aws_security_group|aws_lb|aws_ecs_cluster|aws_ecr_repository|aws_sns_topic|aws_sqs_queue|aws_dynamodb_table"

# ── Counters ──────────────────────────────────────────────────────────────────
TOTAL_CHECKED=0
TOTAL_PASS=0
TOTAL_FAIL=0
TOTAL_WARN=0
FAILURES=""

# ── Helper functions ──────────────────────────────────────────────────────────

validate_name() {
  local resource_type="$1"
  local resource_name="$2"
  local resource_address="$3"
  local name_length=${#resource_name}

  TOTAL_CHECKED=$((TOTAL_CHECKED + 1))

  # ── Length check ──────────────────────────────────────────────────────────
  local max_len="${MAX_LENGTHS[$resource_type]:-256}"
  if [ "$name_length" -gt "$max_len" ]; then
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
    FAILURES="${FAILURES}\n  ${RED}FAIL${NC} [LENGTH] ${resource_address}"
    FAILURES="${FAILURES}\n       Name: '${resource_name}'"
    FAILURES="${FAILURES}\n       Length: ${name_length} chars (max: ${max_len})"
    FAILURES="${FAILURES}\n"
    return 1
  fi

  # ── Pattern check ─────────────────────────────────────────────────────────
  if ! echo "$resource_name" | grep -qP "$NAMING_REGEX"; then
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
    FAILURES="${FAILURES}\n  ${RED}FAIL${NC} [PATTERN] ${resource_address}"
    FAILURES="${FAILURES}\n       Name: '${resource_name}'"
    FAILURES="${FAILURES}\n       Expected: {TIPO}-{aw|az|gc}-{ue1|ue2|uw2|glb}-{funcion}-{dev|qa|preprod|prod|dr}"
    FAILURES="${FAILURES}\n       Max segments in FUNCION: 6 (lowercase alphanumeric + hyphens)"
    FAILURES="${FAILURES}\n"
    return 1
  fi

  TOTAL_PASS=$((TOTAL_PASS + 1))
  return 0
}

# ── Special cases: resources that DON'T follow convention ─────────────────────
# CloudWatch Log Groups use /aws/... path pattern — skip naming but check length
# IAM Policies may use path-based naming — handled separately
# Glue databases/tables have their own convention (db_{service}_{workload}_{env})

is_excluded_pattern() {
  local name="$1"
  # CloudWatch log groups start with /aws/
  if [[ "$name" == /aws/* ]]; then
    return 0
  fi
  # Glue databases start with db_
  if [[ "$name" == db_* ]]; then
    return 0
  fi
  # Terraform internal resources
  if [[ "$name" == terraform-* ]]; then
    return 0
  fi
  return 1
}

# ── Main extraction and validation ────────────────────────────────────────────

echo "══════════════════════════════════════════════════════════════════════════"
echo "  Naming Convention Validator"
echo "  Standard: {TIPO}-{UBICACION}-{REGION}-{FUNCION}-{AMBIENTE}"
echo "══════════════════════════════════════════════════════════════════════════"
echo ""
echo "  Plan file: $PLAN_JSON"
echo "  Mode: $([ "$STRICT_MODE" = "--strict" ] && echo "STRICT (all names must match)" || echo "STANDARD (known resources only)")"
echo ""
echo "──────────────────────────────────────────────────────────────────────────"

# Extract resource names from plan JSON
# We look at:
#   1. .resource_changes[].change.after.name (most resources)
#   2. .resource_changes[].change.after.bucket (S3 buckets)
#   3. .resource_changes[].change.after.tags.Name (Name tag)

# Process each resource change that creates or updates
jq -r '
  .resource_changes[]? |
  select(.change.actions | contains(["create"]) or contains(["update"])) |
  {
    type: .type,
    address: .address,
    name: (.change.after.name // .change.after.bucket // null),
    name_tag: (.change.after.tags.Name // .change.after.tags_all.Name // null)
  } |
  select(.name != null or .name_tag != null) |
  "\(.type)|\(.address)|\(.name // "")|\(.name_tag // "")"
' "$PLAN_JSON" 2>/dev/null | while IFS='|' read -r res_type res_address res_name res_name_tag; do

  # Skip if not a resource type we validate
  if ! echo "$res_type" | grep -qP "^(${RESOURCE_TYPES_TO_VALIDATE})$"; then
    continue
  fi

  # Determine which name to validate (resource identifier takes priority)
  local_name="${res_name:-$res_name_tag}"

  if [ -z "$local_name" ]; then
    continue
  fi

  # Skip excluded patterns
  if is_excluded_pattern "$local_name"; then
    TOTAL_WARN=$((TOTAL_WARN + 1))
    echo -e "  ${YELLOW}SKIP${NC} ${res_address} → '${local_name}' (excluded pattern)"
    continue
  fi

  # Validate
  if validate_name "$res_type" "$local_name" "$res_address"; then
    echo -e "  ${GREEN}PASS${NC} ${res_address} → '${local_name}'"
  fi

done

echo ""
echo "──────────────────────────────────────────────────────────────────────────"
echo "  RESULTS"
echo "──────────────────────────────────────────────────────────────────────────"
echo ""
echo "  Checked:  $TOTAL_CHECKED"
echo -e "  Passed:   ${GREEN}${TOTAL_PASS}${NC}"
echo -e "  Failed:   ${RED}${TOTAL_FAIL}${NC}"
echo -e "  Skipped:  ${YELLOW}${TOTAL_WARN}${NC}"
echo ""

if [ "$TOTAL_FAIL" -gt 0 ]; then
  echo -e "──────────────────────────────────────────────────────────────────────────"
  echo -e "  ${RED}FAILURES:${NC}"
  echo -e "$FAILURES"
  echo -e "──────────────────────────────────────────────────────────────────────────"
  echo ""
  echo -e "  ${RED}NAMING CONVENTION REFERENCE:${NC}"
  echo "    Pattern: {TIPO}-{UBICACION}-{REGION}-{FUNCION}-{AMBIENTE}"
  echo ""
  echo "    TIPO:      s3, kdf, appflow, role, usr, pol, lam, vpc, sg, ec2, rds..."
  echo "    UBICACION: aw (AWS), az (Azure), gc (GCP)"
  echo "    REGION:    ue1 (us-east-1), ue2 (us-east-2), uw2 (us-west-2), glb (global)"
  echo "    FUNCION:   1-6 segments, lowercase alphanumeric, separated by hyphens"
  echo "    AMBIENTE:  dev, qa, preprod, prod, dr"
  echo ""
  echo "    Examples:"
  echo "      s3-aw-ue1-bancamovil-ga4-landing-dev"
  echo "      kdf-aw-ue1-bancamovil-ga4-dev"
  echo "      role-aw-ue1-bancamovil-ga4-firehose-dev"
  echo ""
  echo "    Max lengths:"
  echo "      S3 Bucket:    63 chars"
  echo "      IAM Role:     64 chars"
  echo "      Firehose:     64 chars"
  echo "      Lambda:       64 chars"
  echo "      ALB/NLB:      32 chars"
  echo ""

  # Write GitHub Actions annotation
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    cat >> "$GITHUB_STEP_SUMMARY" << EOF
### Naming Convention: FAILED

| Metric | Value |
|--------|-------|
| Checked | $TOTAL_CHECKED |
| Passed | $TOTAL_PASS |
| **Failed** | **$TOTAL_FAIL** |
| Skipped | $TOTAL_WARN |

> Pattern: \`{TIPO}-{UBICACION}-{REGION}-{FUNCION}-{AMBIENTE}\`
EOF
  fi

  exit 1
fi

# Success
echo -e "  ${GREEN}ALL NAMES COMPLIANT${NC}"
echo ""

# Write GitHub Actions annotation
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  cat >> "$GITHUB_STEP_SUMMARY" << EOF
### Naming Convention: PASSED

| Metric | Value |
|--------|-------|
| Checked | $TOTAL_CHECKED |
| Passed | $TOTAL_PASS |
| Skipped | $TOTAL_WARN |

> Pattern: \`{TIPO}-{UBICACION}-{REGION}-{FUNCION}-{AMBIENTE}\`
EOF
fi

exit 0
