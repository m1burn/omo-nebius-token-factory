# VIOLATIONS PLANTED FOR QUALITY-SMOKE (do not fix):
# - trivy/tflint: TLS not enforced on the storage account (https_only disabled below)
# - trivy/tflint: storage account open to all networks (public network access enabled)
resource "azurerm_storage_account" "bad" {
  name                          = "qualitysmokefixture"
  resource_group_name           = "rg-quality-smoke"
  location                      = "westeurope"
  account_tier                  = "Standard"
  account_replication_type      = "LRS"
  https_only                    = false
  public_network_access_enabled = true
}
