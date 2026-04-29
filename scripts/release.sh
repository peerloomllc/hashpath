#!/usr/bin/env bash
# Local release script for HashPath (a single-file web app).
# Usage: ./scripts/release.sh [vX.Y.Z] [--skip-nostr] [--skip-github] [--retag]
#
# Detects APP_VERSION in hashpath.html, extracts the matching CHANGELOG entry,
# creates a git tag + GitHub release, then posts a Nostr announcement signed
# with SIGN_WITH (loaded from scripts/.env or the environment).
#
# Config: scripts/app.conf (APP_NAME, APP_TAGLINE, APP_WEBSITE, NOSTR_HASHTAGS)
# Secret: scripts/.env      (SIGN_WITH — Zapstore NSEC, gitignored)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_FILE="$REPO_ROOT/hashpath.html"

if [ -f "$SCRIPT_DIR/app.conf" ]; then
  set -a; source "$SCRIPT_DIR/app.conf"; set +a
fi
if [ -f "$SCRIPT_DIR/.env" ]; then
  set -a; source "$SCRIPT_DIR/.env"; set +a
fi

# ── Args ────────────────────────────────────────────────────────────────────
RELEASE_TAG=""
SKIP_NOSTR=false
SKIP_GITHUB=false
RETAG=false
for arg in "$@"; do
  case "$arg" in
    --skip-nostr)  SKIP_NOSTR=true ;;
    --skip-github) SKIP_GITHUB=true ;;
    --retag)       RETAG=true ;;
    v*)            RELEASE_TAG="$arg" ;;
    *) echo "Unknown arg: $arg"; exit 1 ;;
  esac
done

_confirm() {
  local prompt="${1:-Continue?}"
  local reply
  read -rp "    ${prompt} [y/N] " reply
  case "$reply" in
    [Yy]) return 0 ;;
    *) echo "Aborted."; exit 0 ;;
  esac
}

# ── Extract version from hashpath.html ──────────────────────────────────────
APP_VERSION=$(grep -oE "APP_VERSION = '[^']+'" "$APP_FILE" | head -1 | sed "s/APP_VERSION = '//; s/'//")
if [ -z "$APP_VERSION" ]; then
  echo "ERROR: Could not find APP_VERSION in $APP_FILE"; exit 1
fi
[ -z "$RELEASE_TAG" ] && RELEASE_TAG="v${APP_VERSION}"
echo "==> Releasing ${APP_NAME:-App} ${RELEASE_TAG} (APP_VERSION=${APP_VERSION})"

# ── Extract release notes from CHANGELOG entry ──────────────────────────────
RELEASE_NOTES=$(python3 - <<PY
import re
src = open("$APP_FILE").read()
m = re.search(r"const CHANGELOG = \[(.*?)\n\];", src, re.DOTALL)
if not m:
    raise SystemExit("Could not locate CHANGELOG block")
block = m.group(1)
entries = re.findall(r"\{\s*version:\s*'([^']+)',\s*items:\s*\[(.*?)\]\s*\}", block, re.DOTALL)
for ver, items_blob in entries:
    if ver == "$APP_VERSION":
        items = re.findall(r"'((?:[^'\\\\]|\\\\.)*)'", items_blob)
        items = [i.replace("\\\\'", "'").replace("\\\\\\\\", "\\\\") for i in items]
        for it in items:
            print(f"- {it}")
        break
else:
    raise SystemExit(f"No CHANGELOG entry for $APP_VERSION")
PY
)
echo ""
echo "Release notes for ${RELEASE_TAG}:"
printf '%s\n' "$RELEASE_NOTES" | sed 's/^/  /'
echo ""

# Write release notes to file for gh CLI and Nostr step
NOTES_FILE="$REPO_ROOT/release_notes.md"
printf '%s\n' "$RELEASE_NOTES" > "$NOTES_FILE"
trap 'rm -f "$NOTES_FILE"' EXIT

