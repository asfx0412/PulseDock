#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"

readmes=(README.md README.en.md)
for readme in "${readmes[@]}"; do
  test -s "$readme"
  if rg -n '当前版本：\*\*|Current version: \*\*|PulseDock-[0-9]+\.[0-9]+\.[0-9]+\.zip' "$readme"; then
    echo "$readme must link to the latest Release instead of hard-coding a version or ZIP name" >&2
    exit 1
  fi
  if ! rg -q 'releases/latest' "$readme"; then
    echo "$readme must link users to the latest GitHub Release" >&2
    exit 1
  fi
done

if ! rg -q 'github/v/release/asfx0412/PulseDock' README.md README.en.md; then
  echo "README version badges must be dynamic GitHub Release badges" >&2
  exit 1
fi

for document in docs/PRODUCT_MESSAGING.md docs/PROMOTION_COPY.md docs/DOCUMENTATION_POLICY.md; do
  test -s "$document" || { echo "Missing documentation: $document" >&2; exit 1; }
done

if rg -n 'v6\.12\.3|6\.15\.1' README.md README.en.md; then
  echo "README contains a known stale release version" >&2
  exit 1
fi

echo "Documentation consistency checks passed."
