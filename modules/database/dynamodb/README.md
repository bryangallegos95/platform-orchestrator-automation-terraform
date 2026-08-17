# Módulo `database/dynamodb`

> Capa de persistencia **DynamoDB** de la plataforma **Central Log**: 5 tablas hardenizadas, cifradas con CMK de cuenta, con Streams y Auto Scaling.

---

## Descripción

Una llamada al módulo = las **5 tablas** del modelo de datos de auditoría transaccional definido en `CL-LLD-DAT-01` (§5 y §10.1). El módulo no requiere VPC: DynamoDB es un servicio gestionado regional.

El esquema **no es negociable desde el son repo**. Cada clave, cada índice y cada ausencia de índice responde a una decisión razonada del documento de diseño — en particular la ausencia deliberada de GSIs sobre `logs`, que es el mayor ahorro estructural del diseño (~USD 375/mes por cada GSI que no se crea, a 10M escrituras/día).

**Fuera de alcance de este módulo:** el camino analítico (Glue + Firehose + Athena) y OpenSearch. El primero irá en un módulo aparte; el segundo **no se construye** (`CL-LLD-DAT-02`), pero los Streams quedan habilitados para que la capacidad pueda reactivarse sin pérdida de datos.

---

## Las 5 tablas

| # | Tabla | PK | SK | GSI | TTL | Stream | Billing |
|---|-------|----|----|-----|-----|--------|---------|
| 1 | `{prefix}-logs` | `pk` = `C#<client_id tokenizado>#<hw_date>` | `sk` = `<trx_date>#<log_id>` | **ninguno** | sí | `NEW_IMAGE` | `var.billing_mode` |
| 2 | `{prefix}-log-payloads` | `lid` (= log_id) | — | ninguno | sí | no | `var.billing_mode` |
| 3 | `{prefix}-applications` | `app` | — | `gsi-app-state` (HASH `st`) | no | `NEW_IMAGE` | `PAY_PER_REQUEST` |
| 4 | `{prefix}-services` | `app` | `svc` | `gsi-svc-state` (HASH `st`, RANGE `asv`) | no | `NEW_IMAGE` | `PAY_PER_REQUEST` |
| 5 | `{prefix}-wait-logs` | `pk` = `W#<app>#<svc>` | `sk` = `<trx_date>#<wait_id>` | `gsi-wait-pending` (HASH `pnd`, RANGE `ts`) — **disperso** | sí | no | `PAY_PER_REQUEST` |

### Por qué `logs` no tiene GSIs

La consulta principal de la pantalla *Consulta de Logs* es **un cliente en una fecha**, y la clave de partición replica exactamente ese contrato: se resuelve con un solo `Query` (`pk = ...` + `sk BETWEEN`), sin fan-out, sin índice y sin motor de búsqueda. Los tres GSIs del diseño anterior (`gsi-log-level`, `gsi-trace-id`, `gsi-service`) provenían de una plantilla genérica de observabilidad de aplicaciones — `log_level` y `trace_id` **no existen** en el modelo de la aplicación — y `service_code` como PK de GSI tiene cardinalidad de decenas de valores para 10M escrituras/día: partición caliente garantizada.

Solo se declaran `pk` y `sk` como `attribute`. **`client_id` y `hw_date` NO se declaran**: son componentes *dentro* del string `pk`, y DynamoDB rechaza toda `AttributeDefinition` que no participe en el esquema de una clave — declararlos haría fallar el despliegue.

### El índice disperso de `wait-logs`

`gsi-wait-pending` usa el idioma del índice secundario disperso: un ítem solo aparece en el índice si posee el atributo que actúa como su clave. La aplicación escribe `pnd = "<app>#<svc>"` al encolar y ejecuta `REMOVE pnd` al liberar, de modo que **el índice contiene por construcción exclusivamente lo pendiente**, sin filtro ni escaneo. Sustituye al `gsi-status` anterior, cuya clave de partición tenía dos valores posibles (`PEN`/`REL`).

---

## Contrato de Configuración (3 Capas)

### LOCKED

