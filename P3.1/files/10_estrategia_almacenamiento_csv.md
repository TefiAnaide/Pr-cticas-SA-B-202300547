# Estrategia de almacenamiento de archivos CSV

## 1. Dónde se guarda el archivo

El CSV original (transferencias/pagos masivos) se sube directamente desde el cliente al
**Transaction Service**, el cual lo reenvía a **Cloud Storage** (bucket S3/GCS/Azure Blob según el
proveedor elegido) o a un **servidor FTP**, según lo definido en `01_arquitectura_general.mermaid`.
El archivo **no se guarda en la base de datos** del servicio: solo se persiste su referencia.

Convención de ruta en el bucket:

```
s3://banking-batches/{yyyy}/{mm}/{dd}/{batchId}.csv
```

Particionar por fecha evita un único "directorio" con millones de objetos y facilita políticas de
ciclo de vida (archivado/expiración) por antigüedad.

## 2. Qué se guarda en base de datos

`CSVFILE` (ver `03_diagramas_ER.mermaid`) guarda únicamente metadatos:

```
CSVFILE { id, bucketPath, rowCount, uploadedAt }
```

`BATCH.csvUrl` referencia ese archivo para poder ofrecer la **descarga desde el historial
consultable** (requisito explícito del enunciado: "el sistema debe mantener un historial consultable
... incluyendo su contenido y la opción de descarga"). La descarga se resuelve generando una URL
firmada (pre-signed URL) de corta duración hacia el bucket, en vez de que Transaction Service
reenvíe el archivo byte a byte.

## 3. Validación del contenido (antes de aceptar el lote)

El CSV se valida en dos niveles antes de generar `VALIDATION_RESULT` por transacción:

1. **Validación de formato**: número de columnas, tipos de dato, encoding, tamaño máximo de archivo
   y de fila — se rechaza el archivo completo si falla aquí (no se persiste en el bucket).
2. **Validación de reglas de negocio**, por cada fila/transacción del lote:
   - Saldo disponible en la cuenta origen.
   - Límites de transacción (monto máximo por operación y por lote).
   - Cuentas de origen/destino válidas (formato y existencia).
   - Reglas de prevención de fraude (montos atípicos, cuentas en lista de vigilancia, duplicados).

Cada regla evaluada por transacción genera un `VALIDATION_RESULT { rule, passed, detail }`. Si
**alguna fila** falla una regla obligatoria, la transacción queda `status=REJECTED` pero el resto
del lote puede continuar (rechazo a nivel de fila, no de archivo completo) — el Maker ve el detalle
exacto de qué filas fallaron y por qué antes de que el lote pase a `PENDING_CHECKER`.

## 4. Por qué no se guarda el CSV en la base de datos relacional

- **Tamaño**: lotes masivos (pagos de planilla, fin de mes) pueden pesar varios MB/decenas de miles
  de filas; guardarlos como `BYTEA`/`BLOB` degradaría el rendimiento de la base de datos del
  Transaction Service, que además debe soportar alta demanda transaccional.
- **Costo y escalabilidad**: el almacenamiento de objetos (S3/GCP/Azure) está optimizado y es más
  barato para archivos binarios que un disco de base de datos gestionado.
- **Separación de responsabilidades**: la base de datos del microservicio guarda el *estado
  transaccional* (lotes, transacciones, resultados de validación); el bucket guarda el *artefacto
  original* como evidencia inmutable para auditoría.

## 5. Retención y auditoría

El archivo original se conserva sin modificar (write-once) el tiempo que exijan las políticas de
auditoría bancaria de la institución; cualquier acceso de lectura al bucket (incluida la descarga
desde el historial) queda registrado por **Logging Service** con `traceId`, `batchId` y el usuario
que solicitó la descarga.
