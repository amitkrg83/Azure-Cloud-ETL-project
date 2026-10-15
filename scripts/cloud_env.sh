#!/usr/bin/env bash
# Source after the Azure stack is applied; no secrets are written to disk.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export TF_VAR_host="$(terraform -chdir="$ROOT/infra/azure" output -raw databricks_host)"
export TF_VAR_workspace_resource_id="$(terraform -chdir="$ROOT/infra/azure" output -raw workspace_resource_id)"
export TF_VAR_access_connector_id="$(terraform -chdir="$ROOT/infra/azure" output -raw access_connector_id)"
export TF_VAR_storage_account="$(terraform -chdir="$ROOT/infra/azure" output -raw storage_account)"
ADF_OBJECT_ID="$(terraform -chdir="$ROOT/infra/azure" output -raw adf_principal_id)"
# This Graph lookup needs directory read permission. A tenant admin can provide
# TF_VAR_adf_application_id directly if Graph is restricted.
if [[ -z "${TF_VAR_adf_application_id:-}" ]]; then
  export TF_VAR_adf_application_id="$(az ad sp show --id "$ADF_OBJECT_ID" --query appId -o tsv)"
fi
[[ -n "$TF_VAR_adf_application_id" ]] || { echo "Missing ADF application/client ID"; return 1; }
