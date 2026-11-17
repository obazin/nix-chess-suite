#!/usr/bin/env bash
# Re-pin the NNUE net of each named engine to the net its pinned source asks
# for.
#
# Usage: update-nets <engine>...
#
# Called by ci/update.sh for every engine, right after nix-update has moved the
# engine's version and before the engine is built. The order matters: an engine
# whose net is tied to its release cannot build at the new version until the
# net pin has followed it.
#
# Engines without a handler below are left alone, so passing the whole tier is
# fine. Prints one line per engine it handles; exits non-zero if any handled
# engine could not be re-pinned, leaving the caller to roll back.
set -euo pipefail

# Caissa names its net in CMakeLists.txt as
#   set(DEFAULT_NEURAL_NET_FILE_NAME <name>.pnn)
# and publishes it as the Caissa-Nets release <name>. The pin lives in
# engines/caissa-net.json, read by engines/caissa.nix.
update_caissa() {
  local pin_file="engines/caissa-net.json"
  local source_path wanted_name current_name url hash

  # Read the net name from the exact source the engine will build from, not
  # from the GitHub API: no rate limit, and it cannot disagree with the src hash.
  source_path=$(nix build --no-link --print-out-paths ".#caissa.src")
  wanted_name=$(sed -n 's/^set(DEFAULT_NEURAL_NET_FILE_NAME \(.*\)\.pnn)$/\1/p' "$source_path/CMakeLists.txt")
  if [ -z "$wanted_name" ]; then
    echo "WARN: caissa: no DEFAULT_NEURAL_NET_FILE_NAME in CMakeLists.txt; net pin left as is"
    return 1
  fi

  current_name=$(jq -r .name "$pin_file")
  if [ "$wanted_name" = "$current_name" ]; then
    echo "net current: caissa ($current_name)"
    return 0
  fi

  url="https://github.com/Witek902/Caissa-Nets/releases/download/${wanted_name}/${wanted_name}.pnn"
  if ! hash=$(nix store prefetch-file --json --hash-type sha256 "$url" | jq -r .hash); then
    echo "WARN: caissa: could not fetch net $wanted_name from $url"
    return 1
  fi

  jq -n --arg name "$wanted_name" --arg hash "$hash" '{ name: $name, hash: $hash }' > "$pin_file"
  echo "net bumped: caissa $current_name -> $wanted_name"
}

failed=0
for engine in "$@"; do
  case "$engine" in
    caissa) update_caissa || failed=1 ;;
    *) ;;
  esac
done
exit "$failed"