| Control | Valor |
|---------|-------|
| Cifrado en reposo | CMK de cuenta `alias/DynamoDB` (SSE-KMS, siempre). **Nunca** la clave AWS-owned |
| Catálogo de tablas | Las 5 tablas, fijas |
| Key schema | PK/SK y GSIs de cada tabla, fijos |
| `prevent_destroy` | `true` en `logs` |
| Streams | `NEW_IMAGE` en `logs`, `applications` y `services` |
| TTL habilitado | `logs`, `log-payloads`, `wait-logs` |
| Billing del catálogo | `PAY_PER_REQUEST` en `applications`, `services`, `wait-logs` |

### GUARD-RAIL

| Control | dev | test | uat | prod |
|---------|-----|------|-----|------|
| Deletion protection | ON por defecto (puede bajarse) | ON por defecto (puede bajarse) | **forzado ON** | **forzado ON** |
| PITR | ON por defecto (puede bajarse) | ON por defecto (puede bajarse) | **forzado ON** | **forzado ON** |
| Retención TTL (piso, días) | 7 | 15 | 30 | 30 |
| Techo WCU de Auto Scaling | 200 | 200 | 500 | 1500 |
| Techo RCU de Auto Scaling | 200 | 200 | 500 | 1000 |

Los cuatro ambientes (`dev`, `test`, `uat`, `prod`) viven en **cuatro cuentas AWS separadas** (`CL-LLD-ARQ-C0`). `uat` toma el mismo piso de retención que `prod` por ser el ambiente de aceptación. No existe un ambiente `dr`: la resiliencia cross-region es replicación S3 **dentro de** la cuenta de `prod`, no una cuenta ni un `ambiente` aparte.

Los techos de capacidad **se recortan (clamp)**, no se rechazan: el default del módulo está dimensionado para producción (§8.2) y seguiría siendo usable en dev sin que el son repo tenga que repetirlo. Lo que sí falla el plan es un `read_capacity`/`write_capacity` (el mínimo de Auto Scaling) por encima del techo efectivo.

### FREE

- `billing_mode` (`PAY_PER_REQUEST` / `PROVISIONED`)
- `read_capacity`, `write_capacity`, `read_capacity_max`, `write_capacity_max` (bajo el techo)
- `autoscaling_target_utilization` (20-90, default 70)
- `ttl_attribute_name` (default `exp`)
- `kms_key_alias` / `kms_key_arn` (qué CMK, no *si* hay CMK)
- `extra_tags`

---

## `billing_mode` y Auto Scaling

Criterio fijado en `CL-LLD-DAT-01` §8.2: **`PAY_PER_REQUEST` en ambientes bajos** (volumen esporádico) y **`PROVISIONED` + Auto Scaling en producción** (carga sostenida, predecible, con estacionalidad diaria conocida). A 10M registros/día el ahorro sobre On-Demand ronda el **78 %** (~USD 383 → ~USD 85/mes).

Con `billing_mode = "PROVISIONED"` el módulo añade cuatro recursos sobre la tabla `logs`: `aws_appautoscaling_target` + `aws_appautoscaling_policy` para lectura y escritura, con target tracking al **70 %** de utilización.

> El *throttling* de escritura en esta tabla equivale a **pérdida potencial de registros de auditoría** (§8.5). Es la razón de que el objetivo de escritura no sea opcional una vez que se aprovisiona capacidad.

---

## TTL: lo que Terraform controla y lo que no

Una configuración TTL de DynamoDB **solo nombra el atributo** que lleva el epoch de vencimiento. La **ventana de retención** vive en quien escribe ese atributo: la Lambda de ingesta calcula `exp = now + retención`.

Por eso el módulo:

- declara `ttl { attribute_name = var.ttl_attribute_name, enabled = true }` en las tres tablas que lo tienen, y
- publica `ttl_retention_days` y `ttl_attribute_name` como **outputs**, para que la capa de aplicación consuma el mismo contrato que la infraestructura declara.

El atributo es `exp` (§7.2), **no** `ttl` ni `expires_at`.

> **Punto crítico de cumplimiento** (§7.2): la Lambda de procesamiento debe confirmar la escritura en S3 **antes** de que un registro pueda expirar por TTL. DynamoDB no es el repositorio de retención regulatoria — esa es S3 con Object Lock (WORM), 10+ años.

---

## Decisiones de negocio pendientes

Ninguna bloquea construir el módulo. Están marcadas en el código con `# TODO: decisión de negocio pendiente`.

