
SET FOREIGN_KEY_CHECKS = 0;

-- =============================================================================
-- USERS
-- Passwords below are bcrypt hashes of the literal strings shown in comments
-- NEVER commit real passwords; replace hashes before any production use
-- =============================================================================
INSERT INTO users (id, username, email, password_hash, role, is_active) VALUES
(1, 'admin_omar',    'omar@invoiceai.dev',    '$2b$12$examplehash_admin_placeholder',    'admin',    1),
(2, 'reviewer_menna','menna@invoiceai.dev',   '$2b$12$examplehash_reviewer_placeholder', 'reviewer', 1),
(3, 'user_habiba',   'habiba@invoiceai.dev',  '$2b$12$examplehash_user1_placeholder',    'user',     1),
(4, 'user_mariam',   'mariam@invoiceai.dev',  '$2b$12$examplehash_user2_placeholder',    'user',     1),
(5, 'user_rawan',    'rawan@invoiceai.dev',   '$2b$12$examplehash_user3_placeholder',    'user',     1);


-- =============================================================================
-- DOCUMENTS
-- Simulates a mix of successful, failed, and duplicate uploads
-- =============================================================================
INSERT INTO documents (id, user_id, file_name, original_file_path, cloud_storage_path, file_type, file_size_bytes, checksum_sha256, upload_status) VALUES
(1, 3, 'receipt_001.jpg', '/tmp/uploads/receipt_001.jpg',     's3://invoice-ai-bucket/docs/receipt_001.jpg',    'jpg',  245120, 'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2', 'uploaded'),
(2, 3, 'receipt_002.png', '/tmp/uploads/receipt_002.png',     's3://invoice-ai-bucket/docs/receipt_002.png',    'png',  318400, 'b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3', 'uploaded'),
(3, 4, 'invoice_003.pdf', '/tmp/uploads/invoice_003.pdf',     's3://invoice-ai-bucket/docs/invoice_003.pdf',    'pdf',  512000, 'c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4', 'uploaded'),
(4, 5, 'bad_file.txt',    '/tmp/uploads/bad_file.txt',        NULL,                                             'jpg',  1024,   NULL,                                                               'unsupported'),  -- wrong extension
(5, 3, 'receipt_001.jpg', '/tmp/uploads/receipt_001_dup.jpg', NULL,                                             'jpg',  245120, 'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2', 'duplicate'); -- same checksum as doc 1


-- =============================================================================
-- OCR RESULTS
-- Only successfully uploaded documents reach OCR
-- =============================================================================
INSERT INTO ocr_results (id, document_id, raw_text, bounding_boxes_json, confidence_score, ocr_engine, ocr_engine_version, processing_time_ms, schema_version) VALUES
(1, 1,
 'SUNSHINE MARKET\n123 Main Street, Cairo\nDate: 15/03/2025\nTotal: $42.50',
 '[{"word":"SUNSHINE","x":50,"y":20,"w":120,"h":18,"conf":97},{"word":"MARKET","x":175,"y":20,"w":90,"h":18,"conf":96},{"word":"123","x":50,"y":45,"w":30,"h":15,"conf":94},{"word":"Total:","x":50,"y":110,"w":55,"h":15,"conf":98},{"word":"$42.50","x":110,"y":110,"w":60,"h":15,"conf":99}]',
 95.20, 'tesseract', '5.3.0', 1340, 1),

(2, 2,
 'FRESH BAKES BAKERY\nNile Corniche, Giza\n2025-01-22\nAmount Due: EGP 180.00',
 '[{"word":"FRESH","x":30,"y":15,"w":70,"h":18,"conf":93},{"word":"BAKES","x":105,"y":15,"w":70,"h":18,"conf":92},{"word":"BAKERY","x":180,"y":15,"w":85,"h":18,"conf":91}]',
 91.75, 'tesseract', '5.3.0', 1820, 1),

(3, 3,
 'APEX SOLUTIONS LLC\n45 Tahrir Sq, Downtown Cairo\nInvoice Date: March 10, 2025\nTotal Amount: USD 2,400.00',
 '[{"word":"APEX","x":60,"y":25,"w":65,"h":20,"conf":98},{"word":"SOLUTIONS","x":130,"y":25,"w":110,"h":20,"conf":97}]',
 97.10, 'tesseract', '5.3.0', 2100, 1);


-- =============================================================================
-- EXTRACTED FIELDS
-- Reflects realistic NLP output with confidence scores
-- =============================================================================
INSERT INTO extracted_fields (id, document_id, company_name, invoice_date, invoice_date_raw, address, total_amount, total_amount_currency, extraction_confidence, confidence_per_field_json, extraction_model, extraction_version, status) VALUES
(1, 1,
 'SUNSHINE MARKET', '2025-03-15', '15/03/2025',
 '123 Main Street, Cairo', 42.50, 'USD',
 93.50,
 '{"company_name":0.97,"invoice_date":0.95,"address":0.90,"total_amount":0.92}',
 'layoutlm-v3', 'v1.0-lora-r8', 'auto'),

(2, 2,
 'FRESH BAKES BAKERY', '2025-01-22', '2025-01-22',
 'Nile Corniche, Giza', 180.00, 'EGP',
 88.25,
 '{"company_name":0.93,"invoice_date":0.95,"address":0.80,"total_amount":0.85}',
 'layoutlm-v3', 'v1.0-lora-r8', 'reviewed'),

(3, 3,
 'APEX SOLUTIONS LLC', '2025-03-10', 'March 10, 2025',
 '45 Tahrir Sq, Downtown Cairo', 2400.00, 'USD',
 96.80,
 '{"company_name":0.98,"invoice_date":0.97,"address":0.95,"total_amount":0.97}',
 'layoutlm-v3', 'v1.0-lora-r8', 'corrected');


