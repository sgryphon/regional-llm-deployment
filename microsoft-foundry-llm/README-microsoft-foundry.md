# Microsoft Foundry, with opencode and GitHub Copilot

Repeatable Bicep deployment of a Microsoft Foundry account with a model on Regional Provisioned
Throughput in Australia East, used from opencode, or from GitHub Copilot Chat in VS Code as a
custom endpoint.

> [!WARNING]
> **This is expensive.** The default model deployment is the minimum 15 PTUs of Regional Provisioned Throughput at
> USD 2.00 per PTU per hour: **USD 30 per hour, about USD 720 per day**. You are charged for as long as
> the deployment exists, whether or not anyone uses it. Run `./Remove-All.ps1` as soon as you are
> finished.

## What is deployed

| Stack                                | Resources                                                                          |
| ------------------------------------ | ---------------------------------------------------------------------------------- |
| `stack-regional-llm-dev-001-init`    | Resource group `rg-regional-llm-dev-001`                                           |
| `stack-regional-llm-dev-001-shared`  | Log Analytics `log-regional-dev-{orgId}-001`, App Insights `appi-regional-dev-...` |
| `stack-regional-llm-dev-001-foundry` | Foundry account `aif-regional-dev-{orgId}-001`, project `proj-regional-dev-001`    |
| `stack-regional-llm-dev-001-model`   | Model deployment `gpt-5-6-sol-dev-001` (`ProvisionedManaged`, 15 PTUs)             |

`orgId` is derived deterministically from the subscription ID (`uniqueString`). All stacks apply the
lowercase tag keys `env`, `region`, `criticality`, `businessunit` and `confidentiality`.

The model is a separate stack from the Foundry account, so you can remove just the model (which is where
the cost is) and redeploy it later without recreating the account.

## Regional processing

The `ProvisionedManaged` SKU (Regional Provisioned Throughput) processes prompts and responses in the
Foundry account's region. The other SKUs don't guarantee that:

- `GlobalStandard` and `GlobalProvisionedManaged` may process in any Azure region.
- `DataZoneStandard` and `DataZoneProvisionedManaged` process within a multi-region data zone. Check
  whether a data zone is offered for your geography before relying on it.
- `Standard` is regional and pay per token, but few current models offer it in Australian regions.

In all cases, data at rest stays in the account's geography.

## Model selection

Last updated November 2026.

The default is `gpt-5.6-sol` version `2026-07-09`, which is available with Regional Provisioned
Throughput in `australiaeast`. To check which models and SKUs are available in your region:

```powershell
az cognitiveservices model list --location australiaeast `
  --query "[?contains(model.skus[].name, 'ProvisionedManaged')].{format:model.format, name:model.name, version:model.version}" `
  -o table
```

To use a different model, override the model parameters on the model stack (see below). Confirm first
that it is listed for `ProvisionedManaged` in your region; newer models often arrive as global
deployments first. The minimum PTU count and increment vary by model, so the deployment fails if
`skuCapacity` is too low for the model.

## Prerequisites

- PowerShell 7 or later, and Azure CLI 2.61.0 or later with Bicep (all included in the devcontainer).
- A subscription with Regional Provisioned Throughput quota for the model in the target region. Check
  quota in the Foundry portal under **Quota**, or request it from Microsoft.
- Permission to create resources and manage deployment stacks at the selected scopes.
- A GitHub Copilot plan that allows custom models (on Copilot Business and Enterprise, your organisation
  admin may need to enable this policy).

Sign in and choose the subscription:

```powershell
az login --tenant <tenant-id>
az account set --subscription <subscription-id>
```

## Deploy everything

Run from this folder:

```powershell
cd ./microsoft-foundry-llm
$VerbosePreference = 'Continue'
./Deploy-Baseline.ps1
```

The script deploys the four stacks in order and prints the hourly cost when finished. Override the
defaults with parameters (`-Purpose`, `-Environment`, `-Instance`, `-Location`) or the matching
`DEPLOY_*` environment variables.

## Deploy step by step

Run these from this folder instead of the script if you want to deploy or change stacks individually.

### Initialise the resource group

If you have already been provided a resource group, skip this step and pass its name to the following
commands. This avoids requiring subscription-level permissions.

```powershell
az stack sub create `
  --name stack-regional-llm-dev-001-init `
  --location australiaeast `
  --template-file ./baseline/001-init-foundry-rg/main.bicep `
  --action-on-unmanage detachAll `
  --deny-settings-mode none `
  --tags env=dev region=australiaeast criticality=low businessunit=regional confidentiality=unclassified
```

### Deploy shared services: Azure Monitor

```powershell
az stack group create `
  --resource-group rg-regional-llm-dev-001 `
  --name stack-regional-llm-dev-001-shared `
  --template-file ./baseline/002-deploy-shared/main.bicep `
  --action-on-unmanage deleteResources `
  --deny-settings-mode none `
  --tags env=dev region=australiaeast criticality=low businessunit=regional confidentiality=unclassified
```

