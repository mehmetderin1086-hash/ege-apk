#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
review_dir="${1:-$PWD/build/academic-review}"
mkdir -p "$review_dir"
review_dir="$(cd "$review_dir" && pwd)"
flutter test --no-pub --concurrency=1 --reporter expanded \
  "--dart-define=BILGILI_REVIEW_DIR=$review_dir" tool/academic_review/review_test.dart
