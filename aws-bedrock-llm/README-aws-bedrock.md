# Claude on Amazon Bedrock, in Australia

Use Claude on Amazon Bedrock with prompts and responses processed only in Australian AWS regions,
from opencode, Claude Code or Claude Desktop. A short Python script helps troubleshoot the connection.

Nothing is deployed. Bedrock runs Claude serverless and charges per token, so there is no idle cost.
You authenticate with your existing AWS sign-in (for example through Stax). No IAM users, roles or
policies are created.

## Model selection

Last checked November 2026.

Only use `au.` model IDs. `global.` and `apac.` profiles can process requests outside Australia, so
each client section below pins every model it uses.

The default is **Claude Opus 5.5**, the newest Claude model that Bedrock can keep in Australia. Newer
models (Claude Fable 5.2 and 5.1) are offered from Australian regions only through the global
inference profile, which can process requests in any commercial AWS region.

| Option                      | Region                    | Model                              | Processed in          |
| --------------------------- | ------------------------- | ---------------------------------- | --------------------- |
| AU geo profile (default)    | `ap-southeast-2` (Sydney) | `au.anthropic.claude-opus-5-5`     | Sydney or Melbourne   |
| Global profile (not for AU) | Any                       | `global.anthropic.claude-opus-5-5` | Any commercial region |

Both use the `bedrock-runtime` endpoint. Single-region processing in Melbourne (`bedrock-mantle`,
`ap-southeast-4`) isn't covered here, as it requires account configuration: Melbourne is an opt-in
region, and the account needs v2 STS session tokens.

Claude Sonnet 5.5 (`au.anthropic.claude-sonnet-5-5`) and Claude Haiku 5.5
(`au.anthropic.claude-haiku-5-5`) also have AU geo profiles, routing to the same two regions. Claude
Code uses all three. AWS notes that new models or versions might not be released for geo profiles.
Check each model's card for current availability:

