## General

- Make demos runnable unchanged in different subscriptions/accounts: derive unique values deterministically (e.g. orgId from the subscription ID) and provide repeatable network allocations when needed; allow explicit overrides.
- Document direct deployment commands; add wrapper scripts only when they provide meaningful value.
- Keep documentation concise: describe what is deployed and noteworthy constraints.
- Don't guess at APIs, because development moves fast; check documentation to verify.
- Don't add bonus features without explicit request; stick to what's asked.
- When asked a question, answer the question; don't make changes.
- If something is unclear, ask to clarify; don't guess.
- Deployments are idempotent: re-running must not error or duplicate resources.
- Tag all supported resources, including demos.
- Don't access a cloud account without explicit approval.

## Project layout

- One folder per sample, each with its own README.

## Networking

- Dual-stack, IPv6-first. Both clouds require IPv4 alongside IPv6; never single-stack IPv4. Don't hardcode addresses.
- IPv6 networks are `/56`; subnets are always `/64` (SLAAC, privacy addresses and neighbour discovery depend on it).
- Don't subnet defensively to "save addresses"; narrower DHCPv6/VPN pools are allocation ranges inside a `/64`, not subnets.

## Python

- Default for simple tasks and API access (e.g. calling an AI endpoint), on either cloud.
- Load configuration from files and environment variables; support CLI arguments as overrides.
- Set argparse parameter defaults in the parameter definition, not in runtime logic.
- Format with [Black](https://black.readthedocs.io/) using default settings.

## Azure

### Naming, tagging and addressing

- Follow Azure CAF [naming](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming) and [tagging](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-tagging); tags use lowercase keys and consistent values.
- Globally-unique names (e.g. DNS-exposed) get an `OrgId` suffix: `0x` + first 4 hex chars of the subscription id.
- Addressing is deterministic from the subscription id: `UlaGlobalId` = first 10 hex chars of `SHA256(subscriptionId)`, split as `gg gggg gggg`. `<vv>` = VNet id, `<ss>` = subnet id (two hex digits each).
  - VNet: `fd<gg>:<gggg>:<gggg>:<vv>00::/56` ([RFC 4193](https://datatracker.ietf.org/doc/html/rfc4193) ULA) and `10.<gg>.<vv>.0/24` (decimal).
  - Subnet: `fd<gg>:<gggg>:<gggg>:<vv><ss>::/64` and a `/26`–`/28` slice of the IPv4 `/24`.
- Known gaps: some features are IPv4-only; `az` CLI cannot create `Icmpv6` NSG rules (use Bicep).

### PowerShell

- PowerShell 7+ and Azure CLI, run inside the devcontainer. Use `az`, not the `Az` module.
- `#!/usr/bin/env pwsh`, `[CmdletBinding()]`, `$ErrorActionPreference = 'Stop'`, comment-based help (`.SYNOPSIS`, `.DESCRIPTION`, `.NOTES`, `.EXAMPLE`).
- `Write-Verbose` on each significant step so `-Verbose` gives a readable trace.
- Every `param()` has an env-var fallback (`$ENV:DEPLOY_*`) and a default.
- Guard `create` calls with a `show` pre-check; removal uses `--yes`.

### Bicep

- Use IPv6-first networking, CIDR functions, and /64 IPv6 subnets.
- Put deployment assets in deployment/ within each project or sample.
- Keep baseline/ as the current desired state for fresh deployments; put explicit, ordered transitions for existing environments in migrations/ (only when requested).
- Use numbered stack folders under deployment/baseline/, each with main.bicep and sibling component modules.
- Keep modules one level deep; orchestrate component modules from the top level.
- Separate optional foundation initialization (RG, networking, monitoring) from workload deployment.
- Accept corporate-provided resource IDs and address allocations; don't assume subscription-level permissions.
- Prefer current, supported Azure resource models and APIs; justify preview dependencies.
- Run standalone `bicep format`, `bicep build`, and `bicep lint` on changed Bicep files.

## AWS

- Python (boto3) for simple tasks and API access; AWS CLI is fine for quick checks in docs.
- CDK for larger infrastructure.
- VPCs use an Amazon-provided IPv6 `/56`; subnets are `/64` slices of it.
- Tags follow [AWS tagging best practices](https://docs.aws.amazon.com/tag-editor/latest/userguide/best-practices-and-strats.html): `Name` (title case, shown in the console), then lowercase, hyphenated keys with a `demo:` prefix, e.g. `demo:owner`, `demo:classification`.
