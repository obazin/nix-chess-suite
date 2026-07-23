#!/usr/bin/env bash
# Sourced by the CI build jobs. Sets up the Cloudflare R2 binary cache once and
# defines r2_push(), which signs and uploads store paths as they are built so
# the cache fills progressively (and auth is validated on the first push).
#
# Reads from the environment (CI secrets):
#   R2_ACCESS_KEY_ID / R2_SECRET_ACCESS_KEY  - R2 S3 API token
#   NIX_SIGNING_KEY                          - the cache's private signing key
# Without those (forks / PRs) r2_push is a clean no-op, so builds still work.

_R2_READY=0
if [ -n "${R2_ACCESS_KEY_ID:-}" ] && [ -n "${NIX_SIGNING_KEY:-}" ]; then
  _R2_KEYFILE="$(mktemp)"
  printf '%s' "$NIX_SIGNING_KEY" > "$_R2_KEYFILE"
  trap 'rm -f "$_R2_KEYFILE"' EXIT

  # Nix's S3 store speaks the AWS SDK; R2 takes the same credentials.
  export AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID"
  export AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY"

  # secret-key= makes `nix copy` sign each narinfo on upload, so consumers
  # trust the cache with only the public key.
  _R2_STORE="s3://nix-chess-suite?endpoint=https://6bf171e9f56d6b67c14845000767fda5.r2.cloudflarestorage.com&region=auto&secret-key=${_R2_KEYFILE}"
  _R2_READY=1
fi

# r2_push <store-path>...  — sign + upload the given paths (and their closures).
r2_push() {
  [ "$_R2_READY" = 1 ] || return 0
  [ "$#" -gt 0 ] || return 0
  nix copy --to "$_R2_STORE" "$@" 2>&1 | tail -3 \
    || echo "::warning::R2 push failed for: $*"
}
