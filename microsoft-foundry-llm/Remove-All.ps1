#!/usr/bin/env pwsh

<#
.SYNOPSIS
  Removes the model deployment, Foundry account, shared resources and resource
  group, then purges the soft-deleted Foundry account.

.DESCRIPTION
  Deletes the stacks in reverse order, starting with the model deployment so
  model charges stop as early as possible. Stacks that don't
  exist are skipped, so the script can be re-run safely, and it also works
  when the resource group was provided (no init stack).

  The Foundry account is soft deleted by Azure; it is purged so the same name
  can be deployed again.

.NOTES
  Requires PowerShell 7+ and Azure CLI, signed in to the target subscription.

.EXAMPLE
  az login
  az account set --subscription <subscription id>
  ./Remove-All.ps1 -Verbose
#>
[CmdletBinding()]
param (
  [string]$Purpose = $ENV:DEPLOY_PURPOSE ?? 'Regional',
  [string]$Environment = $ENV:DEPLOY_ENVIRONMENT ?? 'Dev',
  [string]$Instance = $ENV:DEPLOY_INSTANCE ?? '001'
)

$ErrorActionPreference = 'Stop'

$nameSuffix = "$Purpose-llm-$Environment-$Instance".ToLowerInvariant()
$resourceGroupName = "rg-$nameSuffix"
$stackPrefix = "stack-$nameSuffix"

foreach ($stack in 'model', 'foundry', 'shared') {
  $stackName = "$stackPrefix-$stack"
  az stack group show --resource-group $resourceGroupName --name $stackName --output none 2>$null
  if ($LASTEXITCODE -eq 0) {
    Write-Verbose "Deleting stack $stackName"
    az stack group delete `
      --resource-group $resourceGroupName `
      --name $stackName `
      --action-on-unmanage deleteResources `
      --yes
    if ($LASTEXITCODE -ne 0) { throw "Failed to delete stack $stackName." }
  }
  else {
    Write-Verbose "Stack $stackName not found, skipping"
  }
}

$initStackName = "$stackPrefix-init"
az stack sub show --name $initStackName --output none 2>$null
if ($LASTEXITCODE -eq 0) {
  Write-Verbose "Deleting stack $initStackName and resource group $resourceGroupName"
  az stack sub delete `
    --name $initStackName `
    --action-on-unmanage deleteAll `
    --yes
  if ($LASTEXITCODE -ne 0) { throw "Failed to delete stack $initStackName." }
}
else {
  Write-Verbose "Stack $initStackName not found, skipping"
}

# The Foundry name includes a uniqueString suffix computed by Bicep, so find
# soft-deleted accounts by resource group instead of rebuilding the name.
$deletedAccounts = az cognitiveservices account list-deleted --output json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw 'Failed to list soft-deleted accounts.' }
$toPurge = @($deletedAccounts | Where-Object { $_.id -match "/resourceGroups/$resourceGroupName/" })
if ($toPurge.Count -eq 0) {
  Write-Verbose "No soft-deleted Foundry accounts from $resourceGroupName to purge"
}
foreach ($account in $toPurge) {
  Write-Verbose "Purging soft-deleted Foundry account $($account.name)"
  az cognitiveservices account purge `
    --resource-group $resourceGroupName `
    --name $account.name `
    --location $account.location
  if ($LASTEXITCODE -ne 0) { throw "Failed to purge $($account.name)." }
}
