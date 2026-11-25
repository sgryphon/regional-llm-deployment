/*
Creates, idempotently via Azure Resource Manager:
  - Resource group `rg-regional-llm-dev-001`

The resource group is created at subscription scope. Shared services (such as
Azure Monitor) are deployed into it by `002-deploy-shared`.

Notes:
  Running this requires Azure CLI and an authenticated subscription context.
  Follow Azure Cloud Adoption Framework naming and tagging conventions:
  https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming
  https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-tagging

Example:
  az stack sub create `
    --name 'stack-regional-llm-dev-001-init' `
    --location 'australiaeast' `
    --template-file './baseline/001-init-foundry-rg/main.bicep' `
    --action-on-unmanage detachAll `
    --deny-settings-mode none `
    --tags env=dev region=australiaeast criticality=low businessunit=regional confidentiality=unclassified
*/

targetScope = 'subscription'

@description('Workload or business-unit identifier. Use a short name-safe value.')
@minLength(1)
@maxLength(12)
param purpose string = 'Regional'

@description('Environment tag and name component.')
@minLength(1)
@maxLength(8)
param environment string = 'Dev'

@description('Azure region for the resource group.')
param region string = 'australiaeast'

@description('Instance suffix for resource names.')
@minLength(1)
@maxLength(8)
param instance string = '001'

@description('Override the default resource group name when required.')
param resourceGroupName string = toLower('rg-${purpose}-llm-${environment}-${instance}')

@description('Confidentiality classification tag. Align this value with the taxonomy used by your organization.')
param confidentiality string = 'Unclassified'

@description('Criticality tag.')
param criticality string = 'low'

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: region
  tags: {
    env: toLower(environment)
    region: region
    criticality: toLower(criticality)
    businessunit: toLower(purpose)
    confidentiality: toLower(confidentiality)
  }
}

output resourceGroupName string = rg.name
output resourceGroupId string = rg.id
