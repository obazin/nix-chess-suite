#!/usr/bin/env bash
# Build Windows .exe engines on a native windows-latest runner under MSYS2/UCRT64.
#
# Windows is deliberately NOT built through the Nix flake: too many of these
# hand-rolled Makefiles do not survive mingw cross-compilation, and native
# MSYS2 is far more forgiving. This script mirrors the flake's engine set as
# closely as a shell script can, and drops the results in dist/ for the
# workflow to upload.
#
# It intentionally does the simplest possible thing per engine — clone at the
# rev the .nix file pins, run the Windows/generic make target, copy the .exe.
# Engines that need bespoke handling on Windows are listed explicitly.
set -uo pipefail

DIST="$(pwd)/dist"
WORK="$(pwd)/.win-build"
mkdir -p "$DIST" "$WORK"

# Extract the pinned github owner/repo/rev from an engine's .nix file so the
# Windows build tracks the same commit as the Nix build. Only works for
# fetchFromGitHub-style pins; tarball/bitbucket engines are handled ad hoc.
pin_field() { # <engine> <field>
  grep -oE "$2 = \"[^\"]+\"" "engines/$1.nix" | head -1 | cut -d'"' -f2
}

ok=(); skipped=(); failed=()

build_make() { # <engine> <subdir> <make-args...> :: binary name assumed == engine
  local e="$1" subdir="$2"; shift 2
  local owner repo rev
  owner=$(pin_field "$e" owner); repo=$(pin_field "$e" repo); rev=$(pin_field "$e" rev)
  if [ -z "$owner" ] || [ -z "$rev" ]; then
    echo "skip $e: no github pin (tarball engine — handle manually)"; skipped+=("$e"); return
  fi
  echo "::group::$e ($owner/$repo@${rev:0:8})"
  local d="$WORK/$e"
  rm -rf "$d"
  git clone --quiet "https://github.com/$owner/$repo" "$d" || { failed+=("$e"); echo "::endgroup::"; return; }
  git -C "$d" checkout --quiet "$rev" || { failed+=("$e"); echo "::endgroup::"; return; }
  if ( cd "$d/$subdir" && make "$@" ); then
    # find the freshest .exe the build produced
    local exe
    exe=$(find "$d/$subdir" -name '*.exe' -newer "$d/.git" 2>/dev/null | head -1)
    [ -z "$exe" ] && exe=$(find "$d/$subdir" -maxdepth 1 -name "*$e*" -type f | head -1)
    if [ -n "$exe" ]; then
      cp "$exe" "$DIST/$e.exe"; echo "ok: $e -> dist/$e.exe"; ok+=("$e")
    else
      echo "FAIL $e: built but no .exe found"; failed+=("$e")
    fi
  else
    echo "FAIL $e: make failed"; failed+=("$e")
  fi
  echo "::endgroup::"
}

# --- classic tier (Makefile engines) --------------------------------------
# Net-free, plain make. These are the ones most likely to just work.
build_make fruit        src EXE=fruit
build_make gambitfruit  src
build_make togaii       src
build_make glaurung     src
build_make shallow-blue .   all
build_make stash        src ARCH=generic
build_make rodent-iv    sources/src
build_make discocheck   src

# --- strong tier (need NNUE nets embedded; make download-net works on Windows
#     because the runner HAS network access, unlike the Nix sandbox) --------
build_make stockfish    src build ARCH=x86-64-avx2
build_make berserk      src
build_make obsidian     src
build_make stormphrax   .   EXE=stormphrax

# --- known-manual engines --------------------------------------------------
# CMake, Go, Rust, tarball, or two-stage-net engines are not driven by the
# generic make path above. Track them explicitly so the summary is honest
# about coverage rather than silently omitting them.
for e in pulse cinnamon jazz sjaak2 cheng4 ct800 tucano deeptoga \
         counter zurichess caissa clover seer alexandria \
         rubichess plentychess viridithas reckless lc0 \
         maia-1100 maia-1900; do
  echo "manual: $e not built by generic path (CMake/Go/Rust/tarball/net-two-stage)"
  skipped+=("$e")
done

echo
echo "=== Windows build summary ==="
echo "built:   ${#ok[@]}  (${ok[*]:-none})"
echo "skipped: ${#skipped[@]}"
echo "failed:  ${#failed[@]}  (${failed[*]:-none})"

# A failed generic-path engine is a real regression; a skipped manual engine
# is expected until its bespoke Windows recipe is added. Fail CI only on the
# former.
[ "${#failed[@]}" -eq 0 ]
