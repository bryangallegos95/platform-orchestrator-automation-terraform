# Módulo `database/aurora-postgresql`

Cluster **Aurora PostgreSQL** hardenizado, desplegado dentro de una Spoke VPC
existente (tier BDD) del modelo Hub-and-Spoke. Una llamada al módulo = un
cluster. Pensado para consumo **self-service** desde repos hijos (scaffolds de
Port.io): el repo hijo sólo pasa configuración; **los controles críticos están
bloqueados en el módulo central y no se pueden degradar**.

> Contrato de plataforma: el desarrollador ajusta *lo que es suyo* (tamaño,
> consumidores, base de datos, tags) dentro de rieles; la postura de seguridad
> y cumplimiento la garantiza el módulo.

---

## 🧱 Contrato de configuración (3 capas)

### 🔒 LOCKED — invariante, idéntico en todos los ambientes, NO overridable

| Control | Valor |
|---|---|
| Cifrado en reposo | CMK de cuenta `alias/RDS` (siempre) |
| TLS | `rds.force_ssl = 1` (sólo conexiones cifradas) |
| Autenticación | IAM Database Authentication habilitada |
| Acceso público | `publicly_accessible = false` |
| Auditoría / logging | pgaudit + `log_connections/disconnections`, `log_statement=ddl`, slow-query — **nombres de parámetro protegidos** (un override del hijo se rechaza en `plan`) |
| Upgrades mayores | `allow_major_version_upgrade = false` |
| Snapshots | `copy_tags_to_snapshot = true` |
| **Puerto** | **`15432`** (estándar de seguridad; no 5432) |
| Engine | allow-list: major ≥ 14 (13.x y anteriores EOL → rechazado) |

### 🛡️ GUARD-RAIL — piso por ambiente que el hijo puede SUBIR, nunca BAJAR

| Control | dev / qa | preprod | prod / dr |
|---|---|---|---|
| Multi-AZ | single (opt-UP) | single (opt-UP) | **multi (LOCKED)** |
| Retención PITR (piso) | 7 d | 7 d | **35 d** |
| Enhanced Monitoring | off (opt-in) | ≥ 60 s | ≥ 60 s |
| `apply_immediately` | true | **false** | **false** |
| Deletion protection | default **ON**¹ | **ON (LOCKED)** | **ON (LOCKED)** |
| Techo `serverless_max_acu` | 8 | 16 | 64 |
| Retención log group | 30 d | 90 d | 365 d |
| Auto-pause (`min_acu=0`) | permitido | bloqueado | bloqueado |

¹ En dev/qa el default es ON para proteger ambientes de desarrollo "oficiales"
(evita perder trabajo de un equipo). Para un cluster **efímero** el hijo pone
explícitamente `deletion_protection = false`.

### 🎚️ FREE — autoservicio del hijo, dentro de los rieles

`database_name`, `allowed_security_group_ids` / `allowed_cidrs`,
`serverless_min_acu` / `serverless_max_acu` (bajo el techo), `instances`
(readers extra / clase por instancia), `storage_type` (`aurora-iopt1` FinOps),
`cluster_parameters` / `instance_parameters` **no protegidos** (p.ej.
`max_connections`, `work_mem`), `kms_consumer_role_arns`, tags, retención de
backup/log por encima del piso.

---

## 🔌 Puerto 15432

El cluster escucha en **15432** (constante de plataforma, `local.db_port`),
aplicado tanto al cluster como a las reglas de ingress del Security Group. Los
consumidores (lambda/ECS/EC2) deben apuntar a `:15432`. El output `port` lo
expone para construir cadenas de conexión.

> Cambiar el puerto en un cluster **existente** es disruptivo (modificación +
> reinicio). En despliegues nuevos es transparente.

---

## 🔎 Descubrimiento (sin IDs, sin estado compartido)

| Recurso | Cómo se resuelve |
|---|---|
| Spoke VPC | tag `Name = vpc-aw-{region_short}-{service}-{ambiente}` |
| Subnets BDD | tags `Tier=bdd` + `AZ=a\|b` dentro de la VPC |
| CMK RDS (storage/PI) | `alias/RDS` (`var.kms_key_alias`) o `kms_key_arn` |
| CMK CloudWatch Logs | `alias/CWLogs` (`var.cloudwatch_logs_kms_key_alias`) o `cloudwatch_logs_kms_key_arn` |

El módulo **nunca crea llaves KMS** — las descubre por alias (baseline de cuenta).

## 🛡️ Guards (fallo temprano en `plan`)

`terraform_data.guards` valida antes de tocar nada:
1. **Account** — `aws_account_id` == cuenta activa.
2. **Región** — región del provider == `var.aws_region`, y `dr` ⇒ `us-east-2`.

Preconditions adicionales en el cluster: credencial admin presente (≥16),
`max_acu ≥ min_acu`, techo de ACU por ambiente, engine mínimo para auto-pause,
y prod/dr con instancias en ambas AZ.

## 🪵 Observabilidad

- Export de logs PostgreSQL a un **log group gestionado** (`logs.tf`): retención
  por ambiente + cifrado `alias/CWLogs` (evita el default *never-expire* sin CMK).
- Enhanced Monitoring (rol dedicado) y Performance Insights (misma CMK RDS).

> **Etapa 2 (pendiente):** alarmas base de CloudWatch + `aws_db_event_subscription`
> hacia la **cuenta de Audit** (SNS/EventBridge central), y **AWS Backup** con
> vault inmutable en la **cuenta central de Backups** (prod). No incluidos aquí
> porque dependen de esas cuentas de landing zone.

---

## 🚀 Uso (desde el `terragrunt.hcl` del repo hijo)

```hcl
terraform {
  # Fijar al tag que publica el contrato hardenizado (o a la rama para validar).
  source = "git::https://github.com/bin-transversales-devops/platform-orchestrator-automation-terraform//modules/database/aurora-postgresql?ref=vX.Y.Z"
}

inputs = {
  engine_version     = "16.6"
  serverless         = true
  serverless_min_acu = 0   # auto-pause (sólo dev/qa)
  serverless_max_acu = 4   # bajo el techo del ambiente
  database_name      = "app_db"

  allowed_security_group_ids = ["sg-xxxxxxxx"] # consumidores (preferir SG-a-SG)

  # storage_type = "aurora-iopt1"  # FinOps: I/O-Optimized (opcional)

  aplicacion          = "MiApp"
  propietario_recurso = "MiEquipo"
  producto            = "MiProducto"
  centro_costo        = "CC-1234"
}
```

`service`, `ambiente`, `workload` y `aws_account_id` se inyectan vía
`extra_vars` desde el workflow; `master_password` vía BeyondTrust →
`TF_VAR_master_password`.

## 📤 Outputs principales

`writer_endpoint`, `reader_endpoint`, `port` (15432), `cluster_resource_id`,
`iam_auth_resource_arn_prefix`, `security_group_id`, `kms_key_arn`,
`cloudwatch_log_group_name`, `storage_type`, `global_cluster_identifier`.
