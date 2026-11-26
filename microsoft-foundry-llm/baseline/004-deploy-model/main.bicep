/*
Deploys, idempotently via Azure Resource Manager:
  - Model deployment `<modelName>-<environment>-<instance>` on the Foundry account
    `aif-regional-dev-<orgId>-001`

The Foundry account must already exist; create it with
`003-deploy-foundry/main.bicep`.

The default is gpt-5.6-sol (2026-07-09) with Regional Provisioned Throughput
(ProvisionedManaged SKU) at 10 PTUs, so prompts and responses are processed in
the resource group region. At USD 2.00 per PTU per hour this costs USD 20.00 per
hour (about USD 480 per day) while deployed, whether or not it is used. Delete
the stack when not in use.

Notes:
  Running this requires Azure CLI and an authenticated subscription context.
  Regional provisioned throughput quota for the model must be available in the
  resource group region. The minimum PTU count and increment vary by model.
  Follow Azure Cloud Adoption Framework naming and tagging conventions:
  https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming
  https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-tagging

Example:
  az stack group create `
    --resource-group 'rg-regional-llm-dev-001' `
    --name 'stack-regional-llm-dev-001-model' `
    --template-file './baseline/004-deploy-model/main.bicep' `
    --action-on-unmanage deleteResources `
    --deny-settings-mode none `
    --tags env=dev region=australiaeast criticality=low businessunit=regional confidentiality=unclassified `
    --query 'outputs.costMessage.value' -o tsv

View:
  $foundryName = (az cognitiveservices account list --resource-group 'rg-regional-llm-dev-001' --query '[0].name' -o tsv)
  az cognitiveservices account deployment list `
    --resource-group 'rg-regional-llm-dev-001' `
    --name $foundryName

Cleanup:
  az stack group delete `
    --resource-group 'rg-regional-llm-dev-001' `
    --name 'stack-regional-llm-dev-001-model' `
    --action-on-unmanage deleteResources `
    --yes
*/

@description('Workload or business-unit identifier. Use a short name-safe value.')
@minLength(1)
@maxLength(12)
param purpose string = 'Regional'

@description('Environment tag and name component.')
@minLength(1)
@maxLength(8)
param environment string = 'Dev'

@description('Instance suffix for resource names.')
@minLength(1)
@maxLength(8)
param instance string = '001'

@description('Organization identifier for globally unique names. Defaults deterministically from the subscription ID.')
@minLength(1)
@maxLength(6)
param orgId string = substring(uniqueString(subscription().subscriptionId), 0, 6)

@description('Microsoft Foundry account name.')
@minLength(2)
@maxLength(64)
param foundryName string = toLower('aif-${purpose}-${environment}-${orgId}-${instance}')

@allowed([
  'AI21 Labs'
  'Cohere'
  'Core42'
  'DeepSeek'
  'xAI'
  'Meta'
  'Microsoft'
  'Mistral AI'
  'OpenAI'
  'OpenAI-OSS'
])
@description('Model format (e.g., OpenAI).')
param modelFormat string = 'OpenAI'

@description('Model identifier or name to deploy (e.g., gpt-5.6-sol).')
@minLength(1)
@maxLength(64)
param modelName string = 'gpt-5.6-sol'

@description('Model version to deploy.')
@minLength(1)
@maxLength(64)
param modelVersion string = '2026-07-09'

@allowed([
  'GlobalStandard'
  'DataZoneStandard'
  'Standard'
  'GlobalProvisionedManaged'
  'DataZoneProvisionedManaged'
  'ProvisionedManaged'
])
@description('Deployment SKU. ProvisionedManaged is Regional Provisioned Throughput.')
param skuName string = 'ProvisionedManaged'

@description('Capacity for the deployment: PTUs for provisioned SKUs, or thousands of tokens per minute for standard SKUs.')
@minValue(1)
param skuCapacity int = 15

@description('Price per PTU per hour in USD, used for the cost message output.')
param ptuHourlyRateUsd int = 2

@description('Content filter policy name')
param contentFilterPolicyName string = 'Microsoft.DefaultV2'

@description('Deployment name override. Defaults to <modelName>-<environment>-<instance>.')
@minLength(2)
@maxLength(64)
param deploymentName string = toLower('${replace(modelName, '.', '-')}-${environment}-${instance}')

@description('Confidentiality classification tag. Align this value with the taxonomy used by your organization.')
param confidentiality string = 'Unclassified'

@description('Criticality tag.')
param criticality string = 'low'

var tags = {
  env: toLower(environment)
  region: resourceGroup().location
  criticality: toLower(criticality)
  businessunit: toLower(purpose)
  confidentiality: toLower(confidentiality)
}

var isProvisioned = contains(skuName, 'Provisioned')

resource aiFoundry 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = {
  name: foundryName
}

resource modelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = {
  parent: aiFoundry
  name: deploymentName
  sku: {
    name: skuName
    capacity: skuCapacity
  }
  properties: {
    model: {
      format: modelFormat
      name: modelName
      version: modelVersion
    }
    raiPolicyName: contentFilterPolicyName
  }
  tags: tags
}

output deploymentId string = modelDeployment.id
output deploymentName string = modelDeployment.name
output modelName string = modelName
output foundryName string = foundryName
output costMessage string = isProvisioned
  ? 'Deployed ${modelName} (${modelVersion}) with ${skuCapacity} PTUs (${skuName}). This costs USD ${skuCapacity * ptuHourlyRateUsd}.00 per hour (about USD ${skuCapacity * ptuHourlyRateUsd * 24} per day) until deleted.'
  : 'Deployed ${modelName} (${modelVersion}) as ${skuName} with capacity ${skuCapacity}. Charged per token.'
