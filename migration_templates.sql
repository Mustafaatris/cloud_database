-- =============================================================================
-- Invoice / Document Intelligence System
-- Migration Templates: migration_templates.sql
-- Purpose: Ready-to-copy ALTER TABLE patterns for the most likely future changes
--          Copy and customise; do NOT run this file directly as-is.
-- Convention: migrations/YYYY_MM_DD_NNN_description.sql
-- =============================================================================


-- =============================================================================
-- TEMPLATE 1 — Add a new nullable column to an existing table
-- Use case: Add a new extracted field (e.g. VAT number) without breaking anything
-- =============================================================================
-- ALTER TABLE extracted_fields
--     ADD COLUMN vat_number VARCHAR(50) NULL
--         COMMENT 'VAT registration number if present on invoice'
--     AFTER total_amount_currency;


-- =============================================================================
-- TEMPLATE 2 — Add a new ENUM value (e.g. new file type, new status)
-- ⚠ MySQL requires listing ALL existing values when modifying ENUM
-- =============================================================================
-- -- Example: add 'tiff' to documents.file_type
-- ALTER TABLE documents
--     MODIFY COLUMN file_type ENUM('jpg','jpeg','png','pdf','tiff') NOT NULL;

-- -- Example: add 'archived' to documents.upload_status
-- ALTER TABLE documents
--     MODIFY COLUMN upload_status ENUM('pending','uploaded','failed','duplicate','unsupported','archived') NOT NULL DEFAULT 'pending';


-- =============================================================================
-- TEMPLATE 3 — Add a new processing stage to processing_logs
-- Use case: New pipeline step (e.g. 'classification', 'export')
-- =============================================================================
-- ALTER TABLE processing_logs
--     MODIFY COLUMN stage ENUM('upload','ocr','extraction','validation','storage','classification','export') NOT NULL;


-- =============================================================================
-- TEMPLATE 4 — Create a new lookup / reference table (normalisation)
-- Use case: Centralise currency codes as a proper FK instead of free text
-- =============================================================================
-- CREATE TABLE IF NOT EXISTS currencies (
--     code        CHAR(3)      PRIMARY KEY COMMENT 'ISO 4217 e.g. USD, EGP',
--     name        VARCHAR(80)  NOT NULL,
--     symbol      VARCHAR(10)  NULL
-- ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
--
-- -- Then update extracted_fields to reference it:
-- ALTER TABLE extracted_fields
--     ADD CONSTRAINT fk_extracted_currency
--         FOREIGN KEY (total_amount_currency) REFERENCES currencies(code)
--         ON UPDATE CASCADE ON DELETE RESTRICT;


-- =============================================================================
-- TEMPLATE 5 — Add a new model/version tracking table
-- Use case: When multiple model checkpoints need formal versioning
-- =============================================================================
-- CREATE TABLE IF NOT EXISTS model_versions (
--     id              INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
--     model_name      VARCHAR(80)  NOT NULL,
--     version_tag     VARCHAR(20)  NOT NULL,
--     checkpoint_path VARCHAR(512) NULL COMMENT 'S3 key of adapter weights',
--     f1_overall      DECIMAL(5,4) NULL,
--     released_at     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
--     is_active       TINYINT(1)  NOT NULL DEFAULT 0,
--     notes           TEXT         NULL,
--     UNIQUE KEY uq_model_version (model_name, version_tag)
-- ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- =============================================================================
-- TEMPLATE 6 — Add a foreign key after table creation
-- Use case: Link extracted_fields to model_versions once that table exists
-- =============================================================================
-- ALTER TABLE extracted_fields
--     ADD COLUMN model_version_id INT UNSIGNED NULL,
--     ADD CONSTRAINT fk_extracted_model_version
--         FOREIGN KEY (model_version_id) REFERENCES model_versions(id)
--         ON DELETE SET NULL ON UPDATE CASCADE;


-- =============================================================================
-- TEMPLATE 7 — Rename a column (MySQL 8.0+)
-- Use case: Rename without data loss
-- =============================================================================
-- ALTER TABLE documents RENAME COLUMN original_file_path TO local_temp_path;


-- =============================================================================
-- TEMPLATE 8 — Add pagination-friendly composite index
-- Use case: GET /documents?page=N with cursor-based pagination
-- =============================================================================
-- CREATE INDEX idx_documents_cursor
--     ON documents(user_id, uploaded_at, id);


-- =============================================================================
-- TEMPLATE 9 — Soft-delete pattern (already used; reference for new tables)
-- =============================================================================
-- ALTER TABLE extracted_fields ADD COLUMN is_deleted TINYINT(1) NOT NULL DEFAULT 0;
-- CREATE INDEX idx_extracted_not_deleted ON extracted_fields(is_deleted, document_id);


-- =============================================================================
-- TEMPLATE 10 — Schema version tracking table
-- Use case: Track which migrations have been applied (Flyway / Liquibase style)
-- =============================================================================
-- CREATE TABLE IF NOT EXISTS schema_migrations (
--     version         VARCHAR(20)  PRIMARY KEY COMMENT 'e.g. 2025_03_20_001',
--     description     VARCHAR(255) NOT NULL,
--     applied_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
--     applied_by      VARCHAR(80)  NULL
-- ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================================================
-- END OF MIGRATION TEMPLATES
-- =============================================================================