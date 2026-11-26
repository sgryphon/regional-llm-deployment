# Regional LLM deployment

Scripted infrastructure-as-code examples for deploying private, region-locked LLM endpoints (Azure AI Foundry, AWS Bedrock) and connecting them to developer tools like opencode, GitHub Copilot, and Claude Code.

## AWS Bedrock, with opencode and Claude Code

Claude Opus, Sonnet and Haiku 5.5 on Amazon Bedrock, processed in Australia through the AU geo
inference profiles (Sydney and Melbourne). Pay per token, nothing to deploy. Sign in with your
existing AWS access (e.g. Stax) and configure opencode, Claude Code or Claude Desktop; a Python
script helps with troubleshooting.

See [aws-bedrock-llm](aws-bedrock-llm/README-aws-bedrock.md).

## Microsoft Foundry, with GitHub Copilot

**DRAFT -- TO BE TESTED**

Model on Regional Provisioned Throughput in Australia East, used from GitHub Copilot Chat as a custom
endpoint. Expensive while deployed (about USD 20 per hour by default).

See [microsoft-foundry-llm](microsoft-foundry-llm/README-microsoft-foundry.md).
