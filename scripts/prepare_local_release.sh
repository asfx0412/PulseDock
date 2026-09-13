#!/bin/zsh
# Local release gate for PulseDock.  It is intentionally outside PulseDock.app:
# it uses the developer's existing GitHub CLI login and never stores a token or
# the update-signing private key.
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"

# `prepare_local_release.sh` is intended to run on a stock macOS developer
# machine too; use grep for the few ripgrep operations if it is absent.
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

usage() {
  print "Usage: scripts/prepare_local_release.sh <version> [--publish]"
  print "  <version>  Version from VERSION, e.g. 6.15.3"
  print "  --publish  Explicitly commit the verified working tree, push v<version>,"
  print "             wait for GitHub Actions, then verify the public Release."
}

[[ $# -ge 1 && $# -le 2 ]] || { usage >&2; exit 64; }
VERSION="$1"
PUBLISH="${2:-}"
[[ "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { print "Invalid release version: $VERSION" >&2; exit 64; }
[[ -z "$PUBLISH" || "$PUBLISH" == "--publish" ]] || { usage >&2; exit 64; }

[[ "$(tr -d '[:space:]' < VERSION)" == "$VERSION" ]] || { print "VERSION does not match $VERSION" >&2; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)" == "$VERSION" ]] || { print "Info.plist does not match $VERSION" >&2; exit 1; }
NOTES="outputs/PulseDock-${VERSION}发布说明.md"
REPORT="outputs/PulseDock-${VERSION}测试报告.md"
[[ -s "$NOTES" && -s "$REPORT" ]] || { print "Missing release notes or test report for $VERSION" >&2; exit 1; }

# A release is never prepared from an unexplained worktree. Ignored build
# outputs are OK and may be rebuilt. Pre-existing staged changes are refused,
# but ordinary new files and deliberate deletions are part of a release: they
# are collected into the displayed manifest and require the final confirmation.
[[ -z "$(git diff --cached --name-only)" ]] || { print "Staged changes found; unstage/review them before preparing a release." >&2; exit 1; }
typeset -aU CHANGED_FILES
while IFS= read -r -d $'\0' changed_path; do
  [[ -n "$changed_path" ]] && CHANGED_FILES+=("$changed_path")
done < <(git diff --name-only -z)
while IFS= read -r -d $'\0' untracked_path; do
  [[ -n "$untracked_path" ]] && CHANGED_FILES+=("$untracked_path")
done < <(git ls-files --others --exclude-standard -z)
(( ${#CHANGED_FILES} > 0 )) || { print "No version changes to prepare." >&2; exit 1; }

# These names commonly contain credentials. Keep the safety boundary even
# though this command can now publish reviewed new files in one operation.
for release_path in "${CHANGED_FILES[@]}"; do
  case "$release_path" in
    .env|.env.*|*.pem|*.key|*.p12|*.mobileprovision|*.secrets|*.credentials)
      print "Refusing potentially sensitive release path: $release_path" >&2; exit 1 ;;
  esac
done

release_diff_sha() {
  {
    git diff --binary --no-ext-diff --
    local new_path
    while IFS= read -r -d $'\0' new_path; do
      [[ -n "$new_path" ]] || continue
      git diff --no-index --binary -- /dev/null "$new_path" || [[ $? -eq 1 ]]
    done < <(git ls-files --others --exclude-standard -z)
  } | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}'
}

./scripts/test.sh
./scripts/build.sh
ZIP="outputs/PulseDock-${VERSION}.zip"
[[ -s "$ZIP" ]] || { print "Build did not create $ZIP" >&2; exit 1; }
ZIP_SHA="$(/usr/bin/shasum -a 256 "$ZIP" | /usr/bin/awk '{print $1}')"
DIFF_SHA="$(release_diff_sha)"
NOTES_SHA="$(/usr/bin/shasum -a 256 "$NOTES" | /usr/bin/awk '{print $1}')"
RECEIPT_DIR=".build"
RECEIPT="$RECEIPT_DIR/release-ready-${VERSION}.json"
mkdir -p "$RECEIPT_DIR"
FILES_JSON=$(/usr/bin/python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "${CHANGED_FILES[@]}")
/usr/bin/python3 - "$RECEIPT" "$VERSION" "$(git rev-parse HEAD)" "$ZIP_SHA" "$DIFF_SHA" "$NOTES_SHA" "$FILES_JSON" <<'PY'
import datetime, json, pathlib, sys
path, version, commit, zip_sha, diff_sha, notes_sha, files_json = sys.argv[1:]
payload = {
    "schema": 1, "version": version, "commit": commit,
    "preparedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "zipSHA256": zip_sha, "diffSHA256": diff_sha, "releaseNotesSHA256": notes_sha,
    "files": json.loads(files_json), "tests": ["scripts/test.sh", "scripts/build.sh"]
}
pathlib.Path(path).write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n")
PY
print "Local release receipt written: $RECEIPT"
print "ZIP SHA-256: $ZIP_SHA"
print "Files approved for this release: ${#CHANGED_FILES}"
print "Release manifest:"
printf '  %s\n' "${CHANGED_FILES[@]}"

[[ "$PUBLISH" == "--publish" ]] || exit 0
print -n "Publish PulseDock v${VERSION} from this exact receipt? Type ${VERSION}: "
read -r confirmation
[[ "$confirmation" == "$VERSION" ]] || { print "Publish cancelled." >&2; exit 1; }

command -v gh >/dev/null || { print "GitHub CLI (gh) is required for --publish." >&2; exit 1; }
# Clash Verge currently exposes its HTTP/mixed listener on 7897.  Do this only
# for publication so an obsolete shell-wide 7890 proxy cannot break git/gh.
GITHUB_PROXY="${PULSEDOCK_GITHUB_PROXY:-http://127.0.0.1:7897}"
export HTTP_PROXY="$GITHUB_PROXY"
export HTTPS_PROXY="$GITHUB_PROXY"
export http_proxy="$GITHUB_PROXY"
export https_proxy="$GITHUB_PROXY"
if ! gh auth status -h github.com >/dev/null 2>&1; then
  print "GitHub CLI 登录不可用。请先执行：scripts/github_login.sh" >&2
  exit 1
fi
REMOTE_URL="$(git remote get-url origin)"
[[ "$REMOTE_URL" == *"github.com/asfx0412/PulseDock"* ]] || { print "origin is not asfx0412/PulseDock: $REMOTE_URL" >&2; exit 1; }
[[ -z "$(git ls-remote --tags origin "refs/tags/v${VERSION}")" ]] || { print "Tag v${VERSION} already exists." >&2; exit 1; }
CURRENT_DIFF_SHA="$(release_diff_sha)"
[[ "$CURRENT_DIFF_SHA" == "$DIFF_SHA" ]] || { print "Working tree changed after local verification; prepare again." >&2; exit 1; }
git add -A -- "${CHANGED_FILES[@]}"
git commit -m "Release v${VERSION}"
git tag -a "v${VERSION}" -m "PulseDock v${VERSION}"
git push origin HEAD
git push origin "v${VERSION}"

# The signing private key exists only in GitHub Actions.  Wait for that trusted
# build, then verify the public result with the same public key shipped in App.
HEAD_SHA="$(git rev-parse HEAD)"
RUN_ID="$(gh run list --repo asfx0412/PulseDock --workflow release.yml --commit "$HEAD_SHA" --limit 1 --json databaseId --jq '.[0].databaseId')"
[[ -n "$RUN_ID" && "$RUN_ID" != "null" ]] || { print "Tag pushed; could not locate the Release workflow run." >&2; exit 1; }
gh run watch "$RUN_ID" --repo asfx0412/PulseDock --exit-status
VERIFY_DIR="$(mktemp -d /private/tmp/PulseDock-public-release.XXXXXX)"
trap 'rm -rf "$VERIFY_DIR"' EXIT
gh release download "v${VERSION}" --repo asfx0412/PulseDock --pattern 'PulseDock-*.zip' --pattern latest-macos-arm64.json --dir "$VERIFY_DIR"
PUBLIC_KEY="$(rg -o '[A-Za-z0-9+/]{43}=' Sources/PulseDock/Services/AppUpdateService.swift | head -1)"
swift scripts/verify_update_manifest.swift "$VERIFY_DIR/latest-macos-arm64.json" "$PUBLIC_KEY"
PUBLIC_ZIP_SHA="$(/usr/bin/shasum -a 256 "$VERIFY_DIR/PulseDock-${VERSION}.zip" | /usr/bin/awk '{print $1}')"
MANIFEST_SHA="$(/usr/bin/plutil -extract sha256 raw -o - "$VERIFY_DIR/latest-macos-arm64.json")"
[[ "$PUBLIC_ZIP_SHA" == "$MANIFEST_SHA" ]] || { print "Public ZIP SHA does not match manifest." >&2; exit 1; }
gh release view "v${VERSION}" --repo asfx0412/PulseDock --json url,tagName,publishedAt,assets > "$RECEIPT_DIR/release-result-${VERSION}.json"
print "Published and public artifacts verified: $RECEIPT_DIR/release-result-${VERSION}.json"
