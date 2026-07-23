#!/usr/bin/env bash
# Sign and push built store paths to the project's Cloudflare R2 bucket, which
# serves as the Nix binary cache. Called by the CI build jobs with the list of
# store paths that built successfully this run.
#
# Requires in the environment (CI secrets):
#   R2_ACCESS_KEY_ID / R2_SECRET_ACCESS_KEY  - R2 S3 API token
#   NIX_SIGNING_KEY                          - the cache's private signing key
# A no-op (clean exit) if the credentials are absent, so forks/PRs without the
# secrets still build without trying to push.
set -uo pipefail

[ "$#" -gt 0 ] || { echo "r2-push: nothing to push"; exit 0; }
if [ -z "${R2_ACCESS_KEY_ID:-}" ] || [ -z "${NIX_SIGNING_KEY:-}" ]; then
  echo "r2-push: R2/signing secrets not set — skipping push"
  exit 0
fi

# R2 bucket + account (non-secret).
R2_BUCKET="nix-chess-suite"
R2_ACCOUNT="6bf171e9f56d6b67c14845000767fda5"
STORE="s3://${R2_BUCKET}?endpoint=https://${R2_ACCOUNT}.r2.cloudflarestorage.com&region=auto"

keyfile="$(mktemp)"
trap 'rm -f "$keyfile"' EXIT
printf '%s' "$NIX_SIGNING_KEY" > "$keyfile"

# Nix's S3 store speaks the AWS SDK; R2 accepts the same credentials.
export AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY"

# Sign the whole closure, then copy it (signatures let consumers trust the
# cache with only the public key).
echo "r2-push: signing $# path(s) and their closures"
nix store sign --key-file "$keyfile" --recursive "$@"

echo "r2-push: copying to R2"
nix copy --to "$STORE" "$@"
echo "r2-push: done"
