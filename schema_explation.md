# Schema Explanation
## Invoice / Document Intelligence System

---

## Table-by-Table Reference

---

### 1. `users`

**Purpose:** Stores user accounts for authentication and role-based access.

**Key design choices:**
- `password_hash` must hold a bcrypt or argon2 hash — never a plaintext password.
- `role` uses ENUM (`admin`, `reviewer`, `user`). Admins manage the system; reviewers can correct extracted data; users can only upload and view.
- `is_active` provides soft-disable: set to `0` to block login without deleting the account or its history.
- Auth is **optional in MVP** — you can seed a single admin user and skip login until Sprint 2.

**Common queries:**
```sql
-- Verify login
SELECT id, password_hash, role FROM users WHERE email = ? AND is_active = 1;

-- List reviewers
SELECT id, username FROM users WHERE role IN ('admin', 'reviewer') AND is_active = 1;
```

---

### 2. `documents`

**Purpose:** Master record for every uploaded file. All other tables join back to this one.

**Key design choices:**
- `original_file_path` is the temporary local path during processing; `cloud_storage_path` is the permanent S3 key. Keeping them separate lets you update the S3 path without touching the temp path.
- `checksum_sha256` is a SHA-256 hex string. Compute it **before** uploading to S3. It enables instant duplicate rejection and integrity verification.
- `upload_status` drives the processing pipeline. Only `uploaded` documents proceed to OCR.
- `is_deleted = 1` soft-deletes a document. The backend **filters `is_deleted = 0`** by default on all queries.

**Common queries:**
```sql
-- Find duplicates before inserting
SELECT id FROM documents WHERE checksum_sha256 = ? AND is_deleted = 0 LIMIT 1;

-- List a user's uploaded documents newest first
SELECT id, file_name, upload_status, uploaded_at
FROM documents
WHERE user_id = ? AND is_deleted = 0
ORDER BY uploaded_at DESC
LIMIT 20 OFFSET 0;
```

---

### 3. `ocr_results`

**Purpose:** Stores the raw output of the OCR engine (Tesseract or equivalent).

**Key design choices:**
- `UNIQUE` constraint on `document_id` enforces the 1-to-1 relationship. A document is processed by OCR exactly once.
- `bounding_boxes_json` stores the spatial layout. Expected shape (schema v1):
  ```json
  [
    {"word": "SUNSHINE", "x": 50, "y": 20, "w": 120, "h": 18, "conf": 97},
    ...
  ]
  ```
- `schema_version` must be incremented whenever the shape of `bounding_boxes_json` changes. The backend reads `schema_version` first and selects the correct parser.
- `ocr_engine` and `ocr_engine_version` allow reproducibility — you know exactly which version produced which result.

**Common queries:**
```sql
-- Get OCR text for a document
SELECT raw_text, bounding_boxes_json, schema_version
FROM ocr_results
WHERE document_id = ?;
```

---

### 4. `extracted_fields`

**Purpose:** The structured NLP output — the 4 invoice fields the model extracts.

**Key design choices:**
- This is **1-to-N with documents** on purpose. If a document is reprocessed (e.g. after LoRA fine-tuning improves), a **new row** is inserted, not an update. The `created_at` timestamp identifies recency.
- `invoice_date` is stored as MySQL `DATE` for reliable range queries. `invoice_date_raw` preserves the original string for debugging.
- `total_amount` uses `DECIMAL(12,2)` — **never FLOAT or DOUBLE for money**. FLOAT introduces rounding errors.
- `confidence_per_field_json` stores per-field scores so the frontend can highlight low-confidence fields for reviewer attention:
  ```json
  {"company_name": 0.97, "invoice_date": 0.88, "address": 0.71, "total_amount": 0.95}
  ```
- `raw_model_output_json` stores the complete model output. This lets you reparse fields later without rerunning the model.
- `extraction_version` stores the LoRA checkpoint tag (e.g. `v1.0-lora-r8`) used.

**Common queries:**
```sql
-- Search by company name
SELECT ef.*, d.file_name, d.cloud_storage_path
FROM extracted_fields ef
JOIN documents d ON d.id = ef.document_id
WHERE ef.company_name LIKE 'APEX%'
  AND d.is_deleted = 0
ORDER BY ef.invoice_date DESC;

-- Find low-confidence extractions needing review
SELECT * FROM extracted_fields
WHERE extraction_confidence < 80.0 AND status = 'auto'
ORDER BY created_at ASC;
```

---

### 5. `review_corrections`

**Purpose:** Immutable audit log of every human correction to extracted data.

