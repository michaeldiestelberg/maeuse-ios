#!/bin/bash
set -euo pipefail

# Requires macOS 26+, Xcode 26+, and a downloaded Apple Intelligence model.
# Runs the actual interpreter and expense models; no audio or network API usage.
cd "$(dirname "$0")/.."
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/maeuse-apple-check.XXXXXX")"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
xcrun swiftc -parse-as-library -module-cache-path "$check_dir/module-cache" \
  Maeuse/Services/AppleExpenseInterpreter.swift \
  Maeuse/Models/Expense.swift Maeuse/Models/VoiceWorkspace.swift \
  scripts/check-apple-model.swift -o "$check_dir/check-apple-model"
"$check_dir/check-apple-model"
