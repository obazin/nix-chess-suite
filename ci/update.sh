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

# Engines whose upstream tag naming nix-update cannot read unaided. Left to
# itself it takes the highest-sorting tag verbatim, and for these four the
# newest tag is not a release at all — Stockfish publishes dated dev tags
# (stockfish-dev-20260801-c5aef2bf), RubiChess tags its TCEC entries
# (TCECfrc4, TCEC-S21), Reckless tags dev builds (v0.10.0-dev-7300f044) — or
# belongs to a different numbering series: PlentyChess carries both a legacy
# `vX` line and the current `b-vX` one, and the legacy tags sort as newer.
#
# The regex is anchored at both ends because nix-update applies it with
# re.match, which anchors only the start: an unanchored `v([0-9.]+)` would
# happily read "0.10.0" out of "v0.10.0-dev-7300f044" and then pin a tag that
# does not exist. The capture group is the version as the engine file spells
# it, so each file's `rev` template ("sf_${version}", "b-v${version}", …)
# still resolves.
declare -A VERSION_REGEX=(
  [stockfish]='^sf_(.*)$'
  [rubichess]='^([0-9]{8})$'
  [plentychess]='^b-v(.*)$'
  [reckless]='^v([0-9.]+)$'
)

case "$TIER" in
  strong)  ENGINES=("${STRONG[@]}") ;;
  classic) ENGINES=("${CLASSIC[@]}") ;;
  all)     ENGINES=("${STRONG[@]}" "${CLASSIC[@]}") ;;
  *) echo "unknown tier: $TIER" >&2; exit 2 ;;
esac

echo "Updating tier '$TIER': ${ENGINES[*]}"
echo

# Holds a pristine copy of each engine file while nix-update rewrites it, so a
# failed bump can be rolled back (see below).
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

changed=0
for e in "${ENGINES[@]}"; do
  file="engines/${e}.nix"
  [ -f "$file" ] || { echo "skip $e (no $file)"; continue; }

  before=$(sha256sum "$file" | cut -d' ' -f1)
  cp "$file" "$work/${e}.nix"

  # nix-update rewrites version + src hash (and cargoHash for Rust) in place,
  # updating to the newest upstream release/tag. It cannot know about NNUE
  # nets — those are handled separately below.
  #
  # --flake, not --file: engines/*.nix are callPackage-style *functions*, so
  # importing one directly gives nix-update a lambda it cannot call ("function
  # 'anonymous lambda' called without required argument 'fetchurl'"). The flake
  # exposes every engine as packages.<system>.<name>, already applied.
  #
  # --override-filename, because nix-update locates the file to rewrite from
  # builtins.unsafeGetAttrPos "src". For the mkEngine-based engines that
  # resolves to lib/mkEngine.nix — the generic builder re-declares `inherit
  # pname version src` — not to the engine file that actually holds the pin.
  # Naming the file explicitly keeps every rewrite in engines/<name>.nix.
  regex_args=()
  if [ -n "${VERSION_REGEX[$e]:-}" ]; then
    regex_args=(--version-regex "${VERSION_REGEX[$e]}")
  fi

  if nix-update --flake --override-filename "$file" \
       "${regex_args[@]}" --build "$e" 2>/tmp/nixupdate.log; then
    :
  else
    # nix-update writes the new version into the file *before* it prefetches
    # the hash for it, so a failure partway through — an unresolvable tag, a
    # 404 on the new rev — leaves the pin bumped to a version whose hash was
    # never updated. Roll back, so a failed engine is a genuine no-op instead
    # of a broken pin riding into the PR.
    cp "$work/${e}.nix" "$file"
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
