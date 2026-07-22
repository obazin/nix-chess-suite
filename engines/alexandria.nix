{ lib, mkEngine, fetchFromGitHub, fetchurl }:

let
  # Alexandria's Makefile has no net downloader: it expects a raw net file
  # `nn.net`, runs it through a native helper (tools/preprocess) to produce
  # `processed.net`, and embeds THAT via INCBIN (-DEVALFILE="processed.net").
  # CI pins the net from the Alexandria-networks releases; the committed
  # net-hash.txt records its sha256. At the v9.0.0 tag net-hash.txt is
  #   b9a20ec5481b47d18151b42e35c46564e2b0b3d0582403aadacbdb529fc478f2
  # which is exactly the sha256 of the net09 release asset, so that is the net
  # this engine revision was trained/tuned against.
  net = fetchurl {
    url = "https://github.com/PGG106/Alexandria-networks/releases/download/net09/nn.net";
    hash = "sha256-uaIOxUgbR9GBUbQuNcRlZOKws9BYJAOq2svbUp/EePI=";
  };
in
mkEngine rec {
  pname = "alexandria";
  version = "9.0.0";

  src = fetchFromGitHub {
    owner = "PGG106";
    repo = "Alexandria";
    rev = "v${version}";
    hash = "sha256-rUuEhXpvv+LU/GKp/h4svBq9yvwYM9reBpOe/qVpkOM=";
  };

  # The default `all` target drives the whole two-stage build itself:
  #   processed.net : nn.net
  #       $(MAKE) -C tools ...     # build the preprocess helper
  #       ./tools/preprocess nn.net processed.net
  #   Alexandria : processed.net $(OBJECTS)
  # So a plain `make` (no explicit target) with nn.net in place builds the
  # helper, runs it, and embeds the result. Command-line variable overrides
  # (CC/CXX from mkEngine) propagate into the `-C tools` sub-make, so the
  # helper is compiled with the same Nix toolchain — i.e. for the build
  # platform, which is what a native aarch64-darwin build needs.
  makeTarget = null;

  # Pin the raw net as nn.net at the source root, which is where the
  # `processed.net : nn.net` rule and the mkEngine EVALFILE=nn.net flag both
  # look. (EVALFILE names the raw input; EVALFILE_PROCESSED=processed.net is
  # what actually gets embedded.)
  evalFile = net;
  evalFileName = "nn.net";

  binaries = [ "Alexandria" ];

  # The built binary is `Alexandria` but the engine (and mkEngine's UCI check)
  # wants `alexandria`. mkEngine's default installPhase installs the cased name
  # and then symlinks the lowercase one, which fails on a case-insensitive
  # filesystem (macOS APFS): the two paths are the same file. Install directly
  # under the lowercase name instead.
  installPhase = ''
    runHook preInstall
    install -Dm755 Alexandria "$out/bin/alexandria"
    runHook postInstall
  '';

  postPatch = ''
    # The Makefile sets `TMPDIR = .tmp` as its object directory. Because TMPDIR
    # is already in the environment (Nix sets it), make re-exports the new
    # value, so the compiler wrapper's mktemp then tries to write into a
    # relative ".tmp" that does not exist yet and the build dies immediately.
    # Rename the Makefile's variable so it stops clobbering the real TMPDIR.
    substituteInPlace makefile --replace-quiet 'TMPDIR' 'OBJDIR'

    # -flto-partition=one is GCC-only and makes clang error out. Plain -flto
    # (kept) works with the Darwin toolchain. On aarch64-darwin the Makefile
    # already selects NATIVE=-mcpu=apple-a14 and, with no `build=` set and no
    # x86 feature macros detected, adds none of the AVX/BMI flags.
    substituteInPlace makefile --replace-fail ' -flto-partition=one' ""

    # std::round is constexpr under libstdc++ (which upstream builds against)
    # but not under clang's libc++, so a compile-time sanity static_assert in
    # nnue.h fails to evaluate. Swap in an equivalent constexpr rounding
    # expression; round(64 * 1.98) == int(126.72 + 0.5) == 127 either way.
    substituteInPlace src/nnue.h \
      --replace-fail 'std::round(L1_QUANT * WEIGHT_CLIPPING)' \
        'int(L1_QUANT * WEIGHT_CLIPPING + 0.5f)'
  '';

  # The object files that embed the net (nnue.o via INCBIN of processed.net)
  # have no Makefile dependency on the `processed.net : nn.net` rule, so a
  # parallel build races and compiles nnue.o before the preprocessor has
  # produced processed.net ("Could not find incbin file 'processed.net'").
  # A serial build honours the left-to-right prerequisite order of the `all`
  # target (processed.net first, then the engine), which is what upstream's
  # .NOTPARALLEL annotation assumes.
  enableParallelBuilding = false;

  meta = with lib; {
    description = "Alexandria, PGG106's NNUE UCI engine; net preprocessed by an in-tree helper then embedded";
    homepage = "https://github.com/PGG106/Alexandria";
    # LICENSE.md is the GPLv3 text. Unlike most engines here, neither the
    # sources nor the licence file carry an "or any later version" grant, so
    # this is GPL-3.0-only.
    license = licenses.gpl3Only;
    maintainers = [ ];
  };
}
