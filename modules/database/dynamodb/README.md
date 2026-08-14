# Módulo `database/dynamodb`

> Set de tablas **DynamoDB** hardenizadas para la plataforma **Central Log** (trazabilidad de aplicaciones, servicios y logs).

---

> ### BORRADOR — pendiente de validar contra `platform-knowledge-base`
>
> Este módulo se escribió **sin acceso** al repo `platform-knowledge-base` (naming conventions oficiales, mapa de cuentas, baseline de seguridad).
> Todo lo que normalmente vendría de esa fuente está marcado en el código como `# TODO: validar contra platform-knowledge-base` y **es propuesta, no decisión**:
>
> | Punto pendiente | Valor propuesto | Dónde se cambia |
> |-----------------|-----------------|-----------------|
> | Convención de nombres | `ddb-aw-{region}-{workload}-{funcionalidad}-{tabla}-{ambiente}` | `locals.tf` → `resource_prefix` (1 línea) |
> | Alias de la CMK | `alias/DynamoDB` (**alias real desconocido**) | `variables.tf` → `kms_alias` |
> | PITR como LOCKED | siempre ON, sin variable | `main.tf` → bloque `point_in_time_recovery` |
> | Deletion protection | piso ON en prod-like | `locals.tf` → `deletion_protection_floor` |
> | Piso de retención TTL | 365 d prod-like / 30 d dev-qa | `locals.tf` → `ttl_retention_floor_days` |
> | TTL espejo en payloads | ON — el payload expira con su log padre | `locals.tf` → `payload_ttl_enabled` |
> | Billing mode | `PAY_PER_REQUEST` | `variables.tf` → `billing_mode` |
> | Proyección de GSIs | `ALL` | `variables.tf` → `gsi_projection_type` |
> | Atributo del GSI 3 de `logs` | `estado` (la fuente dice `estado` como atributo y `status` como GSI) | `locals.tf` → `logs_status_attribute` |
> | Postura de DR | **ninguna asumida** (sin Global Tables) | `guards.tf` (guard comentado) |

---

## Descripción

Una llamada al módulo = **el set completo de 6 tablas**. No son building blocks independientes: forman un único modelo de datos (`logs` ↔ `log-payloads`, `wait-logs` ↔ `wait-payloads`) y se versionan juntas.

Pensado para consumo **self-service** desde repos hijos: el repo hijo solo pasa configuración; **los controles críticos están bloqueados en el módulo central y no se pueden degradar**.

A diferencia de `aurora-postgresql` y `elasticache-serverless`, **DynamoDB es un servicio regional sin VPC**: no hay descubrimiento de VPC/subnets ni Security Groups. La única dependencia externa es la **CMK de cuenta, descubierta por alias**.

---

## Modelo de datos

DynamoDB es *schemaless*: Terraform solo declara los atributos que participan en una **key** (de tabla o de índice). Los atributos no-clave se documentan aquí y en `locals.tf`, pero no se declaran (el provider los rechaza).

| Tabla | PK | SK | Atributos no-clave | TTL | Streams | GSIs |
|-------|----|----|--------------------|-----|---------|------|
| `applications` | `application_code` (S) | — | `nombre`, `estado`, `descripcion`, `creation_date` | — | — | — |
| `services` | `service_code` (S) | `application_code` (S) | `estado`, `tipo`, `service_name` | — | — | — |
| `logs` | `id_log` (S) | — | `client_id` (+ `ttl`) | — | 4 |
| `log-payloads` | `id_log` (S) | — | `data_in`, `data_out`, `additional_data`, `data_type` (+ `ttl`) | (propuesto, espejo del padre)* | — | — |
| `wait-logs` | `id_wait_log` (S) | — | `application_code`, `service_code`, `estado` (+ `ttl`) | | — |
| `wait-payloads` | `id_wait_log` (S) | — | `data_in`, `data_out`, `additional_data`, `data_type` (+ `ttl`) | (propuesto, espejo del padre)* | — | — |

En `logs`, los atributos `application_code`, `service_code`, `timestamp`, `estado` y `user_name` **sí** se declaran porque son keys de sus GSIs.

### GSIs de `logs`

| Índice | HASH | RANGE |
|--------|------|-------|
| `application-code-timestamp-index` | `application_code` (S) | `timestamp` (N, epoch) |
| `service-code-timestamp-index` | `service_code` (S) | `timestamp` (N, epoch) |
| `status-timestamp-index` | `estado` (S) | `timestamp` (N, epoch) |
| `user-name-timestamp-index` | `user_name` (S) | `timestamp` (N, epoch) |

El análisis de Central Log lista el atributo de la tabla como `estado` pero nombra el GSI 3 sobre `status`. Se asumió `estado` por consistencia con el resto del modelo; se define **una sola vez** en `locals.tf` (`logs_status_attribute`). **Cambiar la key de un GSI ya creado obliga a recrear el índice**, así que conviene confirmarlo antes del primer apply.

