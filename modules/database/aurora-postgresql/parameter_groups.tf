# modules/database/aurora-postgresql/parameter_groups.tf
#
# Cluster + instance parameter groups.
#
# The CIS/security baseline is ALWAYS present (see locals.base_cluster_parameters):
#   rds.force_ssl=1            → TLS-only connections
#   log_connections/disconnections, log_statement=ddl, slow-query logging
#   shared_preload_libraries   → pg_stat_statements + pgaudit
#   pgaudit.log=ddl,role       → DDL/role audit trail in the postgresql log
#
# Son repos EXTEND or OVERRIDE via var.cluster_parameters / var.instance_parameters
# (their entries win on name collision) — e.g. tuning work_mem, max_connections.
#
# Family is derived from the engine major version (aurora-postgresql16 for 16.x)
# unless var.db_family is set — changing family+version together is how son
# repos move to a new engine generation.

resource "aws_rds_cluster_parameter_group" "this" {
  name        = local.cluster_pg_name
  family      = local.db_family
  description = "Cluster parameters for ${local.cluster_name}. Security baseline + son-repo overrides. Managed by Terraform (database/aurora-postgresql module)."

  dynamic "parameter" {
    for_each = local.cluster_parameters
    content {
      name         = parameter.key
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  tags = merge(local.tags, { Name = local.cluster_pg_name })

  lifecycle {
    # Family changes force replacement — create the new group before
    # destroying the old one so instances are never left without a group.
    create_before_destroy = true
  }
}

resource "aws_db_parameter_group" "this" {
  name        = local.instance_pg_name
  family      = local.db_family
  description = "Instance parameters for ${local.cluster_name}. Managed by Terraform (database/aurora-postgresql module)."

  dynamic "parameter" {
    for_each = local.instance_parameters
    content {
      name         = parameter.key
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  tags = merge(local.tags, { Name = local.instance_pg_name })

  lifecycle {
    create_before_destroy = true
  }
}
