"""Check you can call Claude on Amazon Bedrock in Australia with your current AWS sign-in.

Sends one short prompt using the Anthropic Python SDK, signed with your AWS credentials
(SigV4). Uses only a few tokens of inference. No AWS resources are created.

The default model is the AU geographic inference profile au.anthropic.claude-opus-5-5,
called through bedrock-runtime and processed in Sydney or Melbourne.

  PowerShell:  python check_claude_model.py --profile innovation
"""

import argparse
import logging
import os
import sys

import anthropic
from anthropic import AnthropicBedrock
from botocore.exceptions import BotoCoreError

log = logging.getLogger(__name__)

HINTS = {
    400: "Check the model ID is offered in this region (see the README model table).",
    401: "Your AWS credentials are invalid or expired. Sign in again (e.g. stax2aws login).",
    403: "Your role can't invoke this model, the model isn't enabled in the account, or a "
    "service control policy blocks one of the destination regions. "
    "Ask the account owner.",
    404: "Model not found. Check the model ID and region.",
}


def explain(error: anthropic.APIStatusError) -> str:
    message = f"HTTP {error.status_code}: {error.message}"
    hint = HINTS.get(error.status_code)
    return f"{message}\n{hint}" if hint else message


def main() -> None:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "--region",
        default=os.environ.get("AWS_REGION", "ap-southeast-2"),
        help="AWS region to call (default: AWS_REGION or ap-southeast-2)",
    )
    parser.add_argument(
        "--model",
        default=os.environ.get("DEPLOY_MODEL_ID", "au.anthropic.claude-opus-5-5"),
        help="model or inference profile ID "
        "(default: DEPLOY_MODEL_ID or au.anthropic.claude-opus-5-5)",
    )
    parser.add_argument(
        "--profile",
        default=os.environ.get("AWS_PROFILE"),
        help="AWS named profile for credentials (default: AWS_PROFILE, "
        "else the default credential chain)",
    )
    parser.add_argument(
        "--prompt",
        default="Say hello in five words.",
        help="prompt to send (default: %(default)s)",
    )
    parser.add_argument(
        "-v", "--verbose", action="store_true", help="log progress to stderr"
    )
    args = parser.parse_args()

    logging.basicConfig(
        stream=sys.stderr,
        level=logging.INFO if args.verbose else logging.WARNING,
        format="%(message)s",
    )

    try:
        log.info(
            "Creating Bedrock client for %s (profile: %s)",
            args.region,
            args.profile or "default chain",
        )
        client = AnthropicBedrock(aws_region=args.region, aws_profile=args.profile)

        log.info("Sending test prompt to %s", args.model)
        response = client.messages.create(
            model=args.model,
            max_tokens=1024,
            messages=[{"role": "user", "content": args.prompt}],
        )
    except (BotoCoreError, RuntimeError) as error:
        # The SDK raises RuntimeError when no AWS credentials can be resolved.
        sys.exit(f"AWS credentials problem: {error}\nSign in first (see the README).")
    except anthropic.APIStatusError as error:
        sys.exit(explain(error))
    except anthropic.APIConnectionError as error:
        sys.exit(f"Could not connect to Bedrock in {args.region}: {error}")

    log.info(
        "Stop reason: %s; usage: %s input, %s output tokens",
        response.stop_reason,
        response.usage.input_tokens,
        response.usage.output_tokens,
    )
    if response.stop_reason == "refusal":
        sys.exit(f"{args.model} declined the prompt.")

    text = "".join(block.text for block in response.content if block.type == "text")
    print(f"{args.model}: {text}")


if __name__ == "__main__":
    main()
