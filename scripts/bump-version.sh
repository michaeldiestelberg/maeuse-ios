#!/usr/bin/env bash
set -euo pipefail

PROJECT_FILE="${PROJECT_FILE:-Maeuse.xcodeproj/project.pbxproj}"
INFO_PLIST="${INFO_PLIST:-Maeuse/Info.plist}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/bump-version.sh patch
  scripts/bump-version.sh minor
  scripts/bump-version.sh major
  scripts/bump-version.sh build

Rules:
  patch: 1.0.0 -> 1.0.1 and increments the build number
  minor: 1.0.0 -> 1.1.0 and increments the build number
  major: 1.0.0 -> 2.0.0 and increments the build number
  build: keeps the marketing version and increments only the build number
USAGE
}

bump="${1:-}"
case "$bump" in
  patch|minor|major|build)
    ;;
  -h|--help|help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 64
    ;;
esac

if [[ ! -f "$PROJECT_FILE" ]]; then
  echo "Project file not found: $PROJECT_FILE" >&2
  exit 66
fi

if [[ ! -f "$INFO_PLIST" ]]; then
  echo "Info.plist not found: $INFO_PLIST" >&2
  exit 66
fi

current_version="$(
  perl -ne 'if (/MARKETING_VERSION = "?([^";]+)"?;/) { print $1; exit }' "$PROJECT_FILE"
)"
current_build="$(
  perl -ne 'if (/CURRENT_PROJECT_VERSION = "?([^";]+)"?;/) { print $1; exit }' "$PROJECT_FILE"
)"

if [[ ! "$current_version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  echo "Expected MARKETING_VERSION to use Major.Minor.Patch, got: $current_version" >&2
  exit 65
fi

if [[ ! "$current_build" =~ ^[0-9]+$ ]]; then
  echo "Expected CURRENT_PROJECT_VERSION to be an integer, got: $current_build" >&2
  exit 65
fi

IFS=. read -r major minor patch <<< "$current_version"
case "$bump" in
  patch)
    patch=$((patch + 1))
    ;;
  minor)
    minor=$((minor + 1))
    patch=0
    ;;
  major)
    major=$((major + 1))
    minor=0
    patch=0
    ;;
  build)
    ;;
esac

new_version="$major.$minor.$patch"
new_build=$((current_build + 1))

NEW_VERSION="$new_version" NEW_BUILD="$new_build" perl -0pi -e '
  s/MARKETING_VERSION = "?[^";]+"?;/MARKETING_VERSION = $ENV{NEW_VERSION};/g;
  s/CURRENT_PROJECT_VERSION = "?[^";]+"?;/CURRENT_PROJECT_VERSION = $ENV{NEW_BUILD};/g;
' "$PROJECT_FILE"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString \$(MARKETING_VERSION)" "$INFO_PLIST" >/dev/null
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion \$(CURRENT_PROJECT_VERSION)" "$INFO_PLIST" >/dev/null

echo "Version: $current_version -> $new_version"
echo "Build:   $current_build -> $new_build"