- [Model availability by region](https://docs.aws.amazon.com/bedrock/latest/userguide/models-region-compatibility.html)
- Model cards for [Claude Opus 5.5](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-anthropic-claude-opus-5-5.html),
  [Claude Sonnet 5.5](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-anthropic-claude-sonnet-5-5.html)
  and [Claude Haiku 5.5](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-anthropic-claude-haiku-5-5.html)
  (Programmatic Access and Regional Availability sections)

Pricing: geographic and in-region endpoints carry a 10% premium over the global endpoint. See
[Amazon Bedrock pricing](https://aws.amazon.com/bedrock/pricing/).

**Note:** Currently (November 2026) the endpoint `bedrock-runtime.ap-southeast-2.amazonaws.com` is
IPv4 only.

## Prerequisites

- A way to sign in to AWS: `stax2aws` for Stax, or AWS CLI v2 (`aws sso login` or `aws login`).
  Both are included in the devcontainer.
- The client you want to use. opencode is included in the devcontainer. Install the others
  separately:
  - Claude Code: see [Claude Code setup](https://code.claude.com/docs/en/setup); on Windows,
    `irm https://claude.ai/install.ps1 | iex`.
  - Claude Desktop: see
    [Claude Desktop on 3P installation](https://claude.com/docs/third-party/claude-desktop/installation).
- Claude Opus 5.5, Claude Sonnet 5.5 and Claude Haiku 5.5 enabled in the AWS account. Enabling a
  model for the first time needs AWS Marketplace permissions; if you don't have them, ask the
  account owner to open the model in the Bedrock console **Model catalog** and send one request from
  the playground. That enables it for everyone in the account.
- An AWS sign-in whose role allows `bedrock:InvokeModel` and
  `bedrock:InvokeModelWithResponseStream` on the `au.` inference profile and the matching
  foundation model (for example `au.anthropic.claude-opus-5-5` and `anthropic.claude-opus-5-5`) for
  each model you use, in both `ap-southeast-2` and `ap-southeast-4`.
- Service control policies that allow Bedrock in both Sydney and Melbourne. If either destination
  region of the AU profile is blocked, requests fail even though the other region is allowed.

If you're not sure about permissions, see [Troubleshooting](#troubleshooting).

## Sign in to AWS

You need to sign in to AWS, either directly, via SSO, or via other tools such as Stax. Sign in on
the machine where the client runs: credentials written inside the devcontainer aren't visible to
Claude Desktop on Windows.

With Stax, use [stax2aws](https://github.com/stax-labs/stax2aws-releases) to write temporary
credentials to a named profile (here `innovation`, for up to 8 hours):

```powershell
stax2aws login -i stax-au1 -o versent-innovation --profile innovation --session-duration 28800
```

Sign in to Stax in the browser when prompted, then select the account and role.

Other setups work too, as long as they leave credentials in the standard AWS credential chain, for
example `aws sso login --profile <name>` with IAM Identity Center, or `aws login`.

## Set up client tools

### Set up in opencode

[opencode](https://opencode.ai/docs/providers/) (installed in the devcontainer) has a built-in
`amazon-bedrock` provider that uses the standard AWS credential chain, and its catalogue already
includes the `au.` model IDs.

Sign in with `stax2aws` as above, then add the models to the global config,
`~/.config/opencode/opencode.jsonc`. This sets `model` and `agents` in the existing file, or
creates it. Other settings are kept, but comments are not:

```powershell
# Sample config
$bedrock = @'
{
  "$schema": "https://opencode.ai/config.json",
  "model": "amazon-bedrock/au.anthropic.claude-opus-5-5",
  "agents": {
    "title": { "model": "amazon-bedrock/au.anthropic.claude-haiku-5-5" },
    "summary": { "model": "amazon-bedrock/au.anthropic.claude-haiku-5-5" }
  }
}
'@ | ConvertFrom-Json -AsHashtable
# Get existing
$path = '~/.config/opencode/opencode.jsonc'
$cfg = (Get-Content $path -Raw -ErrorAction Ignore | ConvertFrom-Json -AsHashtable) ?? @{}
# Update values
$cfg.'$schema' = $bedrock.'$schema'
$cfg.model = $bedrock.model
$cfg.agents = $bedrock.agents
# Write it out
New-Item -ItemType Directory -Force ~/.config/opencode | Out-Null
$cfg | ConvertTo-Json -Depth 10 | Set-Content $path
```

For a single project, use `opencode.jsonc` in the project folder instead.

In the same PowerShell terminal, set the profile and region, then test the default and background
models:

```powershell
$ENV:AWS_PROFILE = 'innovation'
$ENV:AWS_REGION = 'ap-southeast-2'
opencode run "Say hello in five words."
opencode run -m amazon-bedrock/au.anthropic.claude-haiku-5-5 "Say hello in five words."
```

The `agents` entries pin the background `title` and `summary` tasks to an `au.` model; other agents
use the main model. When choosing a model in the TUI, only pick `au.` entries.

`AWS_PROFILE` is what enables the provider; `AWS_REGION` alone does not. When the Stax credentials
expire, run `stax2aws login` again and restart opencode.

### Set up in Claude Code (CLI)

Claude Code switches to Bedrock with environment variables and uses the standard AWS credential
chain, so it can use the same Stax profile.

1. Sign in with `stax2aws` as above.
2. In the same PowerShell terminal, set the environment variables:

   ```powershell
   $ENV:CLAUDE_CODE_USE_BEDROCK = '1'
   $ENV:AWS_PROFILE = 'innovation'
   $ENV:AWS_REGION = 'ap-southeast-2'
   $ENV:ANTHROPIC_BEDROCK_REGION_PREFIX = 'au'
   $ENV:ANTHROPIC_MODEL = 'au.anthropic.claude-opus-5-5'
   $ENV:ANTHROPIC_DEFAULT_OPUS_MODEL = 'au.anthropic.claude-opus-5-5'
   $ENV:ANTHROPIC_DEFAULT_SONNET_MODEL = 'au.anthropic.claude-sonnet-5-5'
   $ENV:ANTHROPIC_DEFAULT_HAIKU_MODEL = 'au.anthropic.claude-haiku-5-5'
   $ENV:ANTHROPIC_DEFAULT_OPUS_MODEL_SUPPORTED_CAPABILITIES = 'effort,xhigh_effort,max_effort,adaptive_thinking'
   $ENV:ANTHROPIC_DEFAULT_SONNET_MODEL_SUPPORTED_CAPABILITIES = 'effort,adaptive_thinking'
   $ENV:ANTHROPIC_DEFAULT_HAIKU_MODEL_SUPPORTED_CAPABILITIES = 'effort,adaptive_thinking'
   ```

3. Then check Claude can process using the different models:

   ```powershell
   claude -p "Say hello in five words." --model opus
   claude -p "Say hello in five words." --model sonnet
   claude -p "Say hello in five words." --model haiku
   ```

Pin every model tier. If you don't, Claude Code picks its own model IDs for background tasks and
uses the `apac.` prefix for `ap-*` regions, which can process requests outside Australia. Opus is
the main model; Claude Code uses the Haiku tier for background tasks.

Claude Code doesn't recognise the `au.` IDs, so the `_SUPPORTED_CAPABILITIES` variables declare what
each model supports. Without them, it sends fixed-budget thinking, and the 5.5 models reject it with
`400 "thinking.type.enabled" is not supported for this model`. Don't add `thinking` to the lists;
that value turns fixed-budget thinking back on.

When the Stax credentials expire, run `stax2aws login` again in another terminal. Don't set
`awsAuthRefresh` to the `stax2aws` command. Claude Code doesn't support interactive input for that
command, and `stax2aws` needs a browser sign-in and a role selection.

The WebSearch tool isn't available on Bedrock.

#### Permanent settings

These variables last only for the terminal session. To make them permanent, put them in the `env`
block of a settings file: `~/.claude/settings.json` for all projects, or a project's
`.claude/settings.json`.

### Set up in Claude Desktop

Claude Desktop can use Bedrock instead of a Claude.ai account ("third-party inference"). The
**Bedrock** provider signs requests with an AWS named profile, so it can reuse the Stax profile from
[Sign in to AWS](#sign-in-to-aws). Use the AU geo profile.

1. Sign in with `stax2aws` on the computer where Claude Desktop runs (for example Windows, not the
   devcontainer).
2. In Claude Desktop, open the application menu (☰, top left of the sign-in screen on Windows) and
   select **Help → Troubleshooting → Enable Developer Mode**.
3. Select **Developer → Configure Third-Party Inference…**.
4. In **Connection**, set:

   | Field              | Value                    |
   | ------------------ | ------------------------ |
   | Inference provider | **Bedrock**              |
   | Credential kind    | **Cloud vendor profile** |
   | AWS region         | `ap-southeast-2`         |
   | AWS profile name   | `innovation`             |

5. In **Models**, add `au.anthropic.claude-opus-5-5` (the first entry is the default). The app can't
   discover models with profile credentials, so at least one entry is required.
6. Click **Test connection**, then **Apply Changes** and **Relaunch now**.

When the Stax credentials expire, run `stax2aws login` again. The app's automatic re-login runs
`aws sso login`, which only works for IAM Identity Center profiles, not Stax.

The other option, **Interactive sign-in**, needs an IAM Identity Center start URL, region, account
ID and permission set; with Stax this is likely not available, so check with the account owner.

Server-side tools that need Anthropic-hosted infrastructure, such as web search, aren't available
with Bedrock.

## Troubleshooting

If a client fails, use this script to check sign-in, permissions and model access outside the
client. It needs Python 3.

### Test environment setup

Create a Python virtual environment for this example and install its dependencies from
[requirements.txt](requirements.txt). The commands below assume you are in the
`aws-bedrock-llm` folder with the virtual environment active.

Windows PowerShell:

```powershell
cd .\aws-bedrock-llm
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

Devcontainer (PowerShell on Linux). If running on Windows, this puts the venv in the user's home
directory, on the container WSL volume, rather than the mapped Windows folder:

```powershell
cd ./aws-bedrock-llm
python3 -m venv ~/.venvs/aws-bedrock-llm
~/.venvs/aws-bedrock-llm/bin/Activate.ps1
pip install -r requirements.txt
```

In bash, activate with `source ~/.venvs/aws-bedrock-llm/bin/activate` instead.

### Run the test

```powershell
python check_claude_model.py --profile innovation
```

This sends a short prompt to `au.anthropic.claude-opus-5-5` through `bedrock-runtime` in Sydney and
prints the reply. Set `$ENV:AWS_PROFILE = 'innovation'` to skip `--profile`. Each model must be
enabled in the account; test the others with `--model <id>`, for example
`--model au.anthropic.claude-haiku-5-5`.

Add `-v` to see progress and token usage; `--help` lists all options. Each option also reads an
environment variable (`AWS_REGION`, `AWS_PROFILE`, `DEPLOY_MODEL_ID`).

If it fails:

- **"AWS credentials problem" or 401:** sign in again; the profile is missing or its credentials expired.
- **403:** your role lacks the permissions above, the model isn't enabled in the account, or an SCP
  blocks one of the AU destination regions. Ask the account owner.
- **400 or 404:** the model ID isn't offered in that region. Check the table above.

## Data residency

A summary for engineering use, not a compliance statement.

- **Processing location:** the AU geo profile processes requests in Sydney or Melbourne. Avoid
  `global.` profile IDs, which can process anywhere.
- **Model provider:** Bedrock runs Claude on AWS-managed infrastructure, so Anthropic doesn't
  receive your traffic. AWS states Bedrock doesn't use prompts or completions for training. See
  [Data protection in Amazon Bedrock](https://docs.aws.amazon.com/bedrock/latest/userguide/data-protection.html).
- **Jurisdiction:** AWS is a US company, so the US CLOUD Act applies regardless of region.
- **Government work:** check whether Bedrock, and the specific endpoint, are in the current AWS IRAP
  assessment scope.
- **The client:** opencode, Claude Code with `CLAUDE_CODE_USE_BEDROCK`, and Claude Desktop in
  third-party mode send inference to Bedrock, but check their telemetry settings before relying on
  them for sensitive work.

## Limitations and trade-offs

Considerations before using this setup more widely than one person or a small team.

- **Residency depends on client settings.** Nothing here stops a user picking a `global.` or
  `apac.` model, or a client falling back to one. For enforcement, have the account owner deny
  Bedrock invocation of non-`au.` inference profiles in IAM or an SCP.
- **Model lag.** The newest Claude models may reach Australia only through the global profile, or
  later than other geographies. In-region processing can mean using an older model.
- **Cost.** The geo profile carries a 10% premium over global. Usage is billed to the account;
  per-user or per-team attribution needs separate accounts or tagged application inference
  profiles.
- **Quotas.** On-demand tokens-per-minute and requests-per-minute quotas apply per account and
  region. A team sharing one account can hit throttling (HTTP 429); check Service Quotas and
  request increases if needed.
- **Credentials.** Stax credentials last up to 8 hours and need a manual browser sign-in to renew;
  the clients can't refresh them. IAM Identity Center profiles refresh more smoothly in Claude
  Desktop.
- **Per-user setup.** Each user configures their client by hand. For a fleet, Claude Code managed
  settings and Claude Desktop MDM configuration can enforce the models and provider centrally.
- **Feature gaps.** Server-side tools that need Anthropic-hosted infrastructure, such as web
  search, aren't available on Bedrock.
- **Audit.** Bedrock model invocation logging is off by default, so prompts and responses aren't
  recorded. Turn it on if you need an audit trail, and keep the logs in an Australian region.
- **Networking.** The Sydney `bedrock-runtime` endpoint is IPv4 only, and traffic goes over the
  public endpoint unless you add a VPC interface endpoint.

## Clean up

Nothing to remove. There is no charge when you're not sending requests, and the Stax credentials
expire on their own.

## References

- [Claude in Amazon Bedrock (Anthropic)](https://platform.claude.com/docs/en/build-with-claude/claude-in-amazon-bedrock)
- [Inference profiles](https://docs.aws.amazon.com/bedrock/latest/userguide/inference-profiles-support.html)
- [opencode providers](https://opencode.ai/docs/providers/)
- [Claude Code on Amazon Bedrock](https://code.claude.com/docs/en/amazon-bedrock)
- [Claude Desktop on 3P: Amazon Bedrock](https://claude.com/docs/third-party/claude-desktop/bedrock)
- [Claude Desktop on 3P: in-app configuration](https://claude.com/docs/third-party/claude-desktop/in-app-configuration)
