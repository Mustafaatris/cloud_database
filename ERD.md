# Entity Relationship Diagram (ERD)
## Invoice / Document Intelligence System

---

## Tables Overview

| Table | Module | Primary Key | Foreign Keys |
|---|---|---|---|
| `users` | Auth | `id` | — |
| `documents` | Upload | `id` | `user_id → users.id` |
| `ocr_results` | OCR | `id` | `document_id → documents.id` |
| `extracted_fields` | NLP | `id` | `document_id → documents.id` |
| `review_corrections` | Review | `id` | `extracted_field_id → extracted_fields.id`, `reviewer_id → users.id` |
| `processing_logs` | Logging | `id` | `document_id → documents.id` |
| `api_integration_config` | Config | `id` | — |

---

## ASCII Relationship Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        INVOICE INTELLIGENCE SYSTEM                      │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────┐          ┌──────────────────┐
│    users    │          │  api_integration │
│─────────────│          │     _config      │
│ id (PK)     │          │──────────────────│
│ username    │          │ id (PK)          │
│ email       │          │ service_name     │
│ password_   │          │ endpoint_name    │
│   hash      │          │ base_url         │
│ role        │          │ active_version   │
│ is_active   │          │ input_schema JSON│
│ created_at  │          │ output_schema    │
│ updated_at  │          │   JSON           │
└──────┬──────┘          │ is_active        │
       │ 1               └──────────────────┘
       │ (owns)
       │ N
┌──────▼────────────────────┐
│         documents         │
│───────────────────────────│
│ id (PK)                   │
│ user_id (FK → users.id)   │
│ file_name                 │
│ original_file_path        │
│ cloud_storage_path (S3)   │
│ file_type                 │
│ file_size_bytes           │
│ checksum_sha256           │  ← duplicate detection
│ upload_status             │
│ is_deleted                │  ← soft-delete
│ uploaded_at               │
└──────┬────────────────────┘
       │ 1
       ├──────────────────────────────────────────┐
       │                                          │
       │ 1                                        │ 1
 ┌─────▼──────────────┐                   ┌──────▼──────────────┐
 │    ocr_results     │                   │   processing_logs   │
 │────────────────────│                   │─────────────────────│
 │ id (PK)            │                   │ id (PK)             │
 │ document_id (FK)   │ ← UNIQUE (1-to-1) │ document_id (FK)    │
 │ raw_text           │                   │ stage               │
 │ bounding_boxes     │                   │ status              │
 │   _json (JSON)     │                   │ error_message       │
 │ confidence_score   │                   │ started_at          │
 │ ocr_engine         │                   │ completed_at        │
 │ processing_time_ms │                   └─────────────────────┘
 │ schema_version     │                   (N rows per document,
 └────────────────────┘                    one per stage attempt)

       │ 1
       │ (has many extraction runs)
       │ N
┌──────▼─────────────────────────────┐
│          extracted_fields          │
│────────────────────────────────────│
│ id (PK)                            │
│ document_id (FK → documents.id)    │
│ company_name                       │
│ invoice_date (DATE)                │
│ invoice_date_raw                   │  ← original string
│ address (TEXT)                     │
│ total_amount (DECIMAL 12,2)        │
│ total_amount_currency              │
│ extraction_confidence              │
│ confidence_per_field_json (JSON)   │  ← per-field scores
│ extraction_model                   │
│ extraction_version                 │  ← LoRA checkpoint
│ raw_model_output_json (JSON)       │  ← full model output
│ status (auto/reviewed/corrected)   │
│ created_at                         │
│ updated_at                         │
└──────┬─────────────────────────────┘
       │ 1
       │ N
┌──────▼─────────────────────────────┐
│        review_corrections          │
│────────────────────────────────────│
│ id (PK)                            │
│ extracted_field_id (FK)            │
│ reviewer_id (FK → users.id)        │
│ field_name                         │  ← which field was corrected
│ old_value (TEXT)                   │
│ new_value (TEXT)                   │
│ correction_reason                  │
│ corrected_at                       │
└────────────────────────────────────┘
```

---

## Cardinality Summary

| Relationship | Type | Notes |
|---|---|---|
| users → documents | 1-to-N | One user uploads many documents |
| documents → ocr_results | 1-to-1 | Each document has exactly one OCR result |
| documents → extracted_fields | 1-to-N | Reprocessing creates new rows, not updates |
| documents → processing_logs | 1-to-N | One row per stage per run |
| extracted_fields → review_corrections | 1-to-N | Multiple corrections per field set |
| users → review_corrections | 1-to-N | Reviewer can correct many documents |
| api_integration_config | standalone | No FK; registry only |

---

## Key Design Decisions

### Why extracted_fields is 1-to-N with documents
Running LoRA fine-tuning on the same document twice should **not** overwrite the previous result. New extraction runs create a new row. The `status` column and `created_at` timestamp identify the latest authoritative version.

### Why JSON columns are used
`bounding_boxes_json`, `confidence_per_field_json`, and `raw_model_output_json` store data whose **shape may change** as the model or OCR engine is swapped. Storing them as JSON prevents schema migrations every time the AI team updates the output format — only `schema_version` needs to be bumped.

### Why review_corrections is append-only
The corrections table is an **audit log**. Rows are never updated or deleted. This ensures a complete history of who changed what and when, which is important for compliance and debugging model errors.

### Why checksum_sha256 exists on documents
The SHA-256 hash of the raw file allows:
1. **Duplicate detection** — same file uploaded twice returns `duplicate` status immediately.
2. **Integrity verification** — compare hash at download time against stored hash to detect corruption in S3.

---

## Future Extension Points

| Extension | How to add |
|---|---|
| Multi-page PDF support | Add `page_number` column to `ocr_results` and `extracted_fields` |
| Batch processing | Add `batch_id` FK to a new `batches` table on `documents` |
| Model versioning | Add `model_versions` table; FK from `extracted_fields.extraction_version` |
| Currency normalisation | Add `currencies` lookup table; FK from `total_amount_currency` |
| Export history | Add `exports` table with `document_id`, `format`, `exported_at` |
| Tagging / categorisation | Add `tags` + `document_tags` junction table |