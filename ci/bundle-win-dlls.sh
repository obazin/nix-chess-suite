#!/usr/bin/env bash
# Copy the non-system DLLs that each Windows .exe transitively imports into the
# exe's own folder, so the mingw-cross binaries run on a stock Windows box.
#
# The mingw toolchain dynamically links its C++/GCC/threads runtime
# (libstdc++-6.dll, libgcc_s_seh-1.dll, the mcfgthread/winpthread DLL, …). Those
# are NOT Windows system DLLs and are not in the engine's $out/bin, so a bare
# .exe fails to launch with "libstdc++-6.dll was not found". Rather than hardcode
# names (they differ across C, C++ and Rust engines), inspect each binary with
# objdump and copy exactly what it needs. Membership of the toolchain DLL "pool"
# is the test: a needed DLL that exists in the pool is a runtime lib to bundle; a
# needed DLL absent from the pool is a Windows-provided system DLL (kernel32,
# ws2_32, ucrtbase, …) and is left alone.
#
# Usage: bundle-win-dlls.sh "<pool-search-dirs>" <engine-dir> [<engine-dir> ...]
#   OBJDUMP / CC env vars override the tools (default x86_64-w64-mingw32-{objdump,gcc}).
set -uo pipefail

OBJDUMP="${OBJDUMP:-x86_64-w64-mingw32-objdump}"
CC="${CC:-x86_64-w64-mingw32-gcc}"
POOL_DIRS="${1:?pool search dirs required}"; shift

# name (lowercase) -> full path of every candidate runtime DLL found by scanning
# the given toolchain dirs. This catches the threads runtime; libgcc_s/libstdc++
# live in gcc's own lib dirs and are found via `$CC -print-file-name` instead
# (resolve() below), which is the canonical way to locate a toolchain file.
declare -A POOL
while IFS= read -r f; do
  [ -n "$f" ] || continue
  POOL["$(basename "$f" | tr '[:upper:]' '[:lower:]')"]="$f"
done < <(find $POOL_DIRS -iname '*.dll' 2>/dev/null)
echo "DLL pool: ${#POOL[@]} candidate runtime DLLs (plus \`$CC -print-file-name\`)"

# Locate a runtime DLL by the name objdump reported ($1). Try the scanned pool,
# then ask the compiler for the file in its own search dirs (libgcc_s_seh-1.dll,
# libstdc++-6.dll, libwinpthread-1.dll, …). Prints the path, or nothing if the
# DLL isn't a toolchain file (i.e. it's a Windows system DLL).
resolve() {
  local name="$1" low p
  low="$(echo "$name" | tr '[:upper:]' '[:lower:]')"
  p="${POOL[$low]:-}"
  if [ -n "$p" ]; then echo "$p"; return; fi
  p="$("$CC" -print-file-name="$name" 2>/dev/null)"
  if [ -n "$p" ] && [ "$p" != "$name" ] && [ -e "$p" ]; then echo "$p"; fi
}

# Windows-provided DLLs: never bundle, never warn about.
is_system() {
  case "$1" in
    kernel32.dll|kernelbase.dll|ntdll.dll|user32.dll|gdi32.dll|advapi32.dll|\
    shell32.dll|shlwapi.dll|ole32.dll|oleaut32.dll|ws2_32.dll|mswsock.dll|\
    winmm.dll|msvcrt.dll|ucrtbase.dll|version.dll|comctl32.dll|comdlg32.dll|\
    setupapi.dll|bcrypt.dll|crypt32.dll|secur32.dll|iphlpapi.dll|dbghelp.dll|\
    psapi.dll|powrprof.dll|userenv.dll|ntdll.dll|rpcrt4.dll|api-ms-win-*)
      return 0;;
    *) return 1;;
  esac
}

# Recursively copy $1's non-system imports into dir $2 (deduped on the filesystem).
bundle() {
  local f="$1" dest="$2" dep low src base
  "$OBJDUMP" -p "$f" 2>/dev/null | awk '/DLL Name:/ {print $3}' | while read -r dep; do
    low="$(echo "$dep" | tr '[:upper:]' '[:lower:]')"
    is_system "$low" && continue
    src="$(resolve "$dep")"
    if [ -z "$src" ]; then
      echo "  WARN: $(basename "$f") imports $dep, unresolved by pool/compiler (assuming system DLL)" >&2
      continue
    fi
    base="$(basename "$src")"
    if [ ! -e "$dest/$base" ]; then
      cp "$src" "$dest/$base"; chmod u+w "$dest/$base"
      echo "  + $base -> $(basename "$dest")"
      bundle "$src" "$dest"   # transitive: e.g. libstdc++-6.dll -> libgcc_s/libwinpthread
    fi
  done
}

rc=0
for dir in "$@"; do
  for exe in "$dir"/*.exe; do
    [ -e "$exe" ] || continue
    bundle "$exe" "$dir" || rc=1
  done
done
exit $rc