**Key design choices:**
- Rows are **never updated or deleted**. The table is append-only.
- `field_name` is a `VARCHAR` (not ENUM) so new fields can be tracked without a schema migration.
- `old_value` and `new_value` are `TEXT` to accommodate any field type as a string.
- The combination of `extracted_field_id`, `field_name`, and `corrected_at` gives a complete timeline of changes to any single field.

**Common queries:**
```sql
-- Get correction history for a document's extraction
SELECT rc.field_name, rc.old_value, rc.new_value, rc.correction_reason,
       u.username, rc.corrected_at
FROM review_corrections rc
JOIN users u ON u.id = rc.reviewer_id
WHERE rc.extracted_field_id = ?
ORDER BY rc.corrected_at ASC;
```

---

### 6. `processing_logs`

**Purpose:** Append-only pipeline trace. One row per stage per attempt.

**Stages:** `upload` → `ocr` → `extraction` → `validation` → `storage`

**Key design choices:**
- Rows are **never updated**. If a stage is retried, a new row is inserted.
- `completed_at` is `NULL` while a stage is in progress, allowing detection of hung processes:
  ```sql
  SELECT * FROM processing_logs
  WHERE status = 'started' AND started_at < NOW() - INTERVAL 5 MINUTE;
  ```
- `error_code` is a short machine-readable code (e.g. `OCR_LOW_CONFIDENCE`, `EXTRACTION_TIMEOUT`) for programmatic error handling in the backend.

**Common queries:**
```sql
-- Get full pipeline status for a document
SELECT stage, status, error_message, started_at, completed_at,
       TIMESTAMPDIFF(SECOND, started_at, completed_at) AS duration_sec
FROM processing_logs
WHERE document_id = ?
ORDER BY started_at ASC;

-- Count failures per stage today
SELECT stage, COUNT(*) AS failures
FROM processing_logs
WHERE status = 'failed' AND DATE(started_at) = CURDATE()
GROUP BY stage;
```

---

### 7. `api_integration_config`

**Purpose:** Living contract registry that reduces integration risk between the Flask backend, OCR service, and the LoRA extraction model.

**Key design choices:**
- `expected_input_schema` and `expected_output_schema` store **JSON Schema** objects. The backend can use a JSON Schema validator (e.g. Python `jsonschema` library) to validate requests and responses at runtime.
- `active_version` allows running multiple versions side-by-side during a migration. Set the old version to `is_active = 0` after cutover.
- When the AI team changes the JSON output format of `POST /extract`, the process is:
  1. Insert a new row with `active_version = 'v2'`.
  2. Update the Flask backend to read from the `v2` row.
  3. Set the `v1` row to `is_active = 0`.

**No FK from this table.** It is a configuration registry, not a transactional table.

---

## JSON Column Reference

| Table | Column | Purpose | Schema version |
|---|---|---|---|
| `ocr_results` | `bounding_boxes_json` | Word-level spatial boxes | `schema_version` column |
| `extracted_fields` | `confidence_per_field_json` | Per-field confidence scores | implicit |
| `extracted_fields` | `raw_model_output_json` | Full model response for debugging | implicit |
| `api_integration_config` | `expected_input_schema` | JSON Schema for request body | `active_version` column |
| `api_integration_config` | `expected_output_schema` | JSON Schema for response body | `active_version` column |

---

## ENUM Reference

| Table | Column | Values |
|---|---|---|
| `users` | `role` | `admin`, `reviewer`, `user` |
| `documents` | `file_type` | `jpg`, `jpeg`, `png`, `pdf` |
| `documents` | `upload_status` | `pending`, `uploaded`, `failed`, `duplicate`, `unsupported` |
| `extracted_fields` | `status` | `auto`, `reviewed`, `corrected` |
| `processing_logs` | `stage` | `upload`, `ocr`, `extraction`, `validation`, `storage` |
| `processing_logs` | `status` | `started`, `success`, `failed`, `skipped` |

> **Note:** When adding a new ENUM value, use `ALTER TABLE ... MODIFY COLUMN` and list **all** existing values plus the new one.

---

## Nullable vs NOT NULL Policy

| Rule | Rationale |
|---|---|
| Extracted field values (`company_name`, `invoice_date`, etc.) are `NULL`-able | A real invoice may genuinely be missing a field. `NULL` correctly signals absence; an empty string does not. |
| `cloud_storage_path` is `NULL`-able | Documents that fail upload never reach S3. |
| `completed_at` in `processing_logs` is `NULL`-able | `NULL` = stage still in progress. |
| `error_message` and `error_code` are `NULL`-able | Only populated on failure. |
| `last_login_at` in `users` is `NULL`-able | Never logged in yet is a valid state. |