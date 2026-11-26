# Microsoft Foundry, with opencode and GitHub Copilot

Repeatable Bicep deployment of a Microsoft Foundry account with a model on Regional Provisioned
Throughput in Australia East, used from opencode, or from GitHub Copilot Chat in VS Code as a
custom endpoint.

> [!WARNING]
> **This is expensive.** The default model deployment is the minimum 15 PTUs of Regional Provisioned
> Throughput at USD 2.00 per PTU per hour: **USD 30 per hour, about USD 720 per day**. You are charged
> for as long as the deployment exists, whether or not anyone uses it. Run `./Remove-All.ps1` as soon
> as you are finished.

## Model selection

Last checked November 2026.

The default is `gpt-5.6-sol` version `2026-07-09`. It uses Regional Provisioned Throughput so prompts
and responses are processed in the Foundry account's geography (Australia). Microsoft may process
them in another region within the geography for operational purposes, such as capacity management.

| Option                            | Region          | Model                         | Processed in        |
| --------------------------------- | --------------- | ----------------------------- | ------------------- |
| Regional provisioned (default)    | `australiaeast` | `gpt-5.6-sol` (`2026-07-09`)  | Australia geography |
| Global provisioned (not regional) | Varies          | Availability varies by region | Any Azure region    |

The default deployment is named `gpt-5-6-sol-dev-001` and uses the `ProvisionedManaged` SKU at 15
PTUs. It has a fixed cost of about USD 30 per hour (USD 720 per day).

15 PTUs is quite small (it is the minimum) and you may face rate limiting if trying to use the model
for any significant tasks.

