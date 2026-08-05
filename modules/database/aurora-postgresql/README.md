# Módulo `database/aurora-postgresql`

> Cluster **Aurora PostgreSQL** hardenizado, desplegado dentro de una Spoke VPC existente (tier BDD) del modelo Hub-and-Spoke.

---

## Descripción

Una llamada al módulo = un cluster. Pensado para consumo **self-service** desde repos hijos (scaffolds de Port.io): el repo hijo solo pasa configuración; **los controles críticos están bloqueados en el módulo central y no se pueden degradar**.

> Contrato de plataforma: el desarrollador ajusta *lo que es suyo* (tamaño, consumidores, base de datos, tags) dentro de rieles; la postura de seguridad y cumplimiento la garantiza el módulo.

---

## Features

- **Serverless v2** — Escalado automático entre `min_acu` y `max_acu` (auto-pause en dev/qa)
- **Global Database** — Replicación cross-region para DR (prod → dr)
- **Log Groups gestionados** — Retención por ambiente + cifrado CMK
- **IAM Database Authentication** — Conexiones sin password desde pods IRSA
- **Performance Insights** — Habilitado por defecto con CMK
- **Enhanced Monitoring** — Forzado en prod-like (>= 60s)

---

## Convención de Nombres

| Recurso | Patrón |
|---------|--------|
| Cluster | `rds-aw-{region}-{workload}-{funcionalidad}-{ambiente}` |
| Instance | `rds-aw-{region}-{workload}-{funcionalidad}-{nn}-{ambiente}` |
| Subnet Group | `sng-aw-{region}-{workload}-{funcionalidad}-{ambiente}` |
| Cluster PG | `cpg-aw-{region}-{workload}-{funcionalidad}-{ambiente}` |
| Security Group | `sgp-aw-{region}-{workload}-{funcionalidad}-{ambiente}` |
| Global Cluster | `gdb-aw-{workload}-{funcionalidad}` |

Donde `{region}` = `ue1` (us-east-1) o `ue2` (us-east-2).

---

## Contrato de Configuración (3 Capas)

### LOCKED — NO overridable

| Control | Valor |
|---------|-------|
| Cifrado en reposo | CMK de cuenta `alias/RDS` (siempre) |
| TLS | `rds.force_ssl = 1` (solo conexiones cifradas) |
| Autenticación | IAM Database Authentication habilitada |
| Acceso público | `publicly_accessible = false` |
| Auditoría | pgaudit + `log_connections/disconnections`, `log_statement=ddl` |
| Upgrades mayores | `allow_major_version_upgrade = false` |
| Snapshots | `copy_tags_to_snapshot = true` |
| **Puerto** | **`15432`** (estándar de seguridad; no 5432) |
| Engine | allow-list: major >= 14 (13.x y anteriores rechazados) |

### GUARD-RAIL — Piso por ambiente (se puede SUBIR, nunca BAJAR)

| Control | dev / qa | preprod | prod / dr |
|---------|----------|---------|-----------|
| Multi-AZ | single (opt-UP) | single (opt-UP) | **multi (LOCKED)** |
| Retención PITR (piso) | 7 d | 7 d | **35 d** |
| Enhanced Monitoring | off (opt-in) | >= 60 s | >= 60 s |
| `apply_immediately` | true | **false** | **false** |
| Deletion protection | default ON | **ON (LOCKED)** | **ON (LOCKED)** |
| Techo `serverless_max_acu` | 8 | 16 | 64 |
| Retención log group | 30 d | 90 d | 365 d |
| Auto-pause (`min_acu=0`) | permitido | bloqueado | bloqueado |

### FREE — Autoservicio del hijo

- `database_name`, `engine_version` (>= 14)
- `allowed_security_group_ids` / `allowed_cidrs`
- `serverless_min_acu` / `serverless_max_acu` (bajo el techo)
- `instances` (readers extra / clase por instancia)
- `storage_type` (`aurora-iopt1` para I/O-Optimized)
- `cluster_parameters` / `instance_parameters` **no protegidos** (ej: `max_connections`, `work_mem`)
- `kms_consumer_role_arns`, `extra_tags`
- Retención de backup/log por encima del piso

---

## Puerto 15432

El cluster escucha en **15432** (constante de plataforma), aplicado tanto al cluster como a las reglas de ingress del Security Group. Los consumidores deben apuntar a `:15432`.

---

## Descubrimiento (sin IDs, sin estado compartido)

| Recurso | Cómo se resuelve |
|---------|------------------|
| Spoke VPC | tag `ou = {var.service}` |
| Subnets BDD | tags `Tier=bdd` + `AZ=a\|b` dentro de la VPC |
| CMK RDS | `alias/RDS` (o `kms_key_arn` explícito) |
| CMK CloudWatch Logs | `alias/CWLogs` (o `cloudwatch_logs_kms_key_arn`) |

El módulo **nunca crea llaves KMS** — las descubre por alias (baseline de cuenta).

---

## Guards (fallo temprano en `plan`)

`terraform_data.guards` valida antes de tocar nada:

1. **Account** — `aws_account_id` == cuenta activa
2. **Región** — región del provider == `var.aws_region`, y `dr` implica `us-east-2`
3. **Credencial** — `master_password` >= 16 chars (cuando no es global-secondary)
4. **ACU** — `max_acu >= min_acu` y bajo el techo del ambiente
5. **Topology** — prod/dr requiere instancias en ambas AZ

---

## Outputs Principales

| Output | Descripción |
|--------|-------------|
| `writer_endpoint` | Endpoint escritura (read/write) |
| `reader_endpoint` | Endpoint lectura (load-balanced) |
| `port` | Puerto del cluster (15432) |
| `cluster_resource_id` | Resource ID para ARNs `rds-db:connect` |
| `iam_auth_resource_arn_prefix` | Prefijo ARN para IAM DB Auth |
| `security_group_id` | SG del módulo |
| `kms_key_arn` | CMK de storage |
| `cloudwatch_log_group_name` | Nombre del log group PostgreSQL |
| `storage_type` | Modelo de storage efectivo |
| `global_cluster_identifier` | ID del Global Database (si habilitado) |
| `instance_identifiers` | Map instance_key → identifier |

---

## Uso (desde terragrunt.hcl del repo hijo)

```hcl
terraform {
  source = "git::https://github.com/bin-transversales-devops/platform-orchestrator-automation-terraform//modules/database/aurora-postgresql?ref=v3.1.0"
}

inputs = {
  engine_version     = "17.7"
  serverless         = true
  serverless_min_acu = 0     # auto-pause (solo dev/qa)
  serverless_max_acu = 4     # bajo el techo del ambiente
  database_name      = "app_db"

  allowed_security_group_ids = ["sg-xxxxxxxx"]

  # storage_type = "aurora-iopt1"  # FinOps: I/O-Optimized (opcional)

  aplicacion          = "MiApp"
  propietario_recurso = "MiEquipo"
  producto            = "MiProducto"
  centro_costo        = "CC-1234"
}
```

Variables `service`, `ambiente`, `workload`, `funcionalidad` y `aws_account_id` se inyectan vía `extra_vars` desde el workflow. `master_password` se inyecta vía BeyondTrust → `TF_VAR_master_password`.

---

## Observabilidad

- Export de logs PostgreSQL a un **log group gestionado** (retención por ambiente + cifrado `alias/CWLogs`)
- Enhanced Monitoring (rol dedicado) y Performance Insights (misma CMK RDS)
- Log group name expuesto como output → consumido por `newrelic-spoke` para subscription filters
