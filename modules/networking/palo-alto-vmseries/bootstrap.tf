# modules/networking/palo-alto-vmseries/bootstrap.tf
#
# S3 bucket for PA VM-Series bootstrap files.
# Contains: init-cfg.txt, authcodes, software/, content/, license/
#
# For DR: Use S3 Cross-Region Replication (CRR) from the prod bucket.
# The DR layer should set create_bootstrap_bucket = false and provide
# the replicated bucket name via bootstrap_bucket_name.

resource "aws_s3_bucket" "bootstrap" {
  count = var.create_bootstrap_bucket ? 1 : 0

  bucket_prefix = "${var.name_prefix}-bootstrap-"
  force_destroy = false

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-bootstrap"
  })
}

resource "aws_s3_bucket_versioning" "bootstrap" {
  count = var.create_bootstrap_bucket ? 1 : 0

  bucket = aws_s3_bucket.bootstrap[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "bootstrap" {
  count = var.create_bootstrap_bucket ? 1 : 0

  bucket = aws_s3_bucket.bootstrap[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "bootstrap" {
  count = var.create_bootstrap_bucket ? 1 : 0

  bucket = aws_s3_bucket.bootstrap[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── Bootstrap directory structure (empty objects as placeholders) ──────────────
# The actual content (init-cfg.txt, authcodes, etc.) is uploaded manually or
# via a separate CI step. These objects create the expected directory structure.

resource "aws_s3_object" "config_dir" {
  count = var.create_bootstrap_bucket ? 1 : 0

  bucket  = aws_s3_bucket.bootstrap[0].id
  key     = "config/"
  content = ""
}

resource "aws_s3_object" "content_dir" {
  count = var.create_bootstrap_bucket ? 1 : 0

  bucket  = aws_s3_bucket.bootstrap[0].id
  key     = "content/"
  content = ""
}

resource "aws_s3_object" "software_dir" {
  count = var.create_bootstrap_bucket ? 1 : 0

  bucket  = aws_s3_bucket.bootstrap[0].id
  key     = "software/"
  content = ""
}

resource "aws_s3_object" "license_dir" {
  count = var.create_bootstrap_bucket ? 1 : 0

  bucket  = aws_s3_bucket.bootstrap[0].id
  key     = "license/"
  content = ""
}
