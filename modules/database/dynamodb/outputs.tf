# modules/database/dynamodb/outputs.tf
#
# Outputs for downstream consumers (IRSA module, wait-processor Lambda,
# son-repo references, compositor).

output "table_names" {
  description = "Map de clave lógica de tabla (applications, services, logs, log-payloads, wait-logs, wait-payloads) → nombre real en AWS."
  value       = { for key, t in aws_dynamodb_table.this : key => t.name }
}

output "table_arns" {
  description = "Map de clave lógica de tabla → ARN. Consumido por modules/identity/irsa-role para generar las policies de acceso (paso siguiente, no en esta pasada)."
  value       = { for key, t in aws_dynamodb_table.this : key => t.arn }
}

output "table_ids" {
  description = "Map de clave lógica de tabla → table ID."
  value       = { for key, t in aws_dynamodb_table.this : key => t.id }
}

output "index_arns" {
  description = "ARNs de los GSIs (`{table_arn}/index/*`). Necesarios en las policies IAM: un permiso sobre la tabla base NO cubre sus índices."
  value       = { for key, t in aws_dynamodb_table.this : key => "${t.arn}/index/*" if length(try(local.gsis[key], {})) > 0 }
}

output "gsi_names" {
  description = "Map de clave lógica de tabla → lista de nombres de GSI declarados."
  value       = { for key, idx in local.gsis : key => keys(idx) }
}

output "stream_arns" {
  description = "Map de clave lógica de tabla → Stream ARN, solo para las tablas con Streams habilitado (hoy: wait-logs). Consumido por el event source mapping del Lambda `wait-processor`."
  value       = { for key, t in aws_dynamodb_table.this : key => t.stream_arn if t.stream_enabled }
}

output "ttl_attribute_name" {
  description = "Nombre del atributo TTL que la aplicación debe escribir (epoch en segundos) en las tablas con TTL habilitado."
  value       = var.ttl_attribute_name
}

output "ttl_enabled_tables" {
  description = "Claves lógicas de las tablas con TTL habilitado (hoy: logs, wait-logs y sus tablas de payloads por TTL espejo)."
  value       = sort([for key, cfg in local.tables : key if cfg.ttl_enabled])
}

output "ttl_retention_days" {
  description = "Días de retención efectivos (piso por ambiente aplicado). DynamoDB NO usa este valor: se expone para que el productor calcule `now + N días` al escribir el atributo TTL."
  value       = local.ttl_retention_days
}

output "kms_key_arn" {
  description = "ARN de la CMK usada para el cifrado en reposo de todas las tablas."
  value       = local.kms_key_arn
}

output "billing_mode" {
  description = "Modo de capacidad efectivo aplicado a las tablas."
  value       = var.billing_mode
}
