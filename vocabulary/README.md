# Vocabulary drop folder

Unzip the Athena vocabulary CSVs **directly into this folder** (no nested directory),
then run `make load-vocab`.

## Getting the files

The OMOP standardized vocabularies cannot be downloaded automatically — they are
licensed per-user and gated behind an OHDSI account.

1. Register / log in at <https://athena.ohdsi.org>
2. **Download** tab → select the vocabularies you need. A reasonable starting set:
   SNOMED, RxNorm, RxNorm Extension, LOINC, ICD10CM, ICD10, ATC, UCUM, Gender,
   Race, Ethnicity, Visit, plus any source vocabularies your ETL maps from.
3. Submit the request and wait for the email with the download link (minutes to hours).
4. Unzip here, so the layout is `vocabulary/CONCEPT.csv`, not `vocabulary/vocab_download/CONCEPT.csv`.

## Expected files

`load_vocabulary.sh` requires all nine, uppercase, `.csv`:

| File | Notes |
| --- | --- |
| `CONCEPT.csv` | The core table |
| `VOCABULARY.csv` | |
| `DOMAIN.csv` | |
| `CONCEPT_CLASS.csv` | |
| `RELATIONSHIP.csv` | |
| `CONCEPT_RELATIONSHIP.csv` | Large |
| `CONCEPT_SYNONYM.csv` | |
| `DRUG_STRENGTH.csv` | |
| `CONCEPT_ANCESTOR.csv` | Largest — tens of millions of rows |

If your download includes `CPT4.csv` reconstruction steps (`cpt.sh` / `cpt.bat`),
run those per Athena's instructions *before* `make load-vocab`.

## Notes

- Everything in this folder except this README is gitignored — the vocabulary is
  large and not ours to redistribute.
- The folder is mounted read-only into the container at `/vocabulary`.
- `make load-vocab` truncates the vocabulary tables first, so re-running replaces
  rather than duplicates. It never touches clinical tables.