> `timestamp` es palabra reservada en las *expressions* de DynamoDB: la aplicación debe usar `ExpressionAttributeNames` (`#ts`) al consultar. No afecta a la definición del índice.

### Separación logs / payloads

`log-payloads` y `wait-payloads` existen para mantener los blobs (`data_in`, `data_out`, `additional_data`) fuera de la tabla caliente: con `gsi_projection_type = ALL`, cada payload en `logs` se replicaría en los 4 GSIs.

---

## Convención de Nombres — PROPUESTA

| Recurso | Patrón propuesto |
|---------|------------------|
| Tabla | `ddb-aw-{region}-{workload}-{funcionalidad}-{tabla}-{ambiente}` |
| GSI | `{atributo}-timestamp-index` |
| KMS grant | `ddb-aw-{region}-{workload}-{funcionalidad}-{ambiente}-{label}` |

Donde `{region}` = `ue1` (us-east-1) o `ue2` (us-east-2), y `{tabla}` es la clave lógica (`applications`, `services`, `logs`, `log-payloads`, `wait-logs`, `wait-payloads`).

Ejemplo: `ddb-aw-ue1-centrallog-trazabilidad-logs-prod`

> **Pendiente de validar contra `platform-knowledge-base`.** Es análogo al patrón `rds-aw-...` de Aurora y `ec-aw-...` de ElastiCache, con un segmento extra `{tabla}` porque el módulo crea 6 recursos del mismo tipo. Se deriva íntegramente de `local.resource_prefix`.

---

## Contrato de Configuración (3 Capas) — BORRADOR

### LOCKED — NO overridable

| Control | Valor | Estado |
|---------|-------|--------|
| Cifrado en reposo | CMK de cuenta (`var.kms_alias`), nunca `alias/aws/dynamodb` | firme (baseline del repo) |
| Point-in-Time Recovery | habilitado en las 6 tablas | **propuesto** — barato y buena práctica; confirmar si el baseline lo quiere GUARD-RAIL por ambiente |
| Catálogo de tablas | las 6 tablas, fijas en `locals.tf` | propuesto — el hijo no elige subconjunto |
| Key schema (PK/SK) | fijo por tabla | firme (define el modelo) |
| Definición de GSIs (keys) | 4 GSIs en `logs` | propuesto — la *proyección* sí es FREE |
| Streams en `wait-logs` | `NEW_AND_OLD_IMAGES` | firme (lo exige el Lambda `wait-processor`) |
| TTL habilitado en `logs` y `wait-logs` | sí — y **espejado en `log-payloads` / `wait-payloads`** con el mismo atributo | propuesto — el espejo evita payloads huérfanos; confirmar si auditoría exige que el payload sobreviva al log padre |

En línea con `AGENTS.md` ("no añadir variables para settings LOCKED"), **no existe** variable para desactivar PITR ni el cifrado.

### GUARD-RAIL — Piso por ambiente (se puede SUBIR, nunca BAJAR)

| Control | dev / qa | preprod | prod / dr | Estado |
|---------|----------|---------|-----------|--------|
| Deletion protection | opt-in (default OFF) | **ON (piso)** | **ON (piso)** | propuesto — mismo criterio que Aurora |
| Retención TTL (piso) | 30 d | 365 d | 365 d | propuesto — sin requisito regulatorio confirmado |

Los pisos se aplican en `locals.tf` y se verifican con `precondition` en `main.tf`.

### FREE — Autoservicio del hijo

- `billing_mode` (`PAY_PER_REQUEST` por defecto) + `provisioned_read_capacity` / `provisioned_write_capacity`
- `table_class` (`STANDARD` / `STANDARD_INFREQUENT_ACCESS`)
- `gsi_projection_type` (`ALL` / `KEYS_ONLY`)
- `ttl_attribute_name`, `ttl_retention_days` (por encima del piso)
- `deletion_protection_enabled` (solo para SUBIRlo en dev/qa)
- `kms_alias` / `kms_key_arn`, `kms_consumer_role_arns`
- `extra_tags`

---

## Capacidad: por qué `PAY_PER_REQUEST`

Sin métricas de tráfico real de Central Log, dimensionar RCU/WCU es adivinar: se sobre-provisiona (coste fijo 24/7) o se infra-provisiona (throttling). `PAY_PER_REQUEST` absorbe los picos de escritura de logs sin capacity planning.

Cuando existan métricas (`ConsumedReadCapacityUnits` / `ConsumedWriteCapacityUnits` a 30-60 días), pasar a `PROVISIONED` es un cambio de variables:

```hcl
billing_mode               = "PROVISIONED"
provisioned_read_capacity  = 25
provisioned_write_capacity = 50
```

