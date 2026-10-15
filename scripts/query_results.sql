-- Replace main.etl_demo if you configured a different catalog/schema.
SELECT * FROM main.etl_demo.daily_sales ORDER BY order_date, region, category;
SELECT order_id, rejection_reason, raw_record FROM main.etl_demo.rejected_orders;
SELECT * FROM main.etl_demo.pipeline_runs ORDER BY run_id;
DESCRIBE HISTORY main.etl_demo.orders;
-- 550.00 expected, with no cancelled/pending revenue.
SELECT SUM(revenue) AS total_revenue FROM main.etl_demo.daily_sales;
