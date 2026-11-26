# Claude on Amazon Bedrock, in Australia

Use Claude Opus 5.5 on Amazon Bedrock with prompts and responses processed only in Australian AWS
regions, tested with a short Python script.

Nothing is deployed. Bedrock runs Claude serverless and charges per token, so there is no idle cost.
You authenticate with your existing AWS sign-in (for example through Stax). No IAM users, roles or
policies are created.

If you want, you can 'Sign in to AWS' to AWS and then jump straight to 'Set up client tools'. If you
have troubles you can use 'Test your Bedrock connection' to check if things are working.

## Model selection

Last checked November 2026.

The default is **Claude Opus 5.5**, the newest Claude model that Bedrock can keep in Australia. Newer
models (Claude Fable 5.2 and 5.1) are offered from Australian regions only through the global
inference profile, which can process requests in any commercial AWS region.

| Option                      | Call region               | Model ID                           | Processed in          |
| --------------------------- | ------------------------- | ---------------------------------- | --------------------- |
| AU geo profile (default)    | `ap-southeast-2` (Sydney) | `au.anthropic.claude-opus-5-5`     | Sydney or Melbourne   |
| Global profile (not for AU) | any                       | `global.anthropic.claude-opus-5-5` | any commercial region |

Both use the `bedrock-runtime` endpoint. The AU geo profile can also be called from Melbourne; it
routes to the same two regions.

Single-region processing in Melbourne is offered through the `bedrock-mantle` endpoint
(`anthropic.claude-opus-5-5` in `ap-southeast-4`), but isn't covered here. Melbourne is an opt-in
region, and credentials from the global STS endpoint only work there if the account issues v2
session tokens.

Claude Sonnet 5.5 and Claude Haiku 5.5 also have AU geo profiles. Check each model's card for exact
IDs and current availability:

- [Model availability by region](https://docs.aws.amazon.com/bedrock/latest/userguide/models-region-compatibility.html)
- [Claude Opus 5.5 model card](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-anthropic-claude-opus-5-5.html)
  (Programmatic Access and Regional Availability sections)

Pricing: geographic and in-region endpoints carry a 10% premium over the global endpoint. See
[Amazon Bedrock pricing](https://aws.amazon.com/bedrock/pricing/).

**Note:** Currently (November 2026) the endpoint `bedrock-runtime.ap-southeast-2.amazonaws.com` is
IPv4 only.

## Prerequisites

- Python 3 and AWS CLI v2 (both included in the devcontainer), for testing the connection.
- Claude Opus 5.5 enabled in the AWS account. Enabling a model for the first time needs AWS
  Marketplace permissions; if you don't have them, ask the account owner to open the model in the
  Bedrock console **Model catalog** and send one request from the playground. That enables it for
  everyone in the account.
- An AWS sign-in whose role allows `bedrock:InvokeModel` and
  `bedrock:InvokeModelWithResponseStream` on the `au.anthropic.claude-opus-5-5` inference profile
  and on the `anthropic.claude-opus-5-5` foundation model in both `ap-southeast-2` and
  `ap-southeast-4`.
- Service control policies that allow Bedrock in both Sydney and Melbourne. If either destination
  region of the AU profile is blocked, requests fail even though the other region is allowed.

If you're not sure about permissions, the test below will tell you.

## Sign in to AWS

You need to sign in to AWS, either directly, via SSO, or via other tools such as Stax.

With Stax, use [stax2aws](https://github.com/stax-labs/stax2aws-releases) to write temporary
credentials to a named profile (here `innovation`, for up to 8 hours):

```powershell
stax2aws login -i stax-au1 -o versent-innovation --profile innovation --session-duration 28800
```

Sign in to Stax in the browser when prompted, then select the account and role.

Other setups work too, as long as they leave credentials in the standard AWS credential chain, for
example `aws sso login --profile <name>` with IAM Identity Center, or `aws login`.

## Test your Bedrock connection

This uses a simple script to test Bedrock is working.

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

Devcontainer (PowerShell on Linux). If running on Windows this puts the venv in the user's home directory, on the container WSL volume, rather than the mapped Windows folder:

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
prints the reply. Set `$ENV:AWS_PROFILE = 'innovation'` to skip `--profile`.

Add `-v` to see progress and token usage; `--help` lists all options. Each option also reads an
environment variable (`AWS_REGION`, `AWS_PROFILE`, `DEPLOY_MODEL_ID`).

If it fails:

- **"AWS credentials problem" or 401:** sign in again; the profile is missing or its credentials expired.
- **403:** your role lacks the permissions above, the model isn't enabled in the account, or an SCP
  blocks one of the AU destination regions. Ask the account owner.
- **400 or 404:** the model ID isn't offered in that region. Check the table above.

## Set up client tools

### Set up in Claude Desktop

Claude Desktop can use Bedrock instead of a Claude.ai account ("third-party inference"). The
**Bedrock** provider signs requests with an AWS named profile, so it can reuse the Stax profile from
[Sign in to AWS](#sign-in-to-aws). Use the AU geo profile.

1. Sign in with `stax2aws` as above, and run the test script to confirm the profile works.
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

Other authentication options in Claude Desktop, and whether they suit a Stax account:

- **Interactive sign-in** (in-app AWS sign-in): the app handles login itself through AWS IAM
  Identity Center. It needs an Identity Center start URL, region, account ID and permission set. With
  Stax you sign in through Stax instead, so this is likely not available; check with the account
  owner.

Server-side tools that need Anthropic-hosted infrastructure, such as web search, aren't available
with Bedrock.

## Data residency

A summary for engineering use, not a compliance statement.

- **Processing location:** the AU geo profile processes requests in Sydney or Melbourne. Avoid `global.` profile IDs, which can process anywhere.
- **Model provider:** Bedrock runs Claude on AWS-managed infrastructure, so Anthropic doesn't
  receive your traffic. AWS states Bedrock doesn't use prompts or completions for training. See
  [Data protection in Amazon Bedrock](https://docs.aws.amazon.com/bedrock/latest/userguide/data-protection.html).
- **Jurisdiction:** AWS is a US company, so the US CLOUD Act applies regardless of region.
- **Government work:** check whether Bedrock, and the specific endpoint, are in the current AWS IRAP
  assessment scope.
- **The client:** Claude Desktop in third-party mode sends inference to Bedrock, but check its
  telemetry settings before relying on it for sensitive work.

## Clean up

Nothing to remove. There is no charge when you're not sending requests, and the Stax credentials
expire on their own.

## References

- [Claude in Amazon Bedrock (Anthropic)](https://platform.claude.com/docs/en/build-with-claude/claude-in-amazon-bedrock)
- [Inference profiles](https://docs.aws.amazon.com/bedrock/latest/userguide/inference-profiles-support.html)
- [Claude Desktop on 3P: Amazon Bedrock](https://claude.com/docs/third-party/claude-desktop/bedrock)
- [Claude Desktop on 3P: in-app configuration](https://claude.com/docs/third-party/claude-desktop/in-app-configuration)
