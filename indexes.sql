-- =============================================================================


-- -----------------------------------------------------------------------------
-- DOCUMENTS — additional composite indexes for common query patterns
-- -----------------------------------------------------------------------------

-- Find all documents for a user filtered by status (dashboard view)
CREATE INDEX IF NOT EXISTS idx_documents_user_status
    ON documents(user_id, upload_status);

-- Date-range queries on uploaded_at for reporting
CREATE INDEX IF NOT EXISTS idx_documents_date_range
    ON documents(uploaded_at, upload_status);

-- Detect duplicates by checksum quickly
-- (already covered by idx_documents_checksum in create_tables.sql)


-- -----------------------------------------------------------------------------
-- EXTRACTED FIELDS — search and filter patterns
-- -----------------------------------------------------------------------------

-- Search by company name prefix (used by GET /documents/search)
-- Prefix index on VARCHAR; length 64 is a good balance
CREATE INDEX IF NOT EXISTS idx_extracted_company_prefix
    ON extracted_fields(company_name(64));

-- Date range queries on invoice_date
-- (already covered by idx_extracted_invoice_date in create_tables.sql)

-- Total amount range queries (e.g. invoices > $1000)
CREATE INDEX IF NOT EXISTS idx_extracted_total
    ON extracted_fields(total_amount);

-- Composite: document_id + status (check if a document already has a reviewed result)
CREATE INDEX IF NOT EXISTS idx_extracted_doc_status
    ON extracted_fields(document_id, status);


-- -----------------------------------------------------------------------------
-- OCR RESULTS
-- -----------------------------------------------------------------------------

-- Look up OCR result by document quickly (1-to-1 but still useful for joins)
-- (already covered by UNIQUE KEY on document_id in create_tables.sql)


-- -----------------------------------------------------------------------------
-- PROCESSING LOGS — operational monitoring queries
-- -----------------------------------------------------------------------------

-- Find all failed stages today (monitoring dashboard)
CREATE INDEX IF NOT EXISTS idx_log_status_started
    ON processing_logs(status, started_at);

-- Find the latest log entry per document per stage (pipeline status page)
CREATE INDEX IF NOT EXISTS idx_log_doc_stage_started
    ON processing_logs(document_id, stage, started_at);


-- -----------------------------------------------------------------------------
-- REVIEW CORRECTIONS — audit trail queries
-- -----------------------------------------------------------------------------

-- All corrections by a specific reviewer
CREATE INDEX IF NOT EXISTS idx_corrections_reviewer_date
    ON review_corrections(reviewer_id, corrected_at);

-- All corrections on a specific field name across all documents
CREATE INDEX IF NOT EXISTS idx_corrections_field_date
    ON review_corrections(field_name, corrected_at);


-- -----------------------------------------------------------------------------
-- USERS — login and role lookups
-- -----------------------------------------------------------------------------

-- Login lookup (email is already UNIQUE; this makes role queries fast)
CREATE INDEX IF NOT EXISTS idx_users_role_active
    ON users(role, is_active);


-- =============================================================================
-- FULL-TEXT INDEX (optional — enable if MySQL 5.7+ full-text search is used)
-- Enables: SELECT * FROM extracted_fields WHERE MATCH(company_name, address) AGAINST('cairo')
-- =============================================================================
-- ALTER TABLE extracted_fields ADD FULLTEXT INDEX ft_extracted_text(company_name, address);
-- ALTER TABLE ocr_results ADD FULLTEXT INDEX ft_ocr_raw_text(raw_text);

-- =============================================================================
-- END OF INDEXES
-- To apply: mysql -u <user> -p <database_name> < indexes.sql
-- =============================================================================