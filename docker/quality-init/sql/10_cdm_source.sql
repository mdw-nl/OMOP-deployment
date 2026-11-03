-- DQD reads the CDM metadata from cdm_source, so make sure it has a row.
-- Expects -v cdm_schema=...  Leaves an existing row (e.g. from an ETL) alone.
--
-- The placeholder is marked by its cdm_holder and removed again once the ETL has
-- written its own row, so DQD does not keep reporting the placeholder name.
DELETE FROM :"cdm_schema".cdm_source
 WHERE cdm_holder = 'Placeholder (quality-init)'
   AND EXISTS (SELECT FROM :"cdm_schema".cdm_source
                WHERE cdm_holder IS DISTINCT FROM 'Placeholder (quality-init)');

INSERT INTO :"cdm_schema".cdm_source (
  cdm_source_name, cdm_source_abbreviation, cdm_holder, source_description,
  source_release_date, cdm_release_date, cdm_version, cdm_version_concept_id, vocabulary_version
)
SELECT 'OMOP CDM', 'OMOP', 'Placeholder (quality-init)',
       'Placeholder until the ETL writes its own row; removed on the next make quality-up',
       current_date, current_date, 'v5.4',
       -- OMOP CDM Version 5.4.0; 0 when the vocabulary lacks it, as the column has a FK to concept
       coalesce((SELECT concept_id FROM :"cdm_schema".concept WHERE concept_id = 756265), 0),
       coalesce((SELECT vocabulary_version FROM :"cdm_schema".vocabulary WHERE vocabulary_id = 'None'), 'unknown')
WHERE NOT EXISTS (SELECT FROM :"cdm_schema".cdm_source);