| # | Decisión | Estado en este módulo | Impacto |
|---|----------|-----------------------|---------|
| 1 | **Ventana de retención caliente**: 30 o 90 días (`CL-LLD-DAT-01` §12.2 #4) | Variable `ttl_retention_days`, **default 30** (la opción barata), con piso de 30 días en `uat`/`prod` | ~USD 123/mes de diferencia. Debe confirmarlo **Negocio + Operaciones**, dimensionando por la antigüedad típica de una investigación |
| 2 | **`gsi-seq` sobre `logs`** (§5.1.3, §12.2 #5) | **NO se despliega.** Documentado como adición futura en el comentario de la tabla `logs` en `main.tf` | ~USD 110/mes. Permitiría partir de un número de transacción sin conocer el cliente — caso habitual en investigación de fraude. Un GSI se puede añadir sobre una tabla existente sin reprocesar el histórico, de modo que dejarlo fuera es reversible. Decidir con **evidencia de uso real** (Fraude / Auditoría) |
| 3 | **Atomicidad en la liberación de `wait-logs`** (§12.2 #6) | **Fuera del alcance de Terraform** | Es una decisión de la capa de aplicación: `TransactWriteItems` (atómico, consume el doble de WCU) frente a escrituras idempotentes. La escritura en `logs` es idempotente por diseño (`ConditionExpression` con `attribute_not_exists`), lo que hace segura la implementación no transaccional — que es la opción recomendada por costo y simplicidad. **Quien construya el Lambda de liberación debe resolverlo** |

---

## Naming — pendiente de contrastar

El módulo usa el patrón simple de la implementación de referencia ya validada:

```
{name_prefix}-logs   {name_prefix}-log-payloads   {name_prefix}-applications
{name_prefix}-services   {name_prefix}-wait-logs
```

**Queda pendiente contrastarlo contra `platform-knowledge-base`** si en algún momento se obtiene acceso. El punto concreto a resolver: `scripts/naming_pattern_validator.sh` de este repo **sí valida `aws_dynamodb_table`** contra la convención corporativa

```
{tipo}-{aw}-{region}-{funcion}-{ambiente}     p. ej.  ddb-aw-ue1-centrallog-logs-dev
```

y un nombre `{name_prefix}-logs` **no la cumple**, porque el `{ambiente}` debe ser el último segmento y aquí el discriminador de tabla va al final. No es algo que un `name_prefix` pueda arreglar: si se adopta la convención corporativa, el nombre debe componerse dentro del módulo como `ddb-aw-{region_short}-{workload}-{funcionalidad}-{tabla}-{ambiente}`. Las variables `workload` y `funcionalidad` ya están declaradas (opcionales, hoy sin uso en el naming) precisamente para ese cambio.

Mientras tanto, el pipeline de un son repo que consuma este módulo **fallará el paso de validación de naming** si lo ejecuta en modo bloqueante sobre estas tablas.

---

## Descubrimiento

| Recurso | Cómo se resuelve |
|---------|------------------|
| CMK DynamoDB | `alias/DynamoDB` (o `kms_key_arn` explícito) |
| VPC / subredes / SG | **No aplica** — DynamoDB es un servicio regional gestionado |

> El alias `alias/DynamoDB` sigue la convención de los demás módulos (`alias/RDS`, `alias/SQS_SNS`, `alias/ElastiCache`, `alias/S3`). **Confirmar contra el baseline de la cuenta antes del primer apply**: si el alias no existe, el `data "aws_kms_alias"` falla en plan.

---

## Guards (plan-time)

| Guard | Qué comprueba |
|-------|---------------|
| Account | `var.aws_account_id` == cuenta activa |
| Region | Región del provider == `var.aws_region` |

Las cinco tablas llevan `depends_on = [terraform_data.guards]`: un guard violado falla **antes** de tocar ningún recurso.

---

## Outputs

| Output | Descripción |
|--------|-------------|
| `logs_table_name` / `logs_table_arn` | Tabla principal de logs |
| `payloads_table_name` / `payloads_table_arn` | Cache caliente de payloads |
| `applications_table_name` / `applications_table_arn` | Catálogo de aplicaciones |
| `services_table_name` / `services_table_arn` | Catálogo de servicios |
| `wait_logs_table_name` / `wait_logs_table_arn` | Logs en espera |
| `table_names` | Map: clave lógica → nombre de tabla |
| `table_arns` | ARNs de las 5 tablas |
| `index_arns` | Patrones `/index/*` de `applications`, `services` y `wait-logs`. **`logs` NO aparece**: no tiene índices, y conceder un patrón vacío solo confunde a quien audite la política |
| `iam_resource_arns` | `table_arns` + `index_arns`, listo para el bloque `Resource` de una policy |
| `logs_stream_arn` | Stream de `logs` → archivo analítico en S3 |
| `catalog_stream_arns` | Streams de `applications` y `services` → invalidación de caché en las Lambdas |
| `ttl_attribute_name` / `ttl_retention_days` | Contrato de TTL para la capa de aplicación |
| `kms_key_arn` | CMK de cifrado at-rest |
| `billing_mode`, `autoscaling_enabled`, `capacity_ceilings` | Contexto de configuración efectiva |

---

## Control de acceso (para quien construya las Lambdas)

`CL-LLD-DAT-01` §9.3 fija el privilegio mínimo por función. Estos permisos **no los crea este módulo** — se declaran en el rol de cada Lambda usando `iam_resource_arns`:

| Rol | Permisos |
|-----|----------|
| Lambda de ingesta | `GetItem` sobre las tablas de catálogo **únicamente** |
| Lambda de procesamiento | `PutItem`, `UpdateItem` sobre `logs`, `log-payloads`, `wait-logs`. **Sin `DeleteItem`** |
| Lambda de consulta | `Query`, `GetItem`. **Solo lectura** |
| Lambda de liberación | `Query` sobre `gsi-wait-pending`; `PutItem` en `logs`; `UpdateItem` en `wait-logs` |
| Operadores humanos | **Sin acceso directo a los datos** |

> **Ninguna función debe tener `DeleteItem` sobre `logs`.** La única vía de eliminación es el TTL. Es un control de integridad exigible por auditoría: hace estructuralmente imposible el borrado programático de un registro de auditoría. DynamoDB **no** ofrece un WORM equivalente al Object Lock de S3 — la inmutabilidad es *de facto*, sostenida por la ausencia de `DeleteItem`, las escrituras condicionales con `attribute_not_exists` y CloudTrail Data Events.

---

## Uso

```hcl
module "dynamodb" {
  source = "git::https://github.com/bin-transversales-devops/platform-orchestrator-automation-terraform.git//modules/database/dynamodb?ref=v3.2.0"

  aws_region     = "us-east-1"
  aws_account_id = "123456789012"
  ambiente       = "dev"
  name_prefix    = "centrallog-dev"

  # FREE — On-Demand en ambientes bajos, PROVISIONED + Auto Scaling en prod
  billing_mode = "PAY_PER_REQUEST"

  # GUARD-RAIL — decisión de negocio pendiente (30 vs 90)
  ttl_retention_days = 30

  aplicacion          = "centrallog"
  propietario_recurso = "transversales-devops"
  producto            = "auditoria-transaccional"
  centro_costo        = "TI-INFRA"
}
```

Producción, con capacidad aprovisionada:

```hcl
  billing_mode       = "PROVISIONED"
  write_capacity     = 200    # ~118 WCU/s sostenidos + margen (§8.1)
  write_capacity_max = 1500
  read_capacity      = 25
  read_capacity_max  = 1000
```

---

## Validación

```powershell
cd modules/database/dynamodb
terraform init -backend=false
terraform validate
terraform fmt -check -recursive
```

---

## Referencias

| Documento | Contenido |
|-----------|-----------|
| `CL-LLD-DAT-01` §5 | Diseño de las 5 tablas: claves, atributos, índices |
| `CL-LLD-DAT-01` §7 | Ciclo de vida, TTL y Streams |
| `CL-LLD-DAT-01` §8 | Dimensionamiento de capacidad, costos y alarmas recomendadas |
| `CL-LLD-DAT-01` §9 | Seguridad, PII, control de acceso e inmutabilidad |
| `CL-LLD-DAT-01` §10 | Divergencias con el Terraform anterior y corrección aplicada |
| `CL-LLD-DAT-01` §12.2 | Decisiones abiertas |
| `CL-LLD-DAT-02` | OpenSearch: decisión de no construirlo |
| `CL-LLD-DAT-03` | Archivo analítico en S3 (Parquet + Athena) |
| `CL-LLD-ARQ-03` | Mensajería: la cola de espera es SQS estándar, no FIFO |
