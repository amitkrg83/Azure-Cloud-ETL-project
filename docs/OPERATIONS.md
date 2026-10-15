# Operations, failure diagnosis, and cleanup

## Where to look

- ADF Studio → Monitor: pipeline run, activity errors, byte-copy statistics and notebook run link.
- Databricks job run: Spark errors, cluster startup, notebook output, Delta commits.
- Unity Catalog `pipeline_runs`: successful counts, revenue and ADF run ID. Failed runs are recorded in
  ADF diagnostics, not this successful-run table.
- Log Analytics: query `ADFActivityRun` / `ADFPipelineRun` when using resource-specific tables;
  the default diagnostic setting may instead send records to `AzureDiagnostics`.

Example for the default diagnostic destination:
```kusto
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.DATAFACTORY"
| where Category in ("PipelineRuns", "ActivityRuns")
| order by TimeGenerated desc
| take 50
```

## Common failures

| Symptom | Check |
|---|---|
| Local Java gateway fails | Java 17, JAVA_HOME, SPARK_LOCAL_IP=127.0.0.1 |
| Terraform storage 403 | Deployer Blob Data Contributor assignment and propagation |
| State access denied | Azure CLI subscription, ARM_USE_AZUREAD, backend data role |
| CREATE STORAGE CREDENTIAL denied | Metastore privileges for the deploying identity |
| Catalog not found | Actual existing workspace catalog; same TF_VAR_catalog in both stacks |
| UC external location validation fails | Access Connector role and propagation; matching region/network policy |
| Graph lookup denied | Set TF_VAR_adf_application_id to the managed identity CLIENT ID |
| ADF Databricks 403 | ADF workspace Contributor role, workspace service principal, notebook CAN_RUN |
| Cluster cannot start | Regional VM quota, SKU availability, allowed cluster policies, runtime version |
| UC privilege denied during notebook | Location READ_FILES/WRITE_FILES/CREATE_EXTERNAL_TABLE and catalog/schema grants |
| Table exists with another owner | Owner/admin must transfer ownership or grant MODIFY and SELECT; do not blindly drop it |
| Stale data after source removal | Fixed snapshot expects all three files; clear bronze safely or restore the full sample |

## Data behavior and scope

This project refreshes a tiny complete snapshot. Each silver/gold/quarantine Delta overwrite is atomic
for that table, but there is no transaction across all tables. A failed notebook can leave a mixed
snapshot. ADF retries may repeat successful writes and audit events. Reconcile by ADF run ID and
rerun the complete pipeline after fixing the failure.
Do not run the notebook manually concurrently with ADF. Full source snapshots are required;
this is not incremental CDC, watermarking or SCD Type 2.
Schema changes fail until reviewed; schemas are not silently evolved. The code uses direct PySpark
quality rules, not Great Expectations. It has no alert action groups or cost alerts.
Azure public endpoints are enabled; private containers and identities do not mean private networking.
For production add private endpoints/VNet design, least-privilege container scopes, manifest-based
input versions, a publish marker for coherent output versions, idempotent audit keys, alerting,
retention/backup rules, performance tuning and deployment approvals appropriate to your team.

## Costs

Local mode creates no Azure resources. Cloud mode incurs storage, ADF copy/activity,
Databricks DBU/VM, and Log Analytics charges. No SQL warehouse or always-running interactive cluster
is provisioned. Use the runtime/region pricing calculators for current rates. Shut down any additional
compute you create manually and destroy the demo when finished.

## Cleanup order

Export the same variables and initialize the same remote backends used for deployment first.
Save any result data you want to keep. Unity Catalog external table metadata must be removed
before deleting the schema; deleting an external table does not delete the lake data.
As an owner/admin, run:

```sql
-- Replace main/etl_demo as configured; these commands delete demo metadata.
DROP TABLE IF EXISTS main.etl_demo.pipeline_runs;
DROP TABLE IF EXISTS main.etl_demo.rejected_orders;
DROP TABLE IF EXISTS main.etl_demo.daily_sales;
DROP TABLE IF EXISTS main.etl_demo.orders;
```

Then from the repository root:
```bash
source scripts/cloud_env.sh
terraform -chdir=infra/databricks plan -destroy -out=destroy.tfplan
terraform -chdir=infra/databricks apply destroy.tfplan
terraform -chdir=infra/azure plan -destroy -out=destroy.tfplan
terraform -chdir=infra/azure apply destroy.tfplan
```

Review destroy plans before applying. The Azure destroy deletes the demo lake and its data.
The separate backend resource group remains, with state history. Keep it until all resources are
confirmed deleted; remove it separately only if you no longer need the state. Do not delete shared
catalogs, metastores or identity apps that this project did not create.

## Verification performed while building

See `docs/VERIFICATION.md` for the actual executed checks and limitations.
