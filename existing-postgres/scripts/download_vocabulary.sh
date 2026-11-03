#!/bin/bash
# Downloads the vocabulary zip at VOCAB_URL and extracts its CSVs into VOCAB_DIR,
# ready for `make load-vocab`. An alternative to the manual Athena download for a
# vocabulary package you are allowed to use.
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

[[ -n "${VOCAB_URL:-}" ]] || die "set VOCAB_URL in .env first."
# In docker mode VOCAB_DIR is a path inside the Postgres container; this script writes
# on this machine, into the folder you mount there.
[[ "$PSQL_MODE" == "host" ]] \
  || die "download-vocab writes to VOCAB_DIR on this machine, which is only the CSV location in PSQL_MODE=host. In docker mode, download into the folder you mount into the container and set VOCAB_DIR to the mount."
for tool in curl unzip; do
  command -v "$tool" >/dev/null 2>&1 || die "download-vocab needs ${tool}."
done

mkdir -p "$VOCAB_DIR"
zip="${VOCAB_DIR}/vocabulary.zip"
# Not echoing the URL itself: download links can carry a token.
say "downloading VOCAB_URL -> ${zip}"
curl -fL --retry 3 -o "${zip}.part" "$VOCAB_URL"
mv "${zip}.part" "$zip"

# -j: load_vocabulary.sh expects the CSVs directly in VOCAB_DIR, not in a subfolder.
say "extracting the CSVs into ${VOCAB_DIR}"
unzip -j -o -q "$zip" '*.csv' -d "$VOCAB_DIR"
rm -f "$zip"

[[ -f "${VOCAB_DIR}/CONCEPT.csv" ]] || die "the zip contains no CONCEPT.csv."
say "done — next: make load-vocab"
