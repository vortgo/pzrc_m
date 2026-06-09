#!/usr/bin/env bash
# Build a correctly-structured Steam Workshop staging tree for PZRC Mod.
#
# PZ scans a workshop item for mods at <item>/mods/<ModName>/mod.info. The repo
# root is the MOD folder (mod.info + common/ + 42/), NOT a workshop item — so
# uploading the repo root directly drops the mod at the item root and PZ never
# finds it. This script wraps the mod under build/workshop/mods/pzrc_m/ and
# copies only the files that belong in the published item (no .git, README,
# CONFIG_REVIEW, tools, vdf, etc.).
#
# Usage:  ./tools/build_workshop.sh
# Then:   steamcmd +login <user> +workshop_build_item <repo>/workshop_upload.vdf +quit
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
STAGE="$REPO/build/workshop"
MODDIR="$STAGE/mods/pzrc_m"

rm -rf "$STAGE"
mkdir -p "$MODDIR"

# --- The mod itself (everything PZ loads) -------------------------------
cp "$REPO/mod.info"   "$MODDIR/"
cp "$REPO/poster.png" "$MODDIR/"
cp -r "$REPO/common"  "$MODDIR/"
cp -r "$REPO/42"      "$MODDIR/"

# --- Workshop-item metadata (item root, not inside the mod) -------------
cp "$REPO/preview.png" "$STAGE/"
cp "$REPO/workshop.txt" "$STAGE/" 2>/dev/null || true

echo "Staged workshop tree at: $STAGE"
echo
find "$STAGE" -maxdepth 3 -mindepth 1 | sed "s#$STAGE#  .#"
echo
echo "mod.info version: $(grep -i modversion "$MODDIR/mod.info")"
echo
echo "Next: steamcmd +login <user> +workshop_build_item $REPO/workshop_upload.vdf +quit"
