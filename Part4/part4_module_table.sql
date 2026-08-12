

DROP TABLE IF EXISTS eda.source_fingerprint;

CREATE TABLE eda.source_fingerprint (
    source_id        INTEGER PRIMARY KEY REFERENCES eda.data_source_catalog(source_id),
    file_path        VARCHAR(400) NOT NULL,
    checksum_sha256  CHARACTER(64) NOT NULL,
    row_count        BIGINT,
    last_checked_at  TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

COMMENT ON TABLE eda.source_fingerprint IS
    'Change detection state for the data-driven pipeline module. Stores a '
    'content hash of each registered source file so the module can tell '
    'whether the unstructured source has changed since the last run.';


