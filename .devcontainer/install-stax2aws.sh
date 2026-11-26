#!/usr/bin/env bash
# Install stax2aws from the GitHub release, verifying the published checksum.
# Override the version with STAX2AWS_VERSION (without the leading "v").
set -euo pipefail

version="${STAX2AWS_VERSION:-1.5.6}"
case "$(uname -m)" in
x86_64) arch=amd64 ;;
aarch64 | arm64) arch=arm64 ;;
i?86) arch=386 ;;
*) echo "Unsupported architecture: $(uname -m)" >&2 && exit 1 ;;
esac

name="stax2aws_${version}_linux_${arch}"
base="https://github.com/stax-labs/stax2aws-releases/releases/download/v${version}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

curl -fsSL -o "$tmp/$name.tar.gz" "$base/$name.tar.gz"
curl -fsSL -o "$tmp/checksums.txt" "$base/checksums.txt"
(cd "$tmp" && grep " $name.tar.gz\$" checksums.txt | sha256sum -c -)

tar -xzf "$tmp/$name.tar.gz" -C "$tmp"
sudo install -m 0755 "$tmp/$name/stax2aws" /usr/local/bin/stax2aws
stax2aws --version || true
