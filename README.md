# ☁️ Cloud ETL Pipeline — Azure Databricks + Data Factory + Terraform + CI/CD

A fully automated, production-ready **Cloud ETL pipeline** built with a modern, in-demand Azure data engineering stack.  
This project demonstrates **infrastructure-as-code, data orchestration, and continuous delivery** for scalable and secure ETL workflows.

---

## 🚀 Architecture Overview

### High-Level Flow
```
Data Sources → Ingestion (ADF / Auto Loader)
→ Transformation (Databricks + Delta Lake)
→ Storage (ADLS + Unity Catalog)
→ Consumption (Power BI / ML)
```

### Core Components
| Layer | Technology | Purpose |
|--------|-------------|----------|
| **Ingestion** | Azure Data Factory (ADF) | Orchestrate data extraction from APIs, databases, and files |
| **Transformation** | Azure Databricks (Spark + Delta Lake) | Clean, standardize, and enrich data using PySpark |
| **Storage** | ADLS Gen2 + Unity Catalog | Secure, hierarchical data storage and governance |
| **Orchestration** | ADF + GitHub Actions | Automate and schedule ETL jobs |
| **Infrastructure** | Terraform | Provision resources across environments (dev/test/prod) |
| **Data Quality** | Great Expectations | Enforce schema and value-level data validation |
| **Monitoring** | Azure Monitor + Log Analytics | Track pipeline runs, job metrics, and alerts |

---

## 🧱 Project Structure

```
cloud-etl/
├─ infra/                     # Terraform IaC
│  ├─ main.tf                 # Providers and Resource Groups
│  ├─ datalake.tf             # ADLS Gen2 + containers
│  ├─ databricks.tf           # Workspace + cluster setup
│  ├─ datafactory.tf          # Pipelines and Linked Services
│  ├─ keyvault.tf             # Secrets and credentials
│  ├─ monitor.tf              # Log Analytics and Alerts
│  └─ env/dev.tfvars          # Environment variables
│
├─ etl/
│  ├─ bronze/ingest_autoloader.py    # Ingest raw data using Spark Auto Loader
│  ├─ silver/clean_and_conform.py    # Clean, validate, and standardize data
│  ├─ gold/business_curations.py     # Aggregation and business-ready datasets
│  ├─ common/io_utils.py             # Utility functions for reads/writes
│  └─ common/expectations/           # Great Expectations data validation
│
├─ adf/
│  ├─ pipelines/ingest_pipeline.json # ADF JSON definition
│  └─ datasets_linkedservices/       # Source/Target connection definitions
│
├─ tests/
│  ├─ unit/test_io_utils.py          # Unit tests for helper functions
│  └─ dq/test_expectations.py        # Data quality tests
│
├─ .github/workflows/
│  ├─ ci.yml                         # Linting + Unit Tests on PRs
│  └─ cd-infra-and-jobs.yml          # Terraform Deploy + Databricks sync
│
├─ .pre-commit-config.yaml
├─ Makefile
└─ README.md
```

---

## 🔧 Setup Instructions

### 1️⃣ Prerequisites
- Azure Subscription (Contributor or Owner role)
- Service Principal with:
  - `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`
- Installed locally:
  - `terraform`, `az`, `python3`, `databricks-cli`, `git`

---

### 2️⃣ Clone the Repo
```bash
git clone https://github.com/<yourusername>/cloud-etl.git
cd cloud-etl
```

---

### 3️⃣ Initialize Terraform
```bash
cd infra
terraform init
terraform workspace new dev || terraform workspace select dev
terraform apply -var-file=env/dev.tfvars
```

This provisions:
- Resource Group  
- ADLS Gen2 (raw, bronze, silver, gold)  
- Databricks Workspace + Cluster  
- Azure Data Factory  
- Key Vault + Log Analytics  

---

### 4️⃣ Configure Databricks CLI
```bash
databricks configure --host https://<databricks-instance> --token <PAT_TOKEN>
```

---

### 5️⃣ Run ETL Jobs
Use the ADF pipeline trigger or Databricks notebook jobs directly.

Example (manual test):
```bash
databricks workspace import_dir etl /Shared/etl --overwrite
databricks jobs run-now --job-id <your-job-id>
```

---

### 6️⃣ Verify Delta Tables
```sql
-- Inside Databricks SQL or notebook
SELECT * FROM main.bronze.sales_raw LIMIT 10;
SELECT * FROM main.silver.sales LIMIT 10;
SELECT * FROM main.gold.daily_sales ORDER BY d DESC;
```

---

## 🔁 CI/CD Workflow

**GitHub Actions** automates:
- `ci.yml`: Linting, unit tests, and data quality validation on every pull request.  
- `cd-infra-and-jobs.yml`: Applies Terraform infra and syncs Databricks jobs to prod when merged into `main`.

Secrets required in GitHub repo:
- `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_CLIENT_SECRET`
- `DATABRICKS_HOST`, `DATABRICKS_TOKEN`

---

## 🔍 Monitoring & Alerts

- Azure Monitor & Log Analytics collect Databricks job and ADF pipeline logs.
- Alerts are configured for:
  - Job or pipeline failures
  - Cost overages
  - Key Vault access anomalies

---

## 🛡️ Security & Governance

- All secrets are stored in **Azure Key Vault**.  
- **Unity Catalog** manages fine-grained access control across bronze, silver, and gold tables.  
- **RBAC** + **Private Endpoints** ensure secure data flow.

---

## 🌟 Features

✅ Cloud-native, serverless ETL  
✅ Delta Lake with schema evolution  
✅ Great Expectations-based data validation  
✅ Infrastructure-as-Code (Terraform)  
✅ Automated CI/CD with GitHub Actions  
✅ Monitored and governed with Azure tools  

---

## 📈 Future Enhancements

- Add streaming ingestion (Event Hub → Delta Live Tables)
- Implement MLflow tracking for data drift
- Deploy using Azure DevOps pipelines as an alternative CI/CD
- Add dbt for SQL-based transformation in Gold layer

---

## 🤝 Contributing

1. Create a new feature branch:
   ```bash
   git checkout -b feature/<feature-name>
   ```
2. Commit and push changes:
   ```bash
   git commit -m "Add: <change description>"
   git push origin feature/<feature-name>
   ```
3. Submit a Pull Request for review.

---

## 📜 License

This project is released under the **MIT License**.

---

**Author:** Amit kumar
**Email:** amitkrg83@gmail.com 
**LinkedIn:** [linkedin.com/in/yourprofile]([https://www.linkedin.com/in/amitkrg83/)
