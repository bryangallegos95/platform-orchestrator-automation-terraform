# modules/database/elasticache-serverless/outputs.tf
#
# Outputs for downstream consumers (IRSA module, son-repo references).

output "cache_name" {
  description = "Name of the ElastiCache Serverless cache."
  value       = aws_elasticache_serverless_cache.this.name
}

output "cache_arn" {
  description = "ARN of the ElastiCache Serverless cache."
  value       = aws_elasticache_serverless_cache.this.arn
}

output "endpoint" {
  description = "Primary endpoint (address + port) for read/write operations."
  value = {
    address = aws_elasticache_serverless_cache.this.endpoint[0].address
    port    = aws_elasticache_serverless_cache.this.endpoint[0].port
  }
}

output "reader_endpoint" {
  description = "Reader endpoint (address + port) for read-optimized operations."
  value = {
    address = aws_elasticache_serverless_cache.this.reader_endpoint[0].address
    port    = aws_elasticache_serverless_cache.this.reader_endpoint[0].port
  }
}

output "security_group_id" {
  description = "ID of the module-managed Security Group."
  value       = aws_security_group.this.id
}

output "kms_key_arn" {
  description = "ARN of the KMS CMK used for at-rest encryption."
  value       = local.kms_key_arn
}

output "subnet_ids" {
  description = "Subnet IDs where VPC endpoints were created."
  value       = [data.aws_subnet.cache_a.id, data.aws_subnet.cache_b.id]
}

output "vpc_id" {
  description = "VPC ID where the cache is deployed."
  value       = data.aws_vpc.spoke.id
}

output "log_group_names" {
  description = "CloudWatch Log Group names for ElastiCache log delivery (slow-log + engine-log)."
  value = {
    slow_log   = aws_cloudwatch_log_group.slow_log.name
    engine_log = aws_cloudwatch_log_group.engine_log.name
  }
}

output "log_group_arns" {
  description = "CloudWatch Log Group ARNs for ElastiCache log delivery."
  value = {
    slow_log   = aws_cloudwatch_log_group.slow_log.arn
    engine_log = aws_cloudwatch_log_group.engine_log.arn
  }
}
