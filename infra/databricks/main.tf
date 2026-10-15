terraform {
  required_version = ">= 1.9, < 2.0"
  required_providers {
    databricks = { source = "databricks/databricks", version = "~> 1.73.0" }
  }
  backend "azurerm" {}
}
provider "databricks" {
  host                        = var.host
  azure_workspace_resource_id = var.workspace_resource_id
  auth_type                   = "azure-cli"
}
variable "host" { type = string }
variable "workspace_resource_id" { type = string }
variable "access_connector_id" { type = string }
variable "storage_account" { type = string }
variable "adf_application_id" { type = string }
variable "catalog" { default = "main" }
variable "schema" { default = "etl_demo" }
resource "databricks_service_principal" "adf" {
  application_id       = var.adf_application_id
  display_name         = "ADF Retail ETL"
  allow_cluster_create = true
  workspace_access     = true
}
resource "databricks_storage_credential" "lake" {
  name = "${var.storage_account}_mi"
  azure_managed_identity { access_connector_id = var.access_connector_id }
  comment = "Managed identity, no storage account keys"
}
resource "databricks_external_location" "layer" {
  for_each        = toset(["bronze", "silver", "gold", "quarantine", "audit"])
  name            = "${var.storage_account}_${each.key}"
  url             = "abfss://${each.key}@${var.storage_account}.dfs.core.windows.net/"
  credential_name = databricks_storage_credential.lake.name
}
resource "databricks_grant" "location" {
  for_each          = databricks_external_location.layer
  external_location = each.value.name
  principal         = databricks_service_principal.adf.application_id
  privileges        = each.key == "bronze" ? ["READ_FILES"] : ["READ_FILES", "WRITE_FILES", "CREATE_EXTERNAL_TABLE"]
}
resource "databricks_schema" "retail" {
  catalog_name  = var.catalog
  name          = var.schema
  comment       = "Retail ETL teaching demo"
  force_destroy = false
}
resource "databricks_grant" "catalog" {
  catalog    = var.catalog
  principal  = databricks_service_principal.adf.application_id
  privileges = ["USE_CATALOG"]
}
resource "databricks_grant" "schema" {
  schema     = databricks_schema.retail.id
  principal  = databricks_service_principal.adf.application_id
  privileges = ["USE_SCHEMA", "CREATE_TABLE"]
}
resource "databricks_notebook" "etl" {
  path     = "/Shared/azure-cloud-etl/run_pipeline"
  language = "PYTHON"
  content_base64 = base64encode(join("\n", [
    "# Databricks notebook source",
    file("${path.module}/../../src/cloud_etl/transforms.py"),
    file("${path.module}/../../notebooks/run_pipeline.py")
  ]))
}
resource "databricks_permissions" "notebook" {
  notebook_path = databricks_notebook.etl.path
  access_control {
    service_principal_name = databricks_service_principal.adf.application_id
    permission_level       = "CAN_RUN"
  }
}
