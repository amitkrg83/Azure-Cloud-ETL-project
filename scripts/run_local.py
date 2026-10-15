"""Run the same Spark logic without Azure. Output is Parquet, not Delta."""
import argparse
import json
import shutil
from pathlib import Path
from pyspark.sql import SparkSession
from cloud_etl.transforms import read_sources, transform, metrics


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default="output")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    out = Path(args.output).resolve()
    spark = (SparkSession.builder.master("local[2]").appName("retail-etl-demo")
             .config("spark.sql.session.timeZone", "UTC")
             .config("spark.sql.shuffle.partitions", "2").getOrCreate())
    spark.sparkContext.setLogLevel("ERROR")
    try:
        bronze = out / "bronze"
        bronze.mkdir(parents=True, exist_ok=True)
        for source in (root / "data/sample").glob("*.csv"):
            shutil.copy2(source, bronze / source.name)
        orders, customers, products = read_sources(spark, str(bronze))
        silver, gold, rejected = transform(orders, customers, products)
        for name, frame in [("silver/orders", silver), ("gold/daily_sales", gold),
                            ("quarantine/orders", rejected)]:
            frame.write.mode("overwrite").parquet(str(out / name))
        report = metrics(orders, silver, gold, rejected)
        (out / "metrics.json").write_text(json.dumps(report, indent=2) + "\n")
        gold.orderBy("order_date", "region", "category").show(truncate=False)
        print(json.dumps(report, indent=2))
        assert report == json.loads((root / "data/expected_metrics.json").read_text())
        print(f"PASS: sample output matches expectations. Results: {out}")
    finally:
        spark.stop()


if __name__ == "__main__":
    main()
