terraform {
  required_version = ">= 1.9, < 2.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.26.0" }
    random  = { source = "hashicorp/random", version = "~> 3.7.1" }
  }
  backend "azurerm" {}
}
provider "azurerm" {
  features {}
  subscription_id     = var.subscription_id
  storage_use_azuread = true
}
variable "subscription_id" { type = string }
variable "location" { default = "eastus2" }
variable "prefix" {
  default = "amitetl"
  validation {
    condition     = can(regex("^[a-z][a-z0-9]{2,11}$", var.prefix))
    error_message = "Use 3-12 lowercase letters/digits, beginning with a letter."
  }
}
variable "spark_version" { default = "15.4.x-scala2.12" }
variable "node_type" { default = "Standard_D4ds_v5" }
variable "catalog" { default = "main" }
variable "schema" { default = "etl_demo" }
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}
locals { name = "${var.prefix}${random_string.suffix.result}" }
resource "azurerm_resource_group" "demo" {
  name     = "rg-${local.name}"
  location = var.location
  tags     = { project = "azure-cloud-etl", environment = "demo" }
}
resource "azurerm_storage_account" "lake" {
  name                            = local.name
  resource_group_name             = azurerm_resource_group.demo.name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  is_hns_enabled                  = true
  min_tls_version                 = "TLS1_2"
  shared_access_key_enabled       = false
  allow_nested_items_to_be_public = false
}
data "azurerm_client_config" "current" {}
resource "azurerm_role_assignment" "deployer_storage" {
  scope                = azurerm_storage_account.lake.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}
resource "azurerm_storage_container" "layers" {
  depends_on            = [azurerm_role_assignment.deployer_storage]
  for_each              = toset(["landing", "bronze", "silver", "gold", "quarantine", "audit"])
  name                  = each.key
  storage_account_id    = azurerm_storage_account.lake.id
  container_access_type = "private"
}
resource "azurerm_databricks_workspace" "demo" {
  name                = "dbw-${local.name}"
  resource_group_name = azurerm_resource_group.demo.name
  location            = var.location
  sku                 = "premium"
}
resource "azurerm_databricks_access_connector" "lake" {
  name                = "ac-${local.name}"
  resource_group_name = azurerm_resource_group.demo.name
  location            = var.location
  identity { type = "SystemAssigned" }
}
resource "azurerm_role_assignment" "connector_storage" {
  scope                = azurerm_storage_account.lake.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_databricks_access_connector.lake.identity[0].principal_id
}
resource "azurerm_data_factory" "demo" {
  name                = "adf-${local.name}"
  resource_group_name = azurerm_resource_group.demo.name
  location            = var.location
  identity { type = "SystemAssigned" }
}
resource "azurerm_role_assignment" "adf_storage" {
  scope                = azurerm_storage_account.lake.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_data_factory.demo.identity[0].principal_id
}
resource "azurerm_role_assignment" "adf_workspace" {
  scope                = azurerm_databricks_workspace.demo.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_data_factory.demo.identity[0].principal_id
}
resource "azurerm_data_factory_linked_custom_service" "lake" {
  name                 = "LS_ADLS_ManagedIdentity"
  data_factory_id      = azurerm_data_factory.demo.id
  type                 = "AzureBlobFS"
  type_properties_json = jsonencode({ url = azurerm_storage_account.lake.primary_dfs_endpoint })
}
resource "azurerm_data_factory_linked_custom_service" "databricks" {
  name            = "LS_Databricks_ManagedIdentity"
  data_factory_id = azurerm_data_factory.demo.id
  type            = "AzureDatabricks"
  type_properties_json = jsonencode({
    domain                = "https://${azurerm_databricks_workspace.demo.workspace_url}"
    authentication        = "MSI"
    workspaceResourceId   = azurerm_databricks_workspace.demo.id
    newClusterVersion     = var.spark_version
    newClusterNodeType    = var.node_type
    newClusterNumOfWorker = "1"
    dataSecurityMode      = "USER_ISOLATION"
  })
}
resource "azurerm_data_factory_custom_dataset" "files" {
  for_each        = toset(["landing", "bronze"])
  name            = "DS_${each.key}_Retail"
  data_factory_id = azurerm_data_factory.demo.id
  type            = "Binary"
  linked_service { name = azurerm_data_factory_linked_custom_service.lake.name }
  type_properties_json = jsonencode({
    location = { type = "AzureBlobFSLocation", fileSystem = each.key, folderPath = "retail" }
  })
}
resource "azurerm_data_factory_pipeline" "retail" {
  name            = "PL_Retail_FullSnapshot"
  data_factory_id = azurerm_data_factory.demo.id
  concurrency     = 1
  activities_json = jsonencode([
    {
      name    = "CopyLandingToBronze"
      type    = "Copy"
      policy  = { timeout = "0.01:00:00", retry = 2, retryIntervalInSeconds = 30 }
      inputs  = [{ referenceName = azurerm_data_factory_custom_dataset.files["landing"].name, type = "DatasetReference" }]
      outputs = [{ referenceName = azurerm_data_factory_custom_dataset.files["bronze"].name, type = "DatasetReference" }]
      typeProperties = {
        source = {
          type           = "BinarySource"
          storeSettings  = { type = "AzureBlobFSReadSettings", recursive = false, wildcardFileName = "*.csv" }
          formatSettings = { type = "BinaryReadSettings" }
        }
        sink = {
          type          = "BinarySink"
          storeSettings = { type = "AzureBlobFSWriteSettings", copyBehavior = "PreserveHierarchy" }
        }
      }
    },
    {
      name              = "TransformAndAggregate"
      type              = "DatabricksNotebook"
      dependsOn         = [{ activity = "CopyLandingToBronze", dependencyConditions = ["Succeeded"] }]
      linkedServiceName = { referenceName = azurerm_data_factory_linked_custom_service.databricks.name, type = "LinkedServiceReference" }
      policy            = { timeout = "0.02:00:00", retry = 1, retryIntervalInSeconds = 60 }
      typeProperties = {
        notebookPath = "/Shared/azure-cloud-etl/run_pipeline"
        baseParameters = {
          storage_account = azurerm_storage_account.lake.name
          catalog         = var.catalog
          schema          = var.schema
          run_id          = { value = "@pipeline().RunId", type = "Expression" }
        }
      }
    }
  ])
}
resource "azurerm_log_analytics_workspace" "demo" {
  name                = "log-${local.name}"
  resource_group_name = azurerm_resource_group.demo.name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
}
resource "azurerm_monitor_diagnostic_setting" "adf" {
  name                       = "pipeline-diagnostics"
  target_resource_id         = azurerm_data_factory.demo.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.demo.id
  enabled_log { category = "PipelineRuns" }
  enabled_log { category = "ActivityRuns" }
}
output "resource_group" { value = azurerm_resource_group.demo.name }
output "storage_account" { value = azurerm_storage_account.lake.name }
output "databricks_host" { value = "https://${azurerm_databricks_workspace.demo.workspace_url}" }
output "workspace_resource_id" { value = azurerm_databricks_workspace.demo.id }
output "access_connector_id" { value = azurerm_databricks_access_connector.lake.id }
output "adf_name" { value = azurerm_data_factory.demo.name }
output "adf_principal_id" { value = azurerm_data_factory.demo.identity[0].principal_id }
output "pipeline_name" { value = azurerm_data_factory_pipeline.retail.name }
