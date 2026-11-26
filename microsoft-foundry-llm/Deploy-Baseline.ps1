#!/usr/bin/env pwsh

<#
.SYNOPSIS
  Deploys the resource group, shared monitoring, Microsoft Foundry account and
  regional model, with default values.

.DESCRIPTION
  Runs the four baseline deployment stacks in order. Each stack is idempotent,
  so the script can be re-run safely.

  The default model deployment is gpt-4.1-mini as a regional Standard (pay per
  token) deployment. Re-running the script replaces any other model deployed
  in the model stack, such as the provisioned throughput alternative, with the
  default. Run Remove-All.ps1 when you are finished.

.NOTES
  Requires PowerShell 7+ and Azure CLI with Bicep, signed in to the target
  subscription.

.EXAMPLE
  az login
  az account set --subscription <subscription id>
  ./Deploy-Baseline.ps1 -Verbose
#>
[CmdletBinding()]
param (
  [string]$Purpose = $ENV:DEPLOY_PURPOSE ?? 'Regional',
  [string]$Environment = $ENV:DEPLOY_ENVIRONMENT ?? 'Dev',
  [string]$Instance = $ENV:DEPLOY_INSTANCE ?? '001',
  [string]$Location = $ENV:DEPLOY_LOCATION ?? 'australiaeast'
)

$ErrorActionPreference = 'Stop'

$baseline = Join-Path $PSScriptRoot 'baseline'
$nameSuffix = "$Purpose-llm-$Environment-$Instance".ToLowerInvariant()
$resourceGroupName = "rg-$nameSuffix"
$stackPrefix = "stack-$nameSuffix"
$commonParameters = @("purpose=$Purpose", "environment=$Environment", "instance=$Instance")
$tags = @(
  "env=$($Environment.ToLowerInvariant())",
  "region=$Location",
  'criticality=low',
  "businessunit=$($Purpose.ToLowerInvariant())",
  'confidentiality=unclassified'
)

Write-Verbose "Creating resource group $resourceGroupName in $Location"
az stack sub create `
  --name "$stackPrefix-init" `
  --location $Location `
  --template-file "$baseline/001-init-foundry-rg/main.bicep" `
  --parameters @commonParameters "region=$Location" `
  --action-on-unmanage detachAll `
  --deny-settings-mode none `
  --tags @tags `
  --output none
if ($LASTEXITCODE -ne 0) { throw 'Resource group deployment failed.' }

Write-Verbose 'Deploying shared resources (Azure Monitor)'
az stack group create `
  --resource-group $resourceGroupName `
  --name "$stackPrefix-shared" `
  --template-file "$baseline/002-deploy-shared/main.bicep" `
  --parameters @commonParameters `
  --action-on-unmanage deleteResources `
  --deny-settings-mode none `
  --tags @tags `
  --output none
if ($LASTEXITCODE -ne 0) { throw 'Shared resources deployment failed.' }

Write-Verbose 'Deploying Microsoft Foundry account and project'
az stack group create `
  --resource-group $resourceGroupName `
  --name "$stackPrefix-foundry" `
  --template-file "$baseline/003-deploy-foundry/main.bicep" `
  --parameters @commonParameters `
  --action-on-unmanage deleteResources `
  --deny-settings-mode none `
  --tags @tags `
  --output none
if ($LASTEXITCODE -ne 0) { throw 'Foundry deployment failed.' }

Write-Verbose 'Deploying model (regional standard, pay per token)'
$modelOutputs = az stack group create `
  --resource-group $resourceGroupName `
  --name "$stackPrefix-model" `
  --template-file "$baseline/004-deploy-model/main.bicep" `
  --parameters @commonParameters `
  --action-on-unmanage deleteResources `
  --deny-settings-mode none `
  --tags @tags `
  --query 'outputs' `
  --output json
if ($LASTEXITCODE -ne 0) { throw 'Model deployment failed.' }
$modelOutputs = $modelOutputs | ConvertFrom-Json

if ($modelOutputs.isProvisioned.value) {
  Write-Warning $modelOutputs.costMessage.value
  Write-Warning 'Run ./Remove-All.ps1 when you are finished to stop charges.'
}
else {
  Write-Output $modelOutputs.costMessage.value
  Write-Output 'Run ./Remove-All.ps1 when you are finished.'
}
