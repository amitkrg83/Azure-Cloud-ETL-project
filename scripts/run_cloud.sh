#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RG="$(terraform -chdir="$ROOT/infra/azure" output -raw resource_group)"
FACTORY="$(terraform -chdir="$ROOT/infra/azure" output -raw adf_name)"
PIPELINE="$(terraform -chdir="$ROOT/infra/azure" output -raw pipeline_name)"
az extension add --name datafactory --upgrade --only-show-errors
RUN_ID="$(az datafactory pipeline create-run -g "$RG" --factory-name "$FACTORY" \
  --name "$PIPELINE" --query runId -o tsv)"
echo "ADF run: $RUN_ID"
for ((attempt=0; attempt<120; attempt++)); do
  STATUS="$(az datafactory pipeline-run show -g "$RG" --factory-name "$FACTORY" \
    --run-id "$RUN_ID" --query status -o tsv)"
  echo "$STATUS"
  case "$STATUS" in
    Succeeded) exit 0 ;;
    Failed|Cancelled) az datafactory pipeline-run show -g "$RG" --factory-name "$FACTORY" --run-id "$RUN_ID"; exit 1 ;;
  esac
  sleep 15
done
echo "Polling timed out after 30 minutes; pipeline may still be running. Inspect ADF Monitor."
exit 1
