# COMMAND ----------
# Terraform prepends the shared transforms.py to this Databricks notebook.
import json
import re

for key, default in [("storage_account", ""), ("catalog", "main"),
                     ("schema", "etl_demo"), ("run_id", "manual")]:
    dbutils.widgets.text(key, default)
account, catalog, schema, run_id = [dbutils.widgets.get(k) for k in
                                   ("storage_account", "catalog", "schema", "run_id")]
for identifier in (account, catalog, schema):
    if not re.fullmatch(r"[a-zA-Z0-9_]+", identifier):
        raise ValueError("Only alphanumeric/underscore identifiers are accepted")
spark.conf.set("spark.sql.session.timeZone", "UTC")
spark.conf.set("spark.sql.ansi.enabled", "true")

def lake(container, path):
    return f"abfss://{container}@{account}.dfs.core.windows.net/{path}"

orders, customers, products = read_sources(spark, lake("bronze", "retail"))
silver, gold, rejected = transform(orders, customers, products)
report = metrics(orders, silver, gold, rejected)
# Fixed full snapshot, one concurrent run. No cross-table atomicity is claimed.
for container, table, frame in [("silver", "orders", silver), ("gold", "daily_sales", gold),
                                 ("quarantine", "rejected_orders", rejected)]:
    (frame.write.format("delta").mode("overwrite").option("overwriteSchema", "true")
     .option("path", lake(container, table)).saveAsTable(f"{catalog}.{schema}.{table}"))
report["run_id"] = run_id
(spark.createDataFrame([report]).write.format("delta").mode("append")
 .option("path", lake("audit", "pipeline_runs"))
 .saveAsTable(f"{catalog}.{schema}.pipeline_runs"))
print(json.dumps(report, indent=2))
dbutils.notebook.exit(json.dumps(report))
