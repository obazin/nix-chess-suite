#!/usr/bin/env bash
# Bump pinned engine revisions and their NNUE nets.
#
# Invoked by .github/workflows/update.yml as `nix run .#update -- --tier <t>`.
# Exposed as a flake app so it runs in a pinned environment with nix-update,
# jq and friends on PATH.
#
# Policy (see README): the strong tier moves constantly and is bumped nightly;
# the classic tier is frozen upstream and is NOT chased here — it is covered
# by the weekly toolchain-drift build in build.yml. `--tier classic` is
# therefore a deliberate, rarely-used override.
set -euo pipefail

TIER="strong"
while [ $# -gt 0 ]; do
  case "$1" in
    --tier) TIER="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

# Engines eligible for automated bumping, by tier. The classic tier is
# intentionally sparse: only engines that still tag releases belong here.
STRONG=(stockfish obsidian berserk stormphrax caissa clover seer alexandria
        rubichess plentychess viridithas reckless lc0)
CLASSIC=(stash cheng4 counter)   # the few classic engines still cutting releases

case "$TIER" in
  strong)  ENGINES=("${STRONG[@]}") ;;
  classic) ENGINES=("${CLASSIC[@]}") ;;
  all)     ENGINES=("${STRONG[@]}" "${CLASSIC[@]}") ;;
  *) echo "unknown tier: $TIER" >&2; exit 2 ;;
esac

echo "Updating tier '$TIER': ${ENGINES[*]}"
echo

changed=0
for e in "${ENGINES[@]}"; do
  file="engines/${e}.nix"
  [ -f "$file" ] || { echo "skip $e (no $file)"; continue; }

  before=$(sha256sum "$file" | cut -d' ' -f1)

  # nix-update rewrites version + src hash (and cargoHash for Rust) in place.
  # --version=branch follows the default branch; for tag-tracking engines it
  # picks the newest tag. It cannot know about NNUE nets — those are handled
  # separately below.
  if nix-update --file "$file" --build "$e" 2>/tmp/nixupdate.log; then
    :
  else
    echo "WARN: nix-update failed for $e (see log); leaving pinned" >&2
    sed 's/^/    /' /tmp/nixupdate.log >&2 || true
    continue
  fi

  after=$(sha256sum "$file" | cut -d' ' -f1)
  if [ "$before" != "$after" ]; then
    echo "bumped: $e"
    changed=$((changed+1))
  else
    echo "current: $e"
  fi
done

# NNUE nets are pinned independently of the engine version and are the part
# that actually rotates for the strong tier. update-nets.sh re-reads each
# engine's net-name file (evaluate.h, network.txt, net-hash.txt, ...) and
# re-pins the fetchurl. Kept as a separate step because the discovery logic
# is per-engine.
if [ "$TIER" != "classic" ] && [ -x ci/update-nets.sh ]; then
  echo
  echo "Refreshing NNUE net pins..."
  ci/update-nets.sh "${ENGINES[@]}" || echo "WARN: net refresh reported issues" >&2
fi

echo
echo "Done. $changed engine file(s) changed."