### Deploy the Foundry account and project

```powershell
az stack group create `
  --resource-group rg-regional-llm-dev-001 `
  --name stack-regional-llm-dev-001-foundry `
  --template-file ./baseline/003-deploy-foundry/main.bicep `
  --action-on-unmanage deleteResources `
  --deny-settings-mode none `
  --tags env=dev region=australiaeast criticality=low businessunit=regional confidentiality=unclassified
```

To use an existing Application Insights resource, add
`--parameters applicationInsightsName=<name> applicationInsightsResourceGroupName=<rg>`.

### Deploy the model

This is the step that costs money. The command prints the hourly cost when complete.

```powershell
az stack group create `
  --resource-group rg-regional-llm-dev-001 `
  --name stack-regional-llm-dev-001-model `
  --template-file ./baseline/004-deploy-model/main.bicep `
  --action-on-unmanage deleteResources `
  --deny-settings-mode none `
  --tags env=dev region=australiaeast criticality=low businessunit=regional confidentiality=unclassified `
  --query 'outputs.costMessage.value' -o tsv
```

You can change the PTU count, or deploy a different model, for example:

```powershell
  --parameters modelName=<model-name> modelVersion=<model-version> skuCapacity=<n>
```

Re-running with a different model name creates a new deployment and the stack deletes the old one.

**Note:** Currently (November 2026) the endpoint address, e.g. `aif-regional-dev-abc123-001.services.ai.azure.com`,
is IPv4 only.

## Using the model

The Foundry account exposes an OpenAI-compatible endpoint. You need three values: the endpoint URL, an
API key, and the deployment name (which is used as the model id).

```powershell
$rg = 'rg-regional-llm-dev-001'
$foundry = az cognitiveservices account list --resource-group $rg | ConvertFrom-Json
$apiKeys = az cognitiveservices account keys list --resource-group $rg --name $foundry.name | ConvertFrom-Json
$deployment = az cognitiveservices account deployment list --resource-group $rg --name $foundry.name | ConvertFrom-Json

$modelUrl = "$($foundry.properties.endpoints.'AI Foundry API')/openai/v1/responses"
$modelId = $deployment.name

Write-Output "Model URL: $modelUrl"
Write-Output "Model ID: $modelId"
```

Check the model responds before configuring any tools:

```powershell
$body = @{
  model = $modelId
  input = 'Say hello in five words.'
} | ConvertTo-Json

$response = Invoke-RestMethod -Method Post -Uri $modelUrl `
  -Headers @{ 'api-key' = $apiKeys.key1 } -ContentType 'application/json' -Body $body
$response.output | Where-Object type -eq 'message' | ForEach-Object { $_.content.text }
```

Treat the API key like a password. Don't paste it into files that are committed to the repo. If it
leaks, rotate it with `az cognitiveservices account keys regenerate --key-name key1 ...`.

## Set up opencode

