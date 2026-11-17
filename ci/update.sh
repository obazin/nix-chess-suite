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

# Holds a pristine copy of each engine's files while they are rewritten, so a
# failed bump can be rolled back (see below).
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Everything echoed to stdout lands in the PR body (update.yml tees it), so
# failures are reported there too, not only on stderr where nobody looks.
changed=0
failed=()
for engine in "${ENGINES[@]}"; do
  file="engines/${engine}.nix"
  [ -f "$file" ] || { echo "skip $engine (no $file)"; continue; }

  # The engine file plus its net pin, if it has one (see ci/update-nets.sh).
  pinned_files=("$file")
  [ -f "engines/${engine}-net.json" ] && pinned_files+=("engines/${engine}-net.json")

  before=$(cat "${pinned_files[@]}" | sha256sum | cut -d' ' -f1)
  mkdir -p "$work/$engine"
  cp "${pinned_files[@]}" "$work/$engine/"

  # nix-update rewrites version + src hash (and cargoHash for Rust) in place,
  # updating to the newest upstream release/tag.
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
  #
  # No --build here: an engine whose net is tied to its release cannot build
  # at the new version until update-nets has re-pinned the net, so the build
  # is a separate step after that.
  regex_arguments=()
  if [ -n "${VERSION_REGEX[$engine]:-}" ]; then
    regex_arguments=(--version-regex "${VERSION_REGEX[$engine]}")
  fi

  failed_step=""
  if ! nix-update --flake --override-filename "$file" \
       "${regex_arguments[@]}" "$engine" 2>"$work/log"; then
    failed_step="nix-update"
  elif ! update-nets "$engine" 2>"$work/log"; then
    failed_step="net refresh"
  elif ! nix build ".#$engine" --no-link -L 2>"$work/log"; then
    failed_step="build"
  fi

  if [ -n "$failed_step" ]; then
    # nix-update writes the new version into the file *before* it prefetches
    # the hash for it, and a net refresh or build can fail after the version
    # moved. Roll back every pinned file, so a failed engine is a genuine
    # no-op instead of a broken pin riding into the PR.
    for pinned in "${pinned_files[@]}"; do
      cp "$work/$engine/$(basename "$pinned")" "$pinned"
    done
    echo "WARN: $engine: $failed_step failed; left pinned (last log lines below, full log in the workflow run)"
    tail -n 20 "$work/log" | sed 's/^/    /'
    sed 's/^/    /' "$work/log" >&2 || true
    failed+=("$engine")
    continue
  fi

  after=$(cat "${pinned_files[@]}" | sha256sum | cut -d' ' -f1)
  if [ "$before" != "$after" ]; then
    echo "bumped: $engine"
    changed=$((changed+1))
  else
    echo "current: $engine"
  fi
done

echo
echo "Done. $changed engine(s) changed."
if [ "${#failed[@]}" -gt 0 ]; then
  echo "FAILED, left at their old pins: ${failed[*]}"
fi
