# GitHub Actions setup

## CI

On push and pull request, `ci.yml` runs PySpark tests with Java 17/Python 3.11,
Ruff, the full local runner, Terraform formatting and provider-schema validation.
It uploads `output/` as a downloadable workflow artifact. No Azure account is needed for CI.
Terraform provider locks are checked in for reproducibility.

## CD authentication

Use an Entra app registration/service principal dedicated to this demo.
Create a federated credential for GitHub Actions:

- Issuer: `https://token.actions.githubusercontent.com`
- Subject: `repo:amitkrg83/Azure-Cloud-ETL-project:environment:demo`
- Audience: `api://AzureADTokenExchange`

Create the GitHub environment `demo`. Configure reviewers if you want an environment deployment gate.
Grant that identity Azure Contributor and RBAC assignment privileges, backend Blob Data Contributor,
and the Databricks/Unity Catalog rights in AZURE_SETUP.md. For the first workspace, do the initial
Azure setup interactively, attach its metastore, and add the deployment service principal before CD.
Use the same state account and keys to avoid creating a second set of resources.

Set these **GitHub environment variables**, not client secrets:

| Variable | Value |
|---|---|
| AZURE_CLIENT_ID | OIDC app's client ID |
| AZURE_TENANT_ID | Your directory/tenant ID |
| AZURE_SUBSCRIPTION_ID | Demo subscription ID |
| TF_STATE_RESOURCE_GROUP | Backend resource group |
| TF_STATE_ACCOUNT | Backend account |
| UC_CATALOG | Existing accessible Unity Catalog catalog |
| AZURE_LOCATION | Optional; defaults to eastus2 |
| ETL_PREFIX | Optional; defaults to amitetl |
| ADF_APPLICATION_ID | Optional ADF identity client ID, if Graph lookup is blocked |

In Actions → CD - deploy demo → Run workflow:

1. Leave `apply` false to review an Azure infrastructure plan in the logs.
2. Select `apply` true to plan/apply Azure, plan/apply Databricks, upload sample files and run ADF.

The plan-only workflow covers the Azure stack. It does not validate an undeployed Databricks
workspace or promise a Databricks plan. The apply workflow builds the Databricks plan after loading
Azure outputs. Terraform apply uses the saved plan from that same run. Workflow concurrency prevents
two CD executions from racing; ADF concurrency=1 prevents overlapping full snapshots through ADF.
An OIDC trust entry grants authentication; it does not itself grant resource/data permissions.
No cloud workflow is run as part of creating this project.

For a hardened deployment, split Azure and workspace applies into separately reviewed environments,
restrict workflows to protected branches, pin action commits, and scope custom roles to dedicated resources.