Un `precondition` exige que ambas capacities estén presentes con `PROVISIONED` y ausentes con `PAY_PER_REQUEST`.

> Autoscaling de capacidad provisionada (`aws_appautoscaling_target`) **no** está modelado todavía.

---

## TTL: qué hace y qué NO hace el módulo

El módulo **habilita el mecanismo**: marca el atributo `ttl` como atributo de expiración en `logs` / `wait-logs` y, por espejo, en `log-payloads` / `wait-payloads`.

DynamoDB **no acepta "días"** — expira ítems cuyo atributo `ttl` contenga un epoch (segundos) pasado. **La aplicación productora debe escribir ese valor.** Por eso `ttl_retention_days` se expone como *output*: el API / Lambda calcula `now + ttl_retention_days` al insertar.

Si un ítem no lleva el atributo, **nunca expira**.

### TTL espejo en las tablas de payloads

`log-payloads` y `wait-payloads` son 1:1 con sus tablas padre (misma key: `id_log` / `id_wait_log`). Sin TTL espejo, cuando el log padre expira **el payload queda huérfano para siempre**: la tabla que se separó justamente para aliviar el tamaño de `logs` crece sin control.

Por eso el productor debe escribir el **mismo** atributo `ttl` con el **mismo** epoch al insertar el par log + payload. DynamoDB no propaga la expiración entre tablas: son dos TTL independientes que solo coinciden si la aplicación escribe el mismo valor.

> **Propuesta pendiente** de confirmar con el equipo de Central Log: se asume que el payload expira *en el mismo momento* que su log padre. Si un requisito de auditoría exige que el payload sobreviva al log, esto deja de ser un booleano y hace falta un desfase de retención propio para las tablas de payloads. Se controla en `locals.tf` → `payload_ttl_enabled`.

---

## Descubrimiento (sin IDs, sin estado compartido)

| Recurso | Cómo se resuelve |
|---------|------------------|
| CMK DynamoDB | `alias/DynamoDB` *(alias real por confirmar)* — o `kms_key_arn` explícito |

El módulo **nunca crea llaves KMS**. No hay lookup de VPC/subnets: DynamoDB no vive en la VPC.

---

## Guards (fallo temprano en `plan`)

`terraform_data.guards` valida antes de tocar nada:

1. **Account** — `aws_account_id` == cuenta activa (si no, el lookup de la CMK apuntaría a otra cuenta)
2. **Región** — región del provider == `var.aws_region` (una región equivocada crea un set de tablas vacío en vez de fallar)

**Sin guard de DR.** Aurora exige `ambiente=dr ⇒ us-east-2` porque su DR es Global Database. Para DynamoDB no hay postura de DR definida todavía (Global Tables vs. backup cross-region vs. sin DR); el guard equivalente queda comentado en `guards.tf`.

---

## Outputs Principales

| Output | Descripción |
|--------|-------------|
| `table_names` | Map clave lógica → nombre real en AWS |
| `table_arns` | Map clave lógica → ARN (input de las policies IRSA) |
| `index_arns` | ARNs `{tabla}/index/*` — **necesarios en IAM**: el permiso sobre la tabla base no cubre sus GSIs |
| `stream_arns` | Stream ARN de las tablas con Streams (hoy `wait-logs`) → event source mapping del Lambda |
| `gsi_names` | Map tabla → nombres de GSI |
| `ttl_attribute_name` | Atributo que debe escribir el productor |
| `ttl_retention_days` | Días efectivos para calcular el epoch |
| `kms_key_arn` | CMK de cifrado en reposo |
| `billing_mode` | Modo de capacidad efectivo |

---

## Uso (desde terragrunt.hcl del repo hijo)

```hcl
terraform {
  source = "git::https://github.com/bin-transversales-devops/platform-orchestrator-automation-terraform//modules/database/dynamodb?ref=<pendiente>"
}

inputs = {
  # billing_mode = "PAY_PER_REQUEST"   # default
  # table_class  = "STANDARD"          # default

  aplicacion          = "CentralLog"
  propietario_recurso = "MiEquipo"
  producto            = "MiProducto"
  centro_costo        = "CC-1234"
}
```

Variables `ambiente`, `workload`, `funcionalidad`, `aws_region` y `aws_account_id` se inyectan vía `extra_vars` desde el workflow.

---

## Fuera de alcance en esta pasada

- **Compositor** (`modules/product/`) — el bloque `dynamodb.tf` se añade una vez validado el módulo
- **Policies IAM automáticas** (`modules/identity/irsa-role/`) — consumirán `table_arns` + `index_arns`
- **Autoscaling** de capacidad provisionada
- **Global Tables / postura de DR**
- **Alarmas CloudWatch** (throttling, `SystemErrors`, consumo vs. capacidad)
- **Backups gestionados** más allá de PITR (AWS Backup)
