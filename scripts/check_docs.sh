#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"

# The release gate must work on a stock macOS Command Line Tools install.
# Prefer ripgrep when available, but retain the small subset of its interface
# used by our shell checks when a developer has not installed it yet.
if ! command -v rg >/dev/null 2>&1; then
  rg() {
    local -a flags files
    local recursive=0
    while (( $# > 0 )); do
      case "$1" in
        -q|-n|-o) flags+=("$1"); shift ;;
        *) break ;;
      esac
    done
    local pattern="$1"; shift
    files=("$@")
    (( ${#files[@]} > 0 )) && recursive=1
    if (( recursive )); then
      command grep -R -E "${flags[@]}" -- "$pattern" "${files[@]}"
    else
      command grep -E "${flags[@]}" -- "$pattern"
    fi
  }
fi

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

if rg -n 'v6\.12\.3|6\.15\.1' README.md README.en.md; then
  echo "README contains a known stale release version" >&2
  exit 1
fi

echo "Documentation consistency checks passed."
