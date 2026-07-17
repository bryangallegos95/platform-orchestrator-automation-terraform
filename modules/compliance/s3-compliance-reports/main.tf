# modules/compliance/s3-compliance-reports/main.tf
#
# S3 Bucket — Centralized compliance reports storage.
#
# What this module creates:
#   1. S3 Bucket (private, encrypted, versioned)
#   2. Public Access Block (all 4 flags)
#   3. Ownership Controls (BucketOwnerEnforced)
#   4. Versioning (enabled)
#   5. Server-Side Encryption (SSE-KMS)
#   6. Bucket Policy (HTTPS enforcement + writer/reader access)
#   7. Lifecycle Rules (IA → Glacier → Expire)
#   8. Access Logging (optional)
#
# What this module does NOT create:
#   - KMS keys (discovered by alias — account baseline)
#   - Logging target bucket (must exist)
#   - IAM roles for writers/readers (created by caller)

# ══════════════════════════════════════════════════════════════════════════════
# DATA SOURCES
# ══════════════════════════════════════════════════════════════════════════════

data "aws_caller_identity" "current" {}

data "aws_kms_alias" "s3" {
  count = var.kms_key_arn == "" ? 1 : 0
  name  = var.kms_key_alias
}

# ══════════════════════════════════════════════════════════════════════════════
# ACCOUNT GUARDRAIL
# ══════════════════════════════════════════════════════════════════════════════

resource "terraform_data" "account_guard" {
  lifecycle {
    precondition {
      condition     = data.aws_caller_identity.current.account_id == var.aws_account_id
      error_message = "aws_account_id (${var.aws_account_id}) != active account (${data.aws_caller_identity.current.account_id})."
    }
  }
}

# ══════════════════════════════════════════════════════════════════════════════
# S3 BUCKET
# ══════════════════════════════════════════════════════════════════════════════

resource "aws_s3_bucket" "this" {
  bucket        = local.bucket_name
  force_destroy = false

  tags = merge(local.tags, { Name = local.bucket_name })

  depends_on = [terraform_data.account_guard]
}

# ══════════════════════════════════════════════════════════════════════════════
# BLOCK PUBLIC ACCESS
# ══════════════════════════════════════════════════════════════════════════════

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ══════════════════════════════════════════════════════════════════════════════
# OWNERSHIP CONTROLS (Disable ACLs)
# ══════════════════════════════════════════════════════════════════════════════

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }

  depends_on = [aws_s3_bucket_public_access_block.this]
}

# ══════════════════════════════════════════════════════════════════════════════
# VERSIONING
# ══════════════════════════════════════════════════════════════════════════════

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

# ══════════════════════════════════════════════════════════════════════════════
# SERVER-SIDE ENCRYPTION (SSE-KMS)
# ══════════════════════════════════════════════════════════════════════════════

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = local.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

# ══════════════════════════════════════════════════════════════════════════════
# LIFECYCLE RULES — IA → Glacier → Expire
# ══════════════════════════════════════════════════════════════════════════════

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "compliance-report-lifecycle"
    status = "Enabled"

    filter {}

    transition {
      days          = var.report_retention_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.archive_retention_days
      storage_class = "GLACIER"
    }

    expiration {
      days = var.expiration_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# ══════════════════════════════════════════════════════════════════════════════
# BUCKET POLICY — HTTPS enforcement + writer/reader access
# ══════════════════════════════════════════════════════════════════════════════

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      # Deny non-HTTPS
      [{
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.this.arn,
          "${aws_s3_bucket.this.arn}/*"
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      }],
      # Writer access (Prowler runners, CI/CD pipelines)
      length(var.writer_role_arns) > 0 ? [{
        Sid       = "AllowWriteFromRunners"
        Effect    = "Allow"
        Principal = { AWS = var.writer_role_arns }
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.this.arn,
          "${aws_s3_bucket.this.arn}/*"
        ]
      }] : [],
      # Reader access (CloudOps, auditors)
      length(var.reader_role_arns) > 0 ? [{
        Sid       = "AllowReadFromAuditors"
        Effect    = "Allow"
        Principal = { AWS = var.reader_role_arns }
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.this.arn,
          "${aws_s3_bucket.this.arn}/*"
        ]
      }] : []
    )
  })

  depends_on = [aws_s3_bucket_public_access_block.this]
}

# ══════════════════════════════════════════════════════════════════════════════
# ACCESS LOGGING (optional)
# ══════════════════════════════════════════════════════════════════════════════

resource "aws_s3_bucket_logging" "this" {
  count = var.logging_bucket_name != "" ? 1 : 0

  bucket = aws_s3_bucket.this.id

  target_bucket = var.logging_bucket_name
  target_prefix = local.logging_prefix
}