-- =============================================================================
-- REVIEW CORRECTIONS
-- Audited corrections made by reviewers
-- =============================================================================
INSERT INTO review_corrections (extracted_field_id, reviewer_id, field_name, old_value, new_value, correction_reason) VALUES
(2, 2, 'address',       'Nile Corniche, Giza',    'Nile Corniche, Giza, Egypt',  'Address was missing country'),
(3, 1, 'company_name',  'APEX SOLUTION LLC',      'APEX SOLUTIONS LLC',          'Missing "S" — OCR misread'),
(3, 1, 'total_amount',  '2,400.00',               '2400.00',                     'Removed comma; backend expects plain decimal');


-- =============================================================================
-- PROCESSING LOGS
-- Full pipeline trace for each document
-- =============================================================================
INSERT INTO processing_logs (document_id, stage, status, error_message, started_at, completed_at) VALUES
-- Document 1: full success
(1, 'upload',     'success', NULL, '2025-03-20 10:00:00', '2025-03-20 10:00:02'),
(1, 'ocr',        'success', NULL, '2025-03-20 10:00:02', '2025-03-20 10:00:03'),
(1, 'extraction', 'success', NULL, '2025-03-20 10:00:03', '2025-03-20 10:00:05'),
(1, 'validation', 'success', NULL, '2025-03-20 10:00:05', '2025-03-20 10:00:05'),
(1, 'storage',    'success', NULL, '2025-03-20 10:00:05', '2025-03-20 10:00:06'),
-- Document 2: success
(2, 'upload',     'success', NULL, '2025-03-21 11:00:00', '2025-03-21 11:00:01'),
(2, 'ocr',        'success', NULL, '2025-03-21 11:00:01', '2025-03-21 11:00:03'),
(2, 'extraction', 'success', NULL, '2025-03-21 11:00:03', '2025-03-21 11:00:05'),
(2, 'validation', 'success', NULL, '2025-03-21 11:00:05', '2025-03-21 11:00:05'),
(2, 'storage',    'success', NULL, '2025-03-21 11:00:05', '2025-03-21 11:00:06'),
-- Document 3: success
(3, 'upload',     'success', NULL, '2025-03-22 09:00:00', '2025-03-22 09:00:01'),
(3, 'ocr',        'success', NULL, '2025-03-22 09:00:01', '2025-03-22 09:00:04'),
(3, 'extraction', 'success', NULL, '2025-03-22 09:00:04', '2025-03-22 09:00:07'),
(3, 'validation', 'success', NULL, '2025-03-22 09:00:07', '2025-03-22 09:00:07'),
(3, 'storage',    'success', NULL, '2025-03-22 09:00:07', '2025-03-22 09:00:08'),
-- Document 4: upload failed (unsupported type)
(4, 'upload', 'failed', 'File type .txt is not supported. Allowed: jpg, jpeg, png, pdf', '2025-03-23 14:00:00', '2025-03-23 14:00:00'),
-- Document 5: duplicate detected at upload
(5, 'upload', 'failed', 'Duplicate detected: SHA-256 matches document_id=1', '2025-03-23 15:00:00', '2025-03-23 15:00:00');


-- =============================================================================
-- API INTEGRATION CONFIG
-- Pre-populated contract registry for backend and AI services
-- =============================================================================
INSERT INTO api_integration_config (service_name, endpoint_name, base_url, active_version, expected_input_schema, expected_output_schema, is_active, notes) VALUES
('ocr-service', 'POST /ocr/extract', 'http://localhost:8001', 'v1',
 '{"type":"object","properties":{"document_id":{"type":"integer"},"file_path":{"type":"string"}},"required":["document_id","file_path"]}',
 '{"type":"object","properties":{"raw_text":{"type":"string"},"bounding_boxes":{"type":"array"},"confidence":{"type":"number"}},"required":["raw_text"]}',
 1, 'Tesseract wrapper; swap for AWS Textract by updating base_url and bumping active_version'),

('extraction-model', 'POST /extract', 'http://localhost:8000', 'v1',
 '{"type":"object","properties":{"document_id":{"type":"integer"},"raw_text":{"type":"string"},"bounding_boxes":{"type":"array"}},"required":["document_id","raw_text"]}',
 '{"type":"object","properties":{"company_name":{"type":"string"},"invoice_date":{"type":"string"},"address":{"type":"string"},"total_amount":{"type":"number"}},"required":["company_name","invoice_date","address","total_amount"]}',
 1, 'LoRA fine-tuned LayoutLM-v3; update active_version on each new checkpoint'),

('flask-backend', 'POST /documents/upload', 'http://localhost:5000', 'v1',
 '{"type":"object","properties":{"file":{"type":"string","format":"binary"},"user_id":{"type":"integer"}},"required":["file","user_id"]}',
 '{"type":"object","properties":{"document_id":{"type":"integer"},"status":{"type":"string"}},"required":["document_id","status"]}',
 1, 'Main upload endpoint; validates file type and size before S3 transfer'),

('flask-backend', 'GET /documents/search', 'http://localhost:5000', 'v1',
 '{"type":"object","properties":{"company_name":{"type":"string"},"date_from":{"type":"string","format":"date"},"date_to":{"type":"string","format":"date"},"total_min":{"type":"number"}}}',
 '{"type":"array","items":{"type":"object","properties":{"document_id":{"type":"integer"},"company_name":{"type":"string"},"invoice_date":{"type":"string"},"total_amount":{"type":"number"}}}}',
 1, 'Full-text + range search over extracted_fields; add pagination params in v2');


SET FOREIGN_KEY_CHECKS = 1;

-- =============================================================================
-- END OF SEED DATA
-- To apply: mysql -u <user> -p <database_name> < seed_data.sql
-- =============================================================================