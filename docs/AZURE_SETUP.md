# Deploy the Azure demo

## Prerequisites and permission boundary

Install Terraform 1.9+, Azure CLI, Git and Python. Sign in with `az login`.
Use a dedicated demo subscription/resource group, not an employer's subscription.
Azure provisioning creates billable resources; inspect every plan before applying.

The deployment identity needs subscription Contributor plus Role Based Access Control Administrator
(or Owner) to create role assignments. It also needs Storage Blob Data Contributor on the backend
container/account. The stack grants it data access on the new demo lake; Azure role propagation can
require waiting a few minutes and reapplying after a 403.

**Unity Catalog is a prerequisite, not automatically bootstrapped by this project.**
An account admin must attach a regional Unity Catalog metastore to the workspace if one is not
automatically attached. Select an existing catalog accessible from this workspace. New Azure
workspaces may have a workspace-named catalog rather than `main`.

The identity applying the Databricks stack must be a workspace admin and have permission to
CREATE STORAGE CREDENTIAL and CREATE EXTERNAL LOCATION on the metastore, USE_CATALOG and
CREATE SCHEMA on the chosen catalog, plus authority to grant privileges there. An account/metastore
admin can grant these. Azure Owner by itself does not grant Unity Catalog privileges.
For CI, explicitly add the OIDC app's service principal to the workspace and grant these permissions.

The regional SKU `Standard_D4ds_v5` and Databricks runtime `15.4.x-scala2.12` are configurable defaults.
Check runtime support, workspace policies and regional vCPU quota before running; one driver plus
one worker uses two VMs. The notebook activity starts a job cluster, which ends after the run.
Public service endpoints are used for learning; storage containers remain private and require identities.

## 1. Sign in and select a subscription

Run all commands from the repository root in Bash:

```bash
az login
az account set --subscription '<your-subscription-id>'
export TF_VAR_subscription_id="$(az account show --query id -o tsv)"
export ARM_SUBSCRIPTION_ID="$TF_VAR_subscription_id"
export ARM_USE_AZUREAD=true
export TF_VAR_catalog=main  # Change to your actual Unity Catalog catalog.
export TF_VAR_schema=etl_demo
```

Register providers if your subscription has not used them:
```bash
az provider register --namespace Microsoft.Storage
az provider register --namespace Microsoft.Databricks
az provider register --namespace Microsoft.DataFactory
az provider register --namespace Microsoft.OperationalInsights
az provider register --namespace Microsoft.Insights
```
Wait until each provider reports Registered (`az provider show --namespace NAME --query registrationState`).

## 2. Bootstrap remote Terraform state (one time)

Use a globally unique lowercase account name, maximum 24 characters. Keep this account separate
from the demo resource group so teardown does not erase Terraform state.

```bash
export STATE_RG=rg-etl-tfstate
export STATE_ACCOUNT='<globally-unique-state-account>'
export LOCATION=eastus2
az group create --name "$STATE_RG" --location "$LOCATION"
az storage account create --name "$STATE_ACCOUNT" --resource-group "$STATE_RG" \
  --location "$LOCATION" --sku Standard_LRS --min-tls-version TLS1_2 \
  --allow-shared-key-access false --allow-blob-public-access false
STATE_ID="$(az storage account show -g "$STATE_RG" -n "$STATE_ACCOUNT" --query id -o tsv)"
# Interactive user. For CI, substitute the app service principal OBJECT ID.
DEPLOYER_OBJECT_ID="$(az ad signed-in-user show --query id -o tsv)"
az role assignment create --assignee-object-id "$DEPLOYER_OBJECT_ID" \
  --assignee-principal-type User --role 'Storage Blob Data Contributor' --scope "$STATE_ID"
# After role propagation, create the private state container.
az storage container create --account-name "$STATE_ACCOUNT" --name tfstate --auth-mode login
az storage account blob-service-properties update --account-name "$STATE_ACCOUNT" \
  --resource-group "$STATE_RG" --enable-versioning true
```

For CI grant its service principal Storage Blob Data Contributor on this same backend.
Backend authentication uses your Azure CLI identity/Entra tokens; there are no access keys.
State is sensitive configuration: restrict account access, preserve version history, and keep it out of Git.

## 3. Plan and create Azure resources

```bash
terraform -chdir=infra/azure init \
  -backend-config="resource_group_name=$STATE_RG" \
  -backend-config="storage_account_name=$STATE_ACCOUNT" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=retail-azure.tfstate"
terraform -chdir=infra/azure plan -out=azure.tfplan
terraform -chdir=infra/azure apply azure.tfplan
terraform -chdir=infra/azure output
```

Optional overrides: `export TF_VAR_location=...`, `TF_VAR_prefix=...`, `TF_VAR_node_type=...`,
`TF_VAR_spark_version=...`. `terraform.tfvars.example` documents the equivalent variable file.
The stack creates the lake, six containers, premium workspace, access connector, ADF with its
system identity, two linked services, two binary datasets, the pipeline, and ADF diagnostics.
No scheduled trigger is created: runs are manual.

## 4. Configure the workspace prerequisite

Open the `databricks_host` output. Confirm it has a Unity Catalog metastore attached.
Confirm the catalog you selected exists. Grant the deployment user/service principal the permissions
listed above. This tenant-specific account setup may need an admin and cannot be inferred by Terraform.

## 5. Apply Databricks objects

```bash
source scripts/cloud_env.sh
terraform -chdir=infra/databricks init \
  -backend-config="resource_group_name=$STATE_RG" \
  -backend-config="storage_account_name=$STATE_ACCOUNT" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=retail-databricks.tfstate"
terraform -chdir=infra/databricks plan -out=databricks.tfplan
terraform -chdir=infra/databricks apply databricks.tfplan
```

`cloud_env.sh` passes Azure outputs to the second stack and resolves ADF's **application/client ID**
from its managed identity object ID using Microsoft Graph. If directory reads are restricted, ask an
admin for that client ID and export `TF_VAR_adf_application_id` before sourcing the script.
Do not substitute the principal/object ID: these are different identifiers.
The ADF service principal is created in the workspace and granted compute creation, notebook run,
external-location access, and catalog/schema permissions.
RBAC propagation must finish before Unity Catalog validates storage credentials/external locations.

## 6. Upload and execute

```bash
bash scripts/upload_sample.sh
bash scripts/run_cloud.sh
```

The second command prints the ADF run ID and polls for completion for at most 30 minutes.
Open ADF Studio → Monitor → Pipeline runs to inspect Copy and Notebook activities separately.
The notebook activity output includes JSON counts. In Databricks, run `scripts/query_results.sql`
using a compute resource you are permitted to use. Tables live under `<catalog>.etl_demo`.
Querying as your personal user may need schema/table SELECT privileges from the table owner/admin;
the ADF identity owns the tables it creates. Workspace admin status alone does not imply UC table access.

A successful sample run returns 12 inputs, 5 silver, 5 rejected, 2 duplicates removed, and 550.00 revenue.
Use the next guide to run the same deployment through GitHub Actions.
