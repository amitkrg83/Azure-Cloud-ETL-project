# Executed verification

Built and checked on 2026-10-15 with Python 3.12.14, Java 17 and PySpark 3.5.5.

| Check | Result |
|---|---|
| `pytest -q` | 5 tests passed |
| Local Spark pipeline | Passed; wrote bronze, silver, gold and quarantine outputs |
| Expected revenue | 550.00 |
| Reconciliation | 12 input = 5 silver + 5 quarantine + 2 duplicates/superseded |
| Ruff lint | Passed |
| Python compilation, including assembled Databricks notebook | Passed |
| Shell syntax (`bash -n`) | Passed |
| Workflow YAML parsing | Passed |
| Terraform HCL parsing and `fmt -check` | Passed |
| Terraform init, both stacks | Provider downloads and lock creation passed |
| Terraform provider-schema validation | Blocked: environment denies Unix sockets needed by providers |
| Azure plan/apply and live ADF run | Not executed; requires Azure authentication and tenant configuration |
| GitHub push | Unavailable: no authenticated GitHub credentials in this session |

Do not interpret syntax checks as a successful cloud deployment. GitHub CI runs `terraform validate`
in a standard runner. Complete the Azure setup guide and inspect plans before deploying.

The tests verify totals and reconciliation, newest valid order selection, cancelled-order behavior,
all five sample rejection reasons with raw evidence, duplicate-dimension rejection, and deterministic reruns.
The local runner independently writes Parquet and checks the metrics fixture.

## Official references consulted

- [ADF compute linked services and managed identity](https://learn.microsoft.com/en-us/azure/data-factory/compute-linked-services)
- [ADF linked-service API properties](https://learn.microsoft.com/en-us/azure/templates/microsoft.datafactory/factories/linkedservices)
- [Unity Catalog managed identities and Access Connector](https://learn.microsoft.com/en-us/azure/databricks/connect/unity-catalog/cloud-storage/azure-managed-identities)
- [AzureRM custom dataset resource](https://registry.terraform.io/providers/hashicorp/azurerm/4.26.0/docs/resources/data_factory_custom_dataset)
- [AzureRM custom linked service resource](https://registry.terraform.io/providers/hashicorp/azurerm/4.26.0/docs/resources/data_factory_linked_custom_service)
- [Databricks notebook permissions](https://registry.terraform.io/providers/databricks/databricks/1.73.0/docs/resources/permissions)
