# Regional LLM deployment

Scripted infrastructure-as-code examples for deploying private, region-locked LLM endpoints (Azure AI Foundry, AWS Bedrock) and connecting them to developer tools like GitHub Copilot and Claude Code.

**DRAFT -- TO BE TESTED**

## AWS Bedrock, with Claude Code

Claude Opus 5.5 on Amazon Bedrock, processed in Australia through the AU geo inference profile
(Sydney and Melbourne) or in-region in Melbourne. Pay per token, nothing to deploy. Includes a Python
test script and draft Claude Desktop setup.

See [aws-bedrock-llm](aws-bedrock-llm/README-aws-bedrock.md).

## Microsoft Foundry, with GitHub Copilot

Model on Regional Provisioned Throughput in Australia East, used from GitHub Copilot Chat as a custom
endpoint. Expensive while deployed (about USD 20 per hour by default).

See [microsoft-foundry-llm](microsoft-foundry-llm/README-microsoft-foundry.md).