[opencode](https://opencode.ai/docs/providers/) (installed in the devcontainer) has a built-in
`azure` provider that works with Foundry accounts. `resourceName` is the Foundry account name (the
first label of the endpoint host). It can sign in with Microsoft Entra ID through your `az login`
session, or with the API key.

Entra ID needs a role with data actions on the Foundry account, such as `Foundry User` (see
[Limitations](#limitations-and-trade-offs)); Contributor or Owner alone isn't enough. Without one,
use the API key.

Using the values from [Using the model](#using-the-model), add the model to the global config,
`~/.config/opencode/opencode.jsonc`. This sets `model`, `agents` and the `azure` provider in the
existing file, or creates it. Other settings are kept, but comments are not:

```powershell
# Sample config
$foundryCfg = @"
{
  "`$schema": "https://opencode.ai/config.json",
  "model": "azure/$modelId",
  "agents": {
    "title": { "model": "azure/$modelId" },
    "summary": { "model": "azure/$modelId" }
  },
  "providers": {
    "azure": {
      "settings": {
        "resourceName": "$($foundry.name)"
      },
      "models": {
        "$modelId": {
          "modelID": "$modelId",
          "limit": { "context": 128000, "output": 16000 }
        }
      }
    }
  }
}
"@ | ConvertFrom-Json -AsHashtable
# Get existing
$path = '~/.config/opencode/opencode.jsonc'
$cfg = (Get-Content $path -Raw -ErrorAction Ignore | ConvertFrom-Json -AsHashtable) ?? @{}
# Update values
$cfg.'$schema' = $foundryCfg.'$schema'
$cfg.model = $foundryCfg.model
$cfg.agents = $foundryCfg.agents
if (-not $cfg.providers) { $cfg.providers = @{} }
$cfg.providers.azure = $foundryCfg.providers.azure
# Write it out
New-Item -ItemType Directory -Force ~/.config/opencode | Out-Null
$cfg | ConvertTo-Json -Depth 10 | Set-Content $path
```

For a single project, use `opencode.jsonc` in the project folder instead.

Connect the `azure` provider with Entra ID (Azure CLI), then test the model:

```powershell
opencode auth login azure --method azure-cli --answer "resourceName=$($foundry.name)"
opencode run "Say hello in five words."
```

opencode gets tokens from `az` as needed, so it keeps working for as long as your `az login` session
is valid. If you have several tenants, sign in to the one that holds the Foundry account
(`az login --tenant <tenant-id>`).

To use the API key instead, run `opencode auth login azure`, choose **API key**, and paste the value
of `$apiKeys.key1`. opencode stores the key with its credentials, not in the config file.

The `agents` entries pin the background `title` and `summary` tasks to the regional deployment;
otherwise they may pick a small model from another provider. Adjust the token limits to match the
model you deployed.

## Set up GitHub Copilot in VS Code

These steps use GitHub Copilot Chat's "bring your own key" (BYOK) support. You need the GitHub Copilot Chat
extension. Note that BYOK is not supported in remote sessions (such as a devcontainer), so you need to run
the following on your host (has lack of isolation risks) or a virtual machine.

1. In VS Code, make sure the GitHub Copilot for Azure extension is installed.
2. Open the Chat sidebar and click the model picker at the bottom.
3. Select **Add Models...** (plus).
4. On the models screen, click **Add Models** and select **Custom Endpoint**.
5. Enter the group name `Azure Foundry`, then enter the API key.
6. For API Type, use **Responses API** (Chat Completion is older but widely supported; Messages API is
   for Anthropic models).

Then complete the models section of the `Azure Foundry` group in `chatLanguageModels.json` with your
Foundry URL and model ID (the `apiKey` input reference is generated by VS Code; keep the one it created):

```json
{
  "name": "Azure Foundry (regional)",
  "vendor": "customendpoint",
  "apiKey": "${input:chat.lm.secret.-1234abcd}",
  "apiType": "responses",
  "models": [
    {
      "id": "gpt-5-6-sol-dev-001",
      "name": "GPT-5.6 Sol (Australia East)",
      "url": "https://aif-regional-dev-abc123-001.services.ai.azure.com/openai/v1/responses",
      "toolCalling": true,
      "vision": true,
      "maxInputTokens": 128000,
      "maxOutputTokens": 16000
    }
  ]
}
```

Adjust `vision` and the token limits to match the model you deployed.

Troubleshooting: if the model cannot handle your request size, configure fewer tools (turn off the ones
you aren't using).

## Limitations and trade-offs

- **Shared API key (Copilot).** Everyone using the endpoint through Copilot BYOK shares the same key, so requests can't be attributed to
  individual users, usage can't be limited per person, and rotating a leaked key breaks it for everyone.
  Distribute it through a secrets store, not chat or email.
- **Fixed cost, not usage-based.** Provisioned throughput is billed per hour whether or not it is used.
  It only becomes cheaper than pay-per-token at sustained high usage; for a small team or a demo it is
  much more expensive.
- **Shared, capped throughput.** The PTUs are a fixed capacity shared by all users. Heavy agentic sessions
  from a few people can exhaust it, and requests over capacity are throttled (HTTP 429).
- **Quota and availability.** Regional Provisioned Throughput quota is not granted by default, and not
  every model is offered with it in Australian regions. Newer models often arrive as global deployments
  first.
- **Copilot still depends on GitHub.** A custom model only replaces the model for chat. You still need a
  GitHub Copilot plan and sign-in, and other Copilot features (such as inline code completions) continue
  to use GitHub-hosted models.
- **Public endpoint.** The Foundry account allows public network access (protected by the key), and the
  endpoint is IPv4 only. Private networking is not part of this sample.
- **Contributor isn't enough for everything.** You may be able to create and delete the Foundry
  resource but still need the `Foundry User` role (assigned by an administrator) to use portal features
  such as Agents. The API key works without it.

## Clean up

Remove everything, purging the soft-deleted Foundry account so the same name can be redeployed:

```powershell
./Remove-All.ps1 -Verbose
```

The script deletes the model stack first so charges stop as early as possible, skips stacks that don't
exist, and works when the resource group was provided (no init stack).

To stop the charges but keep the Foundry account, delete just the model stack:

```powershell
az stack group delete `
  --resource-group rg-regional-llm-dev-001 `
  --name stack-regional-llm-dev-001-model `
  --action-on-unmanage deleteResources `
  --yes
```

Confirm nothing is still deployed:

```powershell
az cognitiveservices account deployment list `
  --resource-group rg-regional-llm-dev-001 `
  --name (az cognitiveservices account list --resource-group rg-regional-llm-dev-001 --query '[0].name' -o tsv) `
  -o table
```

## Stack lifecycle

The init stack retains resources removed from its template (`detachAll`); the shared, Foundry and model
stacks delete removed resources but retain the resource group (`deleteResources`). Deleting the init
stack with `deleteAll` deletes the resource group and anything left in it.
