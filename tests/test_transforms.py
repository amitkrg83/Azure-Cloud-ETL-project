import json
from decimal import Decimal
from pathlib import Path
import pytest
from pyspark.sql import SparkSession
from cloud_etl.transforms import read_sources, transform, metrics

ROOT = Path(__file__).resolve().parents[1]


@pytest.fixture(scope="module")
def spark():
    session = (SparkSession.builder.master("local[2]").appName("etl-tests")
               .config("spark.sql.shuffle.partitions", "2")
               .config("spark.sql.ansi.enabled", "true")
               .config("spark.sql.session.timeZone", "UTC").getOrCreate())
    session.sparkContext.setLogLevel("ERROR")
    yield session
    session.stop()


@pytest.fixture(scope="module")
def result(spark):
    sources = read_sources(spark, str(ROOT / "data/sample"))
    return sources, transform(*sources)


def test_reconciliation_and_exact_totals(result):
    sources, (silver, gold, rejected) = result
    assert metrics(sources[0], silver, gold, rejected) == json.loads(
        (ROOT / "data/expected_metrics.json").read_text())


def test_latest_valid_version_and_cancellation(result):
    _, (silver, gold, _) = result
    assert silver.filter("order_id = 'O1010'").first().quantity == 3
    assert silver.filter("order_id = 'O1003'").first().status == "cancelled"
    assert gold.agg({"revenue": "sum"}).first()[0] == Decimal("550.00")


def test_reasons_and_raw_evidence(result):
    _, (_, _, rejected) = result
    rows = {r.order_id: r for r in rejected.collect()}
    assert rows["O1005"].rejection_reason == "unknown_customer"
    assert rows["O1006"].rejection_reason == "invalid_quantity"
    assert rows["O1007"].rejection_reason == "invalid_price"
    assert rows["O1008"].rejection_reason == "invalid_date"
    assert rows["O1009"].rejection_reason == "unknown_product"
    assert 'oops' in rows["O1007"].raw_record


def test_duplicate_dimension_fails(spark, tmp_path):
    import shutil
    for p in (ROOT / "data/sample").glob("*.csv"):
        shutil.copy(p, tmp_path / p.name)
    with (tmp_path / "customers.csv").open("a") as f:
        f.write("C001,Duplicate,Texas\n")
    with pytest.raises(ValueError, match="Duplicate dimension"):
        read_sources(spark, str(tmp_path))


def test_idempotent_transform(result):
    sources, (silver, gold, _) = result
    second_silver, second_gold, _ = transform(*sources)
    assert silver.exceptAll(second_silver).count() == 0
    assert second_silver.exceptAll(silver).count() == 0
    assert gold.exceptAll(second_gold).count() == 0
