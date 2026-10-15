# Follow one order through the system

## 1. A business sends three files

Open `data/sample/`. Customers and products are lookup tables; orders reference their IDs.
Think of an order as a C# DTO whose fields initially arrive as strings.
No real customer or healthcare information is present.

`O1001` appears twice. `O1010` changes from pending (1 unit) to completed (3 units).
Five other records contain an unknown customer, zero quantity, malformed price,
invalid date, or unknown product. A cancelled order remains valid but earns no revenue.

## 2. Landing and bronze preserve the evidence

`scripts/upload_sample.sh` uploads the three CSVs to `landing/retail/` using your Azure login.
The first ADF activity copies `*.csv` into `bronze/retail/` unchanged.
ADF moves bytes here; it does not clean order values.
Binary datasets describe where files live, linked services describe which system and identity to use,
and the pipeline describes the execution order. This is similar to a scheduled .NET orchestration service.

For this fixed sample, every run supplies all three complete snapshot files. Do not remove or upload
files while the pipeline runs. Missing source files can leave stale bronze files; this example is
not an atomic, manifest-based file-ingestion protocol.

## 3. Databricks converts strings into meaningful types

The notebook receives storage account, catalog, schema and ADF run ID as widgets.
Terraform prepends `src/cloud_etl/transforms.py` into the uploaded notebook so the exact tested
functions are available without notebook import-path tricks or pip installation on a cluster.

`read_sources()` checks headers and prevents duplicate dimension keys from multiplying revenue.
`transform()` trims IDs, normalizes statuses, and uses `try_cast` for dates, timestamps,
integers and decimal money. Like `TryParse` in C#, malformed input becomes an explicit validation
outcome rather than an unhandled conversion exception. ANSI mode is enabled in cloud and tests.

Left joins keep unmatched customer/product references visible long enough to quarantine them.
Spark DataFrames are lazy, like a LINQ `IQueryable`: transformations construct a plan;
`count`, `show`, and `write` execute it across Spark workers.

## 4. Invalid records go to quarantine

| Order | Reason |
|---|---|
| O1005 | unknown_customer |
| O1006 | invalid_quantity |
| O1007 | invalid_price |
| O1008 | invalid_date |
| O1009 | unknown_product |

Each rejected row retains `raw_record` JSON. Multiple reasons are joined with semicolons.
All-rejected inputs produce empty silver/gold outputs; they do not automatically fail the run.
Missing/extra columns and ambiguous dimension keys fail the batch instead of silently changing totals.

## 5. Silver keeps one valid version per order

A window partitions by `order_id` and orders by `updated_at` descending. The newest valid
version wins. A deterministic JSON tie-breaker handles different rows with equal timestamps;
this is a demo rule, not a business sequence number. An invalid latest version is quarantined,
allowing an older valid version to remain. The test suite checks the supplied update and totals.

There are 12 input rows, 5 rejected rows, 2 duplicate/superseded rows and 5 silver orders.
`quantity * unit_price` uses decimal arithmetic instead of floating-point money.
A silver row has date, quantity, price, status, customer region, product category, and line total.

## 6. Gold answers a business question

Filter to `completed` orders, then group by date, region and category.
The four groups total $550. Pending and cancelled orders contribute no completed revenue.
This is equivalent to a SQL `GROUP BY` or a LINQ grouping followed by sums.
Run `scripts/query_results.sql` in a Databricks SQL editor or notebook attached to compute.
Power BI could consume this table through a separately configured Databricks SQL warehouse.

## 7. Delta and Unity Catalog add different capabilities

Delta stores Parquet files plus a transaction log, providing transactions and history per table.
The notebook writes external Delta tables into separate containers and registers them under
`<catalog>.etl_demo`. Unity Catalog controls who can use the schema and the external locations.
The Azure Access Connector's managed identity supplies the actual storage access.
ADF's managed identity runs the notebook and receives the needed Unity Catalog grants.

The snapshot overwrites silver/gold/quarantine each run, so rerunning the same inputs does not
double the revenue. Audit is append-only: retries may append the same ADF run ID more than once.
Writes to multiple tables are sequential; a failure can expose a partially refreshed set of tables.

## 8. Terraform and CI/CD

Terraform is the infrastructure equivalent of checked-in application configuration with a
resource dependency graph. Azure resources come first; Databricks workspace objects come second.
GitHub Actions CI tests the code on push/PR. Manual CD uses OIDC to sign in without a stored Azure
client secret, applies infrastructure when selected, uploads the dummy dataset and runs ADF.
Both stacks keep separate remotely locked state files.

## Try these experiments

1. Fix C999 to C001 in O1005: one less rejected row and $50 more revenue.
2. Change O1003 from cancelled to completed: revenue increases by $75.
3. Change the latest O1010 quantity from 3 to 5: revenue increases by $100.
4. Add a duplicate customer key: the run fails before publishing results.
5. Rerun unchanged inputs: silver/gold totals remain the same.

For modified data, update `data/expected_metrics.json` and expected assertions, or call the
transformation functions directly. The default local runner deliberately checks the original sample contract.
