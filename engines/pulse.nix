{ lib, mkEngine, fetchFromGitHub, cmake }:

mkEngine rec {
  pname = "pulse";
  version = "1.7.3";

  # The repository has hosted several parallel implementations over its life.
  # The current default branch is a Gradle multi-project holding pulse-java,
  # pulse-kotlin, pulse-go *and* pulse-cpp, versioned 2.0.0 but never released.
  #
  # 1.7.3 is the last tagged release and it ships the C++ engine as a plain
  # CMake project under src/main/cpp, which is what we want: a native UCI
  # binary with no JVM at runtime. Pinning the tag rather than master also
  # keeps us off an unreleased tree.
  src = fetchFromGitHub {
    owner = "fluxroot";
    repo = "pulse";
    rev = "cf64c00a883e98506c2c8c90ee67858568753cf2"; # tag 1.7.3
    hash = "sha256-OFNWp1W4nYgoMKBLCROVRdFNTFUdI3zs+XlKqsHWTic=";
  };

  nativeBuildInputs = [ cmake ];

  # No Makefile in the tree, so nothing for stripArchFlags to do; CMake here
  # sets no -march at all.
  stripArchFlags = false;

  postPatch = ''
    # The top-level CMakeLists only knows Linux and Windows and hard-fails on
    # anything else, so Darwin never got a branch. Treat it like the other
    # unixes; PLATFORM_SUFFIX only feeds the CPack archive name.
    substituteInPlace CMakeLists.txt \
      --replace-fail 'message(FATAL_ERROR "Unsupported platform ''${CMAKE_SYSTEM_NAME}")' \
                     'set(PLATFORM_SUFFIX unix)
    set(CPACK_GENERATOR TGZ)'

    # The test subproject downloads googletest at configure time, which the
    # sandbox forbids. We do not run upstream's unit tests anyway - the UCI
    # smoke test is what gates this build.
    substituteInPlace CMakeLists.txt \
      --replace-fail 'add_subdirectory(src/test/cpp)' "" \
      --replace-fail 'enable_testing()' ""

    # Upstream renames the binary to pulse-cpp-<platform>-<version> for its
    # release archives. Keep the plain target name so the install below and
    # mkEngine's smoke test agree on a path.
    substituteInPlace src/main/cpp/CMakeLists.txt \
      --replace-fail 'set_target_properties(pulse PROPERTIES OUTPUT_NAME "pulse-cpp-''${PLATFORM_SUFFIX}-''${pulse_VERSION}")' ""
  '';

  # CMake builds out-of-tree in ./build, so mkEngine's default installPhase
  # (which expects binaries relative to the source root) does not apply.
  installPhase = ''
    runHook preInstall
    install -Dm755 src/main/cpp/pulse "$out/bin/pulse"
    runHook postInstall
  '';

  meta = with lib; {
    description = "Pulse, Phokham Nonava's simple didactic UCI engine, C++ variant (~1800-2000 Elo)";
    homepage = "https://github.com/fluxroot/pulse";
    # Verified against the upstream LICENSE file: verbatim MIT text,
    # "Copyright (C) 2013-2023 Phokham Nonava".
    # https://github.com/fluxroot/pulse/blob/master/LICENSE
    license = licenses.mit;
    maintainers = [ ];
  };
}
