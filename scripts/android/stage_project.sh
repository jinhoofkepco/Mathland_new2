#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: stage_project.sh <project-root> <empty-stage-directory>" >&2
  exit 2
fi

MATHLAND_STAGE_SOURCE="$(cd "$1" && pwd)"
MATHLAND_STAGE_DESTINATION="$2"
mkdir -p "$MATHLAND_STAGE_DESTINATION"
MATHLAND_STAGE_DESTINATION="$(cd "$MATHLAND_STAGE_DESTINATION" && pwd)"
if [ "$MATHLAND_STAGE_SOURCE" = "$MATHLAND_STAGE_DESTINATION" ]; then
  echo "Stage directory must differ from project root" >&2
  exit 1
fi

rsync -a \
  --exclude='.git' \
  --exclude='.github/' \
  --exclude='.godot/' \
  --exclude='node_modules/' \
  --exclude='package.json' \
  --exclude='package-lock.json' \
  --exclude='android/' \
  --exclude='tests/' \
  --exclude='docs/' \
  --exclude='reports/' \
  --exclude='coverage/' \
  --exclude='playwright-report/' \
  --exclude='test-results/' \
  --exclude='web/' \
  --exclude='supabase/' \
  --exclude='packages/' \
  --exclude='scripts/' \
  --exclude='tools/' \
  --exclude='dist/' \
  --exclude='assets/source/' \
  --exclude='.env' \
  --exclude='.env.*' \
  --exclude='*.keystore' \
  --exclude='*.jks' \
  --exclude='*.p12' \
  --exclude='.DS_Store' \
  "$MATHLAND_STAGE_SOURCE/" \
  "$MATHLAND_STAGE_DESTINATION/"
