#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ACCOUNT="$(terraform -chdir="$ROOT/infra/azure" output -raw storage_account)"
az storage blob upload-batch --account-name "$ACCOUNT" --auth-mode login \
  --destination landing --destination-path retail --source "$ROOT/data/sample" \
  --pattern '*.csv' --overwrite true --only-show-errors
