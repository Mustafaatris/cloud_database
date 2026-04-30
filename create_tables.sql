


SET FOREIGN_KEY_CHECKS = 0;

-- =============================================================================
-- MODULE 1: USERS
-- Purpose: Authentication, roles, and future access control
-- Notes: Auth is optional in MVP; table is future-ready for JWT / session auth
-- =============================================================================
CREATE TABLE IF NOT EXISTS users (
    id              INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    username        VARCHAR(80)  NOT NULL UNIQUE,
    email           VARCHAR(255) NOT NULL UNIQUE,
    password_hash   VARCHAR(255) NOT NULL,                          -- bcrypt / argon2 hash; NEVER store plaintext
    role            ENUM('admin', 'reviewer', 'user') NOT NULL DEFAULT 'user',
    is_active       TINYINT(1)  NOT NULL DEFAULT 1,                 -- soft-disable without deleting account
    last_login_at   DATETIME    NULL,                               -- optional; track session activity
    created_at      DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    INDEX idx_users_email  (email),
    INDEX idx_users_role   (role)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='User accounts; auth is optional in MVP but schema is fully ready';


-- =============================================================================
-- MODULE 2: DOCUMENTS
-- Purpose: Track every uploaded invoice/receipt file
-- Notes: Supports JPG, PNG, PDF; stores both local and cloud (S3) paths
--        checksum_sha256 prevents duplicate uploads and detects corruption
-- =============================================================================
CREATE TABLE IF NOT EXISTS documents (
    id                  INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id             INT UNSIGNED NOT NULL,                      -- FK → users.id
    file_name           VARCHAR(255) NOT NULL,                      -- original filename as uploaded
    original_file_path  VARCHAR(512) NULL,                         -- local/temp path during processing
    cloud_storage_path  VARCHAR(512) NULL,                         -- S3 key or full URL (e.g. s3://bucket/path)
    file_type           ENUM('jpg', 'jpeg', 'png', 'pdf') NOT NULL,
    file_size_bytes     BIGINT UNSIGNED NULL,                       -- file size in bytes
    checksum_sha256     VARCHAR(64)  NULL,                         -- SHA-256 of raw file; used for dedup & integrity
    upload_status       ENUM('pending', 'uploaded', 'failed', 'duplicate', 'unsupported') NOT NULL DEFAULT 'pending',
    is_deleted          TINYINT(1)  NOT NULL DEFAULT 0,             -- soft-delete flag; never hard-delete production data
    uploaded_at         DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT fk_documents_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE RESTRICT ON UPDATE CASCADE,

    INDEX idx_documents_user_id     (user_id),
    INDEX idx_documents_status      (upload_status),
    INDEX idx_documents_uploaded_at (uploaded_at),
    INDEX idx_documents_checksum    (checksum_sha256)   -- fast duplicate detection
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='One row per uploaded document; S3 path stored flexibly for future RDS migration';


-- =============================================================================
-- MODULE 3: OCR RESULTS
-- Purpose: Store raw OCR output separate from NLP extraction
-- Notes: bounding_boxes_json holds the spatial layout from Tesseract/similar
--        schema_version allows safe evolution of the JSON structure
-- =============================================================================
CREATE TABLE IF NOT EXISTS ocr_results (
    id                  INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    document_id         INT UNSIGNED NOT NULL UNIQUE,               -- 1-to-1 with documents; UNIQUE enforces this
    raw_text            LONGTEXT     NULL,                          -- full extracted text blob
    bounding_boxes_json JSON         NULL,                         -- word-level boxes: [{word, x, y, w, h, conf}]
    confidence_score    DECIMAL(5,2) NULL,                         -- overall OCR confidence 0.00–100.00
    ocr_engine          VARCHAR(80)  NULL DEFAULT 'tesseract',      -- e.g. 'tesseract', 'easyocr', 'aws-textract'
    ocr_engine_version  VARCHAR(20)  NULL,                         -- engine version for reproducibility
    processing_time_ms  INT UNSIGNED NULL,                         -- wall-clock milliseconds
    schema_version      SMALLINT     NOT NULL DEFAULT 1,           -- bump when bounding_boxes_json shape changes
    created_at          DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_ocr_document FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE CASCADE ON UPDATE CASCADE,

    INDEX idx_ocr_document_id (document_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Raw OCR output per document; JSON column insulates backend from schema changes';


-- =============================================================================
-- MODULE 4: EXTRACTED FIELDS
-- Purpose: Structured NLP output for the 4 key invoice fields
-- Notes: extraction_version tracks model/LoRA version used
--        All field values are nullable because any single field may be absent
--        in a real invoice; do NOT default to empty string
-- =============================================================================
CREATE TABLE IF NOT EXISTS extracted_fields (
    id                      INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    document_id             INT UNSIGNED NOT NULL,
    company_name            VARCHAR(255) NULL,
    invoice_date            DATE         NULL,                      -- parsed to DATE for reliable range queries
    invoice_date_raw        VARCHAR(80)  NULL,                     -- original string before parsing (e.g. "Jan 3, 2025")
    address                 TEXT         NULL,
    total_amount            DECIMAL(12,2) NULL,                    -- numeric; use DECIMAL not FLOAT for money
    total_amount_currency   VARCHAR(10)  NULL DEFAULT 'USD',       -- ISO 4217 currency code
    extraction_confidence   DECIMAL(5,2) NULL,                    -- overall field-set confidence 0.00–100.00
    confidence_per_field_json JSON       NULL,                    -- {"company":0.95, "date":0.87, ...}
    extraction_model        VARCHAR(80)  NULL,                    -- model name e.g. 'layoutlm-v3'
    extraction_version      VARCHAR(20)  NULL,                    -- model/LoRA checkpoint version
    raw_model_output_json   JSON         NULL,                   -- full model JSON for debugging / reprocessing
    status                  ENUM('auto', 'reviewed', 'corrected') NOT NULL DEFAULT 'auto',
    created_at              DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at              DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT fk_extracted_document FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE CASCADE ON UPDATE CASCADE,

    INDEX idx_extracted_document_id  (document_id),
    INDEX idx_extracted_invoice_date (invoice_date),              -- range queries on date
    INDEX idx_extracted_company      (company_name(64)),          -- prefix index for search
    INDEX idx_extracted_status       (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='One row per extraction run; versioned so reprocessing creates a new row, not an overwrite';


-- =============================================================================
-- MODULE 5: REVIEW CORRECTIONS
-- Purpose: Full audit trail of every human correction to extracted fields
-- Notes: field_name is free text so new fields can be added without schema change
--        old_value / new_value stored as TEXT to handle any field type
-- =============================================================================
CREATE TABLE IF NOT EXISTS review_corrections (
    id                  INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    extracted_field_id  INT UNSIGNED NOT NULL,                     -- FK → extracted_fields.id
    reviewer_id         INT UNSIGNED NOT NULL,                     -- FK → users.id
    field_name          VARCHAR(80)  NOT NULL,                     -- e.g. 'company_name', 'total_amount'
    old_value           TEXT         NULL,                         -- value before correction (NULL if field was empty)
    new_value           TEXT         NULL,                         -- value after correction
    correction_reason   VARCHAR(512) NULL,                        -- optional free-text reason
    corrected_at        DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_correction_extracted FOREIGN KEY (extracted_field_id) REFERENCES extracted_fields(id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_correction_reviewer  FOREIGN KEY (reviewer_id)        REFERENCES users(id)            ON DELETE RESTRICT ON UPDATE CASCADE,

    INDEX idx_corrections_extracted_id (extracted_field_id),
    INDEX idx_corrections_reviewer_id  (reviewer_id),
    INDEX idx_corrections_field_name   (field_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Immutable audit log; corrections are inserted, never updated';


-- =============================================================================
-- MODULE 6: PROCESSING LOGS
-- Purpose: Lifecycle tracking for every processing stage of a document
-- Notes: One row per stage per attempt; failed stages get their own row
--        error_message captures stack trace or short reason for debugging
-- =============================================================================
CREATE TABLE IF NOT EXISTS processing_logs (
    id              INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    document_id     INT UNSIGNED NOT NULL,
    stage           ENUM('upload', 'ocr', 'extraction', 'validation', 'storage') NOT NULL,
    status          ENUM('started', 'success', 'failed', 'skipped') NOT NULL DEFAULT 'started',
    error_message   TEXT         NULL,                             -- exception message or short description
    error_code      VARCHAR(50)  NULL,                            -- optional machine-readable error code
    started_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at    DATETIME     NULL,                            -- NULL if still in progress or never completed

    CONSTRAINT fk_log_document FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE CASCADE ON UPDATE CASCADE,

    INDEX idx_log_document_id (document_id),
    INDEX idx_log_stage       (stage),
    INDEX idx_log_status      (status),
    INDEX idx_log_started_at  (started_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Append-only processing pipeline log; never update rows, always insert';


-- =============================================================================
-- MODULE 7: API INTEGRATION CONFIG
-- Purpose: Registry of backend/AI API contracts to mitigate integration risk
-- Notes: expected_input_schema and expected_output_schema store JSON Schema
--        objects so the backend can validate requests/responses programmatically
--        active_version lets you run multiple versions side-by-side during migration
-- =============================================================================
CREATE TABLE IF NOT EXISTS api_integration_config (
    id                      INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    service_name            VARCHAR(80)  NOT NULL,                 -- e.g. 'ocr-service', 'extraction-model'
    endpoint_name           VARCHAR(80)  NOT NULL,                 -- e.g. 'POST /extract', 'GET /health'
    base_url                VARCHAR(512) NULL,                    -- e.g. 'http://localhost:8000'
    active_version          VARCHAR(20)  NOT NULL DEFAULT 'v1',   -- current active version
    expected_input_schema   JSON         NULL,                    -- JSON Schema of request body
    expected_output_schema  JSON         NULL,                    -- JSON Schema of response body
    is_active               TINYINT(1)  NOT NULL DEFAULT 1,       -- disable without deleting
    notes                   TEXT         NULL,                    -- human notes, known quirks
    created_at              DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at              DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    UNIQUE KEY uq_api_service_endpoint (service_name, endpoint_name, active_version),

    INDEX idx_api_service_name   (service_name),
    INDEX idx_api_is_active      (is_active)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Living contract registry; update active_version when AI or backend API changes';


SET FOREIGN_KEY_CHECKS = 1;

