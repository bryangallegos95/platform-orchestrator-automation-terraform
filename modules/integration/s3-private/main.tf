# modules/integration/s3-private/main.tf
#
# Private S3 Bucket — Implements Banco Internacional Security Baseline.
#
# What this module creates:
#   1. S3 Bucket (private, no public access)
#   2. Bucket Public Access Block (all 4 flags)
#   3. Bucket Ownership Controls (BucketOwnerEnforced — disables ACLs)
#   4. Bucket Versioning
#   5. Server-Side Encryption (SSE-KMS with existing CMK)
#   6. Bucket Policy (HTTPS enforcement + consumer access)
#   7. Lifecycle Rules (transition + expiration)
#   8. Access Logging to central bucket
#   9. Optional Object Lock (WORM)
#
# What this module does NOT create:
#   - KMS keys (discovered by alias — account baseline)
#   - Logging target bucket (must exist)
#   - IAM roles/users for consumers (created by caller)
#   - Replication rules (not required per scope)

# ══════════════════════════════════════════════════════════════════════════════
# DATA SOURCES
# ══════════════════════════════════════════════════════════════════════════════

data "aws_caller_identity" "current" {}

# Pre-existing S3 CMK — resolved by alias unless an explicit ARN is supplied.
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
      error_message = "aws_account_id (${var.aws_account_id}) != active account (${data.aws_caller_identity.current.account_id}). Bucket must be created in the correct account."
    }
  }
}

# ══════════════════════════════════════════════════════════════════════════════
# S3 BUCKET
# ══════════════════════════════════════════════════════════════════════════════

resource "aws_s3_bucket" "this" {
  bucket              = local.bucket_name
  object_lock_enabled = var.object_lock_enabled
  force_destroy       = !local.is_prod_like

  tags = merge(local.tags, { Name = local.bucket_name })

  depends_on = [terraform_data.account_guard]
}

# ══════════════════════════════════════════════════════════════════════════════
# BLOCK PUBLIC ACCESS (Control 2.3)
# All four flags enabled — no public access under any circumstance.
# ══════════════════════════════════════════════════════════════════════════════

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ══════════════════════════════════════════════════════════════════════════════
# OWNERSHIP CONTROLS (Control 2.1 — Disable ACLs)
# BucketOwnerEnforced: all objects owned by bucket owner, ACLs disabled.
# ══════════════════════════════════════════════════════════════════════════════

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }

  depends_on = [aws_s3_bucket_public_access_block.this]
}

# ══════════════════════════════════════════════════════════════════════════════
# VERSIONING (Control 3.1)
# ══════════════════════════════════════════════════════════════════════════════

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = var.versioning_enabled ? "Enabled" : "Suspended"
  }
}

# ══════════════════════════════════════════════════════════════════════════════
# SERVER-SIDE ENCRYPTION (Control 4.1 / 4.2 — SSE-KMS)
# Uses the account's pre-existing S3 CMK (alias/S3).
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
# BUCKET POLICY (Controls 2.2 + 4.4)
# - Enforce HTTPS (deny HTTP)
# - Allow specific principals read/write access
# - Deny all public access patterns
# ══════════════════════════════════════════════════════════════════════════════

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      # ── Statement 1: Enforce HTTPS (Control 4.4) ────────────────────────────
      [{
        Sid       = "EnforceHTTPS"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.this.arn,
          "${aws_s3_bucket.this.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }],

      # ── Statement 2: Deny non-specific principals (Control 2.2) ─────────────
      [{
        Sid       = "DenyUnauthorizedAccess"
        Effect    = "Deny"
        Principal = "*"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.this.arn,
          "${aws_s3_bucket.this.arn}/*"
        ]
        Condition = {
          StringNotLike = {
            "aws:PrincipalArn" = concat(
              var.writer_principal_arns,
              var.reader_principal_arns,
              # Always allow the account root (for emergency access)
              ["arn:aws:iam::${var.aws_account_id}:root"]
            )
          }
        }
      }],

      # ── Statement 3: Allow writers (Kinesis Firehose) ───────────────────────
      length(var.writer_principal_arns) > 0 ? [{
        Sid       = "AllowWriters"
        Effect    = "Allow"
        Principal = { AWS = var.writer_principal_arns }
        Action = [
          "s3:PutObject",
          "s3:AbortMultipartUpload",
          "s3:GetBucketLocation",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:GetObject"
        ]
        Resource = [
          aws_s3_bucket.this.arn,
          "${aws_s3_bucket.this.arn}/*"
        ]
      }] : [],

      # ── Statement 4: Allow readers (Stratio) ────────────────────────────────
      length(var.reader_principal_arns) > 0 ? [{
        Sid       = "AllowReaders"
        Effect    = "Allow"
        Principal = { AWS = var.reader_principal_arns }
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.this.arn,
          "${aws_s3_bucket.this.arn}/*"
        ]
      }] : []
    )
  })

  depends_on = [
    aws_s3_bucket_public_access_block.this,
    aws_s3_bucket_ownership_controls.this
  ]
}

# ══════════════════════════════════════════════════════════════════════════════
# LIFECYCLE RULES (Control 3.3)
# ══════════════════════════════════════════════════════════════════════════════

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  count  = var.lifecycle_enabled ? 1 : 0
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "transition-and-expiration"
    status = "Enabled"

    filter {
      prefix = ""
    }

    # Transition to Infrequent Access
    transition {
      days          = var.lifecycle_transition_ia_days
      storage_class = "STANDARD_IA"
    }

    # Transition to Glacier (if configured)
    dynamic "transition" {
      for_each = var.lifecycle_transition_glacier_days > 0 ? [1] : []
      content {
        days          = var.lifecycle_transition_glacier_days
        storage_class = "GLACIER"
      }
    }

    # Expiration (if configured)
    dynamic "expiration" {
      for_each = var.lifecycle_expiration_days > 0 ? [1] : []
      content {
        days = var.lifecycle_expiration_days
      }
    }

    # Non-current version expiration
    noncurrent_version_expiration {
      noncurrent_days = var.lifecycle_noncurrent_expiration_days
    }
  }

  # Abort incomplete multipart uploads
  rule {
    id     = "abort-incomplete-multipart"
    status = "Enabled"

    filter {
      prefix = ""
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}

# ══════════════════════════════════════════════════════════════════════════════
# ACCESS LOGGING (Control 5.1)
# ══════════════════════════════════════════════════════════════════════════════

resource "aws_s3_bucket_logging" "this" {
  bucket = aws_s3_bucket.this.id

  target_bucket = var.logging_bucket_name
  target_prefix = local.logging_prefix
}

# ══════════════════════════════════════════════════════════════════════════════
# OBJECT LOCK (Control 3.4 — Optional)
# Only created when object_lock_enabled = true.
# ══════════════════════════════════════════════════════════════════════════════

resource "aws_s3_bucket_object_lock_configuration" "this" {
  count  = var.object_lock_enabled ? 1 : 0
  bucket = aws_s3_bucket.this.id

  rule {
    default_retention {
      mode = var.object_lock_mode
      days = var.object_lock_retention_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}