# ── Git tag ─────────────────────────────────────────────────────────────────
if git rev-parse -q --verify "refs/tags/${RELEASE_TAG}" >/dev/null; then
  if $RETAG; then
    echo "==> Deleting existing local tag ${RELEASE_TAG} (--retag)"
    git tag -d "$RELEASE_TAG"
  else
    echo "    Tag ${RELEASE_TAG} already exists locally. Use --retag to recreate."
  fi
fi

if ! git rev-parse -q --verify "refs/tags/${RELEASE_TAG}" >/dev/null; then
  _confirm "Create tag ${RELEASE_TAG} on $(git rev-parse --abbrev-ref HEAD) @ $(git rev-parse --short HEAD)?"
  git tag -a "$RELEASE_TAG" -m "${APP_NAME:-App} ${RELEASE_TAG}"
  git push origin "$RELEASE_TAG"
  echo "    Tag pushed."
fi

# ── GitHub release ──────────────────────────────────────────────────────────
if ! $SKIP_GITHUB; then
  if gh release view "$RELEASE_TAG" >/dev/null 2>&1; then
    echo "==> GitHub release ${RELEASE_TAG} already exists."
  else
    _confirm "Create GitHub release ${RELEASE_TAG}?"
    gh release create "$RELEASE_TAG" "$APP_FILE" \
      --title "${APP_NAME:-App} ${RELEASE_TAG}" \
      --notes-file "$NOTES_FILE"
    echo "    GitHub release created."
  fi
fi

# ── Nostr announcement ──────────────────────────────────────────────────────
if $SKIP_NOSTR; then
  echo "==> Skipping Nostr announcement (--skip-nostr)."
  exit 0
fi

if [ -z "${SIGN_WITH:-}" ]; then
  echo "==> Skipping Nostr: SIGN_WITH not set (add it to scripts/.env)."
  exit 0
fi

if ! command -v nak &>/dev/null; then
  echo "    nak not found — install from https://github.com/fiatjaf/nak/releases"
  exit 1
fi

echo ""
echo "==> Posting Nostr announcement..."

# Take first 3 bullets as the "What's new" summary
BULLETS=""
while IFS= read -r line; do
  [ -z "$line" ] && continue
  line=$(printf '%s' "$line" | sed 's/^- //')
  BULLETS="${BULLETS:+${BULLETS}$'\n'}• ${line}"
done < <(grep '^- ' "$NOTES_FILE" | head -3)

NOTE_CONTENT="${APP_NAME:-App} ${RELEASE_TAG} is out!"$'\n\n'"${APP_TAGLINE:-}"
[ -n "$BULLETS" ] && NOTE_CONTENT+=$'\n\n'"What's new:"$'\n'"${BULLETS}"
NOTE_CONTENT+=$'\n\n'"${APP_WEBSITE:-}"$'\n\n'"${NOSTR_HASHTAGS:-}"

NOSTR_RELAYS=(
  wss://relay.damus.io
  wss://nos.lol
  wss://relay.primal.net
  wss://relay.nostr.net
)

DRAFT=$(mktemp /tmp/hashpath-nostr-XXXXXX.txt)
printf '%s' "$NOTE_CONTENT" > "$DRAFT"
echo "    Opening note in vi for review..."
vi "$DRAFT"
NOTE_CONTENT=$(cat "$DRAFT"); rm -f "$DRAFT"

echo ""
echo "    Final content:"
printf '%s\n' "$NOTE_CONTENT" | sed 's/^/      /'
echo ""
echo "    Relays: ${NOSTR_RELAYS[*]}"
_confirm "Post to Nostr?"

if nak event --sec "$SIGN_WITH" -k 1 -c "$NOTE_CONTENT" \
    "${NOSTR_RELAYS[@]}"; then
  echo "    Nostr announcement posted."
else
  echo "    WARNING: Nostr publish failed (release is still complete)."
fi