Regional model availability and minimum PTU capacity vary by model. Confirm that you have quota before
deploying. See [Model and regional processing details](#model-and-regional-processing-details) to check
availability or choose a different model.

## Prerequisites

- PowerShell 7 or later, and Azure CLI 2.61.0 or later with Bicep (all included in the devcontainer).
- A subscription with Regional Provisioned Throughput quota for the model in the target region. Check
  quota in the Foundry portal under **Quota**, or request it from Microsoft.
- Permission to create resources and manage deployment stacks at the selected scopes.
- VS Code on your host or a virtual machine for custom-endpoint setup. BYOK itself doesn't require a
  GitHub Copilot plan, but a Business or Enterprise administrator can disable it by policy.

## Sign in to Azure

Sign in and choose the subscription:

```powershell
az login --tenant <tenant-id>
az account set --subscription <subscription-id>
```

## Deploy and connect

### Deploy everything

Run from this folder:

```powershell
cd ./microsoft-foundry-llm
$VerbosePreference = 'Continue'
./Deploy-Baseline.ps1
```

The script deploys the four stacks in order and prints the hourly cost when finished. Override the
defaults with parameters (`-Purpose`, `-Environment`, `-Instance`, `-Location`) or the matching
`DEPLOY_*` environment variables.

### Clean up when finished

Keep this command handy, but run it **after** you finish testing. Provisioned throughput continues to
cost about USD 30 per hour while the model exists.

```powershell
./Remove-All.ps1 -Verbose
```

The script removes the model first to stop charges as early as possible. It then removes the other
resources and purges the soft-deleted Foundry account. See [Clean up](#clean-up) for model-only removal
and verification commands.

### Get the connection settings

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

This checks the Azure deployment independently of any client configuration. Treat the API key like a
password. Don't paste it into files that are committed to the repo. If it
leaks, rotate it with `az cognitiveservices account keys regenerate --key-name key1 ...`.

## Set up client tools

### Set up in opencode

[opencode](https://opencode.ai/docs/providers/) (installed in the devcontainer) has a built-in
`azure` provider that works with Foundry accounts. `resourceName` is the Foundry account name (the
first label of the endpoint host). It can sign in with Microsoft Entra ID through your `az login`
session, or with the API key.

Entra ID needs a role with data actions on the Foundry account, such as `Foundry User` (see
[Limitations](#limitations-and-trade-offs)); Contributor or Owner alone isn't enough. Without one,
use the API key.

Using the values from [Get the connection settings](#get-the-connection-settings), add the model to
the global config, `~/.config/opencode/opencode.jsonc`. This sets `model`, `agents` and the `azure`
provider in the existing file, or creates it. Other settings are kept, but comments are not:

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
$cfg.providers ??= @{}
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

The first line of output names the model used. If it isn't an `azure` model, the provider isn't
connected and opencode has fallen back to its default free model.

opencode gets tokens from `az` as needed, so it keeps working for as long as your `az login` session
is valid. If you have several tenants, sign in to the one that holds the Foundry account
(`az login --tenant <tenant-id>`).

To use the API key instead, run `opencode auth login azure`, choose **API key**, and paste the value
of `$apiKeys.key1`. opencode stores the key with its credentials, not in the config file.

The `agents` entries pin the background `title` and `summary` tasks to the regional deployment;
otherwise they may pick a small model from another provider. Adjust the token limits to match the
model you deployed.

**Don't switch models.** Choosing another model in the TUI or with `-m` can send prompts outside
Australia. Only pick the `azure/<deployment>` entry.

### Set up in GitHub Copilot

These steps use VS Code Chat's [bring your own key (BYOK)](https://code.visualstudio.com/docs/agent-customization/language-models#_bring-your-own-language-model-key)
support. Custom endpoints aren't supported in remote sessions such as this devcontainer, so perform
these steps in a local VS Code window on your host, or in a virtual machine. Running agentic tools
directly on your host provides less isolation than using the devcontainer.

1. Open a local VS Code window and make sure Chat is available.
2. Open the Chat sidebar and click the model picker at the bottom.
3. Select **Add Models...** (plus).
4. On the models screen, click **Add Models** and select **Custom Endpoint**.
5. Enter the group name `Microsoft Foundry`, then enter the API key.
6. For API Type, use **Responses API** (Chat Completion is older but widely supported; Messages API is
   for Anthropic models).

Then complete the models section of the `Microsoft Foundry` group in `chatLanguageModels.json` with your
Foundry URL and model ID (the `apiKey` input reference is generated by VS Code; keep the one it created):

```json
{
  "name": "Microsoft Foundry (regional)",
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

Troubleshooting: if the model cannot handle your request size, configure fewer tools (turn off the
ones you aren't using).

## Deployment and model details

### What is deployed

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

### Model and regional processing details

The `ProvisionedManaged` SKU (Regional Provisioned Throughput) processes prompts and responses in the
Foundry account's geography. The other SKUs don't guarantee that:

- `GlobalStandard` and `GlobalProvisionedManaged` may process in any Azure region.
- `DataZoneStandard` and `DataZoneProvisionedManaged` process within a multi-region data zone. Check
  whether a data zone is offered for your geography before relying on it.
- `Standard` is regional and pay per token, but few current models offer it in Australian regions.

In all cases, data at rest stays in the account's geography.

To check which models and SKUs are available in your region:

```powershell
az cognitiveservices model list --location australiaeast `
  --query "[?contains(model.skus[].name, 'ProvisionedManaged')].{format:model.format, name:model.name, version:model.version}" `
  -o table
```

To use a different model, override the model parameters on the model stack. Confirm first that it is
listed for `ProvisionedManaged` in your region; newer models often arrive as global deployments first.
The minimum PTU count and increment vary by model, so the deployment fails if `skuCapacity` is too low:

```powershell
--parameters modelName=<model-name> modelVersion=<model-version> skuCapacity=<n>
```

Re-running with a different model name creates a new deployment and the stack deletes the old one.

Currently (November 2026), the endpoint address—for example,
`aif-regional-dev-abc123-001.services.ai.azure.com`—is IPv4 only.

## Deploy step by step

Run these from this folder instead of `Deploy-Baseline.ps1` if you want to deploy or change stacks
individually.

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

## Data residency

A summary for engineering use, not a compliance statement.

- **Processing location:** the regional (`ProvisionedManaged`) deployment processes requests in the
  Australia geography, possibly moving between Australian regions for operational purposes. Global
  and DataZone deployments can process elsewhere.
- **Model provider:** Microsoft hosts the models in Azure, so OpenAI doesn't receive your traffic.
  Microsoft states prompts and completions aren't used to train foundation models. Some data is
  stored at rest in the account's geography, such as Responses API message history and prompts
  flagged by abuse monitoring. See
  [Data, privacy, and security for Foundry Models](https://learn.microsoft.com/en-us/azure/foundry/responsible-ai/openai/data-privacy).
- **Jurisdiction:** Microsoft is a US company, so the US CLOUD Act applies regardless of region.
- **Government work:** check whether Foundry, and the specific deployment type, are in the current
  Microsoft IRAP assessment scope.
- **The client:** opencode and Copilot BYOK send chat to the Foundry endpoint, but Copilot features
  that don't use BYOK still go to GitHub. Check both clients' telemetry settings before relying on
  them for sensitive work.

## Limitations and trade-offs

Considerations before using this setup more widely than one person or a small team.

- **Residency depends on client settings.** Nothing here stops a user picking another model, or a
  client falling back to one. The Copilot model picker shows GitHub-hosted models next to the
  custom endpoint, and opencode falls back to its default free model if the provider isn't
  connected.
- **Model availability.** Not every model is offered with Regional Provisioned Throughput in
  Australian regions. Newer models often arrive as global deployments first.
- **Cost.** Provisioned throughput is billed per hour whether or not it is used. It only becomes
  cheaper than pay-per-token at sustained high usage; for a small team or a demo it is much more
  expensive.
- **Quotas.** Regional Provisioned Throughput quota is not granted by default. The PTUs are a fixed
  capacity shared by all users; heavy agentic sessions from a few people can exhaust it, and
  requests over capacity are throttled (HTTP 429).
- **Credentials.** opencode signs in with each person's Entra ID through `az login`, so requests are
  attributable and there is no shared secret. Copilot BYOK needs the API key, which everyone shares:
  requests can't be attributed to individual users, usage can't be limited per person, and rotating
  a leaked key breaks it for everyone. Distribute it through a secrets store, not chat or email.
- **Feature gaps.** The Copilot custom model applies to chat and utility tasks. Features such as
  inline code completions, semantic search and embeddings still require GitHub Copilot and don't
  use this endpoint.
- **Audit.** This sample doesn't create a diagnostic setting, so Foundry resource logs aren't
  collected. Add one, sending logs to the Log Analytics workspace in Australia, if you need an
  audit trail.
- **Networking.** The Foundry account allows public network access (protected by Entra ID or the
  key), and the endpoint is IPv4 only. Private networking is not part of this sample.
- **Permissions.** Contributor isn't enough for everything. You may be able to create and delete the
  Foundry resource but still need the `Foundry User` role (assigned by an administrator) to use
  Entra ID from opencode or portal features such as Agents. The API key works without it.

## Clean up

Remove everything, purging the soft-deleted Foundry account so the same name can be redeployed. This is
the same command highlighted after deployment:

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

## References

- [Data, privacy, and security for Foundry Models](https://learn.microsoft.com/en-us/azure/foundry/responsible-ai/openai/data-privacy)
- [Deployment types](https://learn.microsoft.com/en-us/azure/ai-foundry/foundry-models/concepts/deployment-types)
- [Provisioned throughput](https://learn.microsoft.com/en-us/azure/ai-foundry/openai/concepts/provisioned-throughput)
- [opencode providers](https://opencode.ai/docs/providers/)
- [VS Code: bring your own language model key](https://code.visualstudio.com/docs/agent-customization/language-models#_bring-your-own-language-model-key)
