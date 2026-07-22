{ lib, stdenv, mkEngine, fetchFromGitHub }:

mkEngine rec {
  pname = "rodent-iv";
  version = "0.33";

  # Pawel Koziol's Rodent IV, the community repo. Dead since April 2021, so
  # this rev is effectively the final state of the project.
  #
  # Do NOT bump this to `nescitus/Rodent_II` or `nescitus/Rodent_III`: those
  # are separate, earlier repositories under GPL-2.0, not the same project
  # and not the same licence.
  src = fetchFromGitHub {
    owner = "nescitus";
    repo = "rodent-iv";
    rev = "e8d84c8c8c189a1cf4eb27c578fc573af3b916d2";
    hash = "sha256-kozpkcEd3KRAqLkDNL+u+cC+yecCCap1G0S7S5Uma28=";
  };

  sourceRoot = "source/sources";

  # Rodent's personality files are most of the point of the engine: each is a
  # hand-tuned parameter set imitating a named player, and `basic.ini` is the
  # index the engine reads at startup to build its `Personality` UCI option.
  # Ship them, plus the opening books, next to the binary.
  dataFiles = [ "../books" "../personalities" ];

  postPatch = ''
    # Rodent locates its data directory ("Rodent home") at runtime. The upstream
    # logic is broken for our purposes in two independent ways:
    #
    #   1. The __APPLE__ branch of SetRodentHomeDir() is an empty stub with an
    #      `#error something should be done here` comment left in. On macOS the
    #      home directory therefore stays "" and Rodent looks for
    #      "personalities/basic.ini" relative to the current directory, which
    #      under a GUI is essentially never right.
    #   2. The generic POSIX branch derives the directory from
    #      readlink("/proc/self/exe"), which does not exist on Darwin and is
    #      the wrong answer under Nix anyway: the data lives in $out/share,
    #      not next to the binary in $out/bin.
    #
    # Note that the Makefile's -DBOOKPATH is dead code in this revision -- no
    # source file references BOOKPATH -- so pointing that at $out would do
    # nothing. Patch the actual lookup instead: fall back to a compiled-in
    # RODENT_DATADIR, still overridable at runtime via $RODENT4HOME.
    substituteInPlace src/rodenthome.cpp \
      --replace-fail '#elif defined (__APPLE__)' '#elif 0 // Nix: use the generic POSIX branch below'

    substituteInPlace src/rodenthome.cpp \
      --replace-fail 'readlink("/proc/self/exe", exe_path, sizeof(exe_path));' \
                     'snprintf(exe_path, sizeof(exe_path), "%s", RODENT_DATADIR);' \
      --replace-fail "*(strrchr(exe_path, '/') + 1) = '\0';" \
                     "/* Nix: RODENT_DATADIR is already a directory */"
  '';

  # The upstream Makefile hardcodes CC=g++, links with the obsolete `ld -s`
  # (fatal on recent cctools) and writes the binary to ../mac/rodentIV. One
  # compiler invocation is clearer than patching four things.
  buildPhase = ''
    runHook preBuild

    $CXX -std=c++14 -O3 -DNDEBUG -w -fno-rtti -finline-functions \
      -DRODENT_DATADIR='"'"$out/share/${pname}/"'"' \
      ${lib.optionalString (!stdenv.hostPlatform.isx86)
        # USE_MM_POPCNT pulls in <nmmintrin.h> / _mm_popcnt_u64, which only
        # exists on x86. rodent.h gates it behind this macro.
        "-DNO_MM_POPCNT"} \
      src/*.cpp -o ${pname} -lm ${lib.optionalString (!stdenv.hostPlatform.isDarwin) "-lpthread"}

    runHook postBuild
  '';

  binaries = [ "rodent-iv" ];

  # The stock smoke test only proves the handshake. Rodent will happily answer
  # `uciok` with no personalities at all -- it just prints a warning and plays
  # with built-in defaults -- so also assert that it actually resolved
  # $out/share/rodent-iv/personalities/basic.ini.
  installCheckPhase = ''
    runHook preInstallCheck
    out_txt=$(printf 'uci\nquit\n' | "$out/bin/${pname}" | tr -d '\r')
    echo "$out_txt" | grep -q uciok || {
      echo "FAIL: ${pname} did not answer 'uciok' to a uci handshake" >&2
      echo "$out_txt" >&2
      exit 1
    }
    if echo "$out_txt" | grep -q "basic.ini"; then
      echo "FAIL: ${pname} could not find its personality files" >&2
      echo "$out_txt" >&2
      exit 1
    fi
    echo "$out_txt" | grep -q 'option name Personality' || {
      echo "FAIL: ${pname} did not advertise the Personality option" >&2
      echo "$out_txt" >&2
      exit 1
    }
    echo "ok: ${pname} speaks UCI and found its personalities"
    runHook postInstallCheck
  '';

  meta = with lib; {
    description = "Rodent IV, Pawel Koziol's personality-driven UCI engine derived from Sungorus";
    homepage = "https://github.com/nescitus/rodent-iv";
    # LICENSE in the repo is the GPLv3 text; every source file carries the
    # "either version 3 of the License, or (at your option) any later version"
    # header, hence gpl3Plus rather than plain gpl3.
    license = licenses.gpl3Plus;
    maintainers = [ ];
  };
}
