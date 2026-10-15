"""Shared, lazy PySpark transformations used locally and in Databricks."""
from pyspark.sql import DataFrame, Window
from pyspark.sql import functions as F

ORDER_COLUMNS = ["order_id", "customer_id", "product_id", "order_date", "quantity",
                 "unit_price", "status", "updated_at"]


def read_sources(spark, root):
    def read(name):
        return spark.read.option("header", True).option("mode", "FAILFAST").csv(f"{root}/{name}.csv")
    orders, customers, products = (read(n) for n in ("orders", "customers", "products"))
    for frame, columns in [(orders, ORDER_COLUMNS),
                           (customers, ["customer_id", "customer_name", "region"]),
                           (products, ["product_id", "product_name", "category"])]:
        if set(frame.columns) != set(columns):
            raise ValueError(f"Schema mismatch: expected {columns}, got {frame.columns}")
    # Ambiguous dimension keys would multiply sales; fail the batch instead.
    for frame, key in [(customers, "customer_id"), (products, "product_id")]:
        if frame.filter(F.col(key).isNull() | (F.trim(F.col(key)) == "")).count():
            raise ValueError(f"Blank dimension key: {key}")
        if frame.groupBy(key).count().filter("count > 1").count():
            raise ValueError(f"Duplicate dimension key: {key}")
    return orders, customers, products


def transform(orders: DataFrame, customers: DataFrame, products: DataFrame):
    # try_cast works with ANSI mode too: malformed values become quarantine rows.
    typed = orders.select(
        *[F.trim(F.col(c)).alias(c) for c in ("order_id", "customer_id", "product_id")],
        F.expr("try_cast(order_date as date)").alias("order_date"),
        F.expr("try_cast(quantity as int)").alias("quantity"),
        F.expr("try_cast(unit_price as decimal(12,2))").alias("unit_price"),
        F.lower(F.trim("status")).alias("status"),
        F.expr("try_cast(updated_at as timestamp)").alias("updated_at"),
        F.to_json(F.struct(*[F.col(c) for c in ORDER_COLUMNS])).alias("raw_record"),
    )
    checked = (typed.join(customers, "customer_id", "left")
               .join(products, "product_id", "left")
               .withColumn("rejection_reason", F.concat_ws(";",
                   F.when(F.col("order_id").isNull() | (F.col("order_id") == ""), "missing_order_id"),
                   F.when(F.col("customer_name").isNull(), "unknown_customer"),
                   F.when(F.col("product_name").isNull(), "unknown_product"),
                   F.when(F.col("order_date").isNull(), "invalid_date"),
                   F.when(F.col("quantity").isNull() | (F.col("quantity") <= 0), "invalid_quantity"),
                   F.when(F.col("unit_price").isNull() | (F.col("unit_price") < 0), "invalid_price"),
                   F.when(F.col("updated_at").isNull(), "invalid_updated_at"),
                   F.when(F.col("status").isNull() |
                          ~F.col("status").isin("completed", "pending", "cancelled"), "invalid_status"))))
    rejected = checked.filter(F.col("rejection_reason") != "")
    valid = checked.filter(F.col("rejection_reason") == "").drop("rejection_reason")
    # Latest VALID version wins; raw JSON breaks equal-timestamp ties deterministically.
    rank = Window.partitionBy("order_id").orderBy(F.desc("updated_at"), F.desc("raw_record"))
    silver = (valid.withColumn("rn", F.row_number().over(rank)).filter("rn = 1").drop("rn")
              .withColumn("line_total", (F.col("quantity") * F.col("unit_price")).cast("decimal(18,2)")))
    gold = (silver.filter("status = 'completed'")
            .groupBy("order_date", "region", "category")
            .agg(F.count("order_id").alias("order_count"), F.sum("quantity").alias("units"),
                 F.sum("line_total").alias("revenue")))
    return silver, gold, rejected


def metrics(orders, silver, gold, rejected):
    raw, clean, bad = orders.count(), silver.count(), rejected.count()
    total = gold.agg(F.sum("revenue")).first()[0]
    return {"input_rows": raw, "silver_rows": clean, "quarantine_rows": bad,
            "duplicates_removed": raw - clean - bad, "gold_rows": gold.count(),
            "total_revenue": str(total or "0.00")}
