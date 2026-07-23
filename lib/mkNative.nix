# Turn a portable engine derivation into a "native" one: tuned for the CPU that
# BUILDS it (-march=native / target-cpu=native) instead of the reproducible,
# portable baseline. Such a binary uses whatever instructions the build CPU has
# (AVX-512, BMI2, …) and is only valid on that CPU — so it must be built locally
# and never substituted from or pushed to a shared cache.
#
#   isRust : the engine is built with buildRustPackage (needs RUSTFLAGS, not
#            NIX_CFLAGS_COMPILE).
#
# The cc-wrapper reads NIX_CFLAGS_COMPILE for every compile regardless of build
# system (Make, CMake, custom), so setting it once covers all C/C++ engines.
# NIX_ENFORCE_NO_NATIVE="" disables the wrapper's default stripping of
# -march=native (which exists for reproducibility).

isRust: drv:
drv.overrideAttrs (old: {
  pname = "${old.pname}-native";

  # A native binary is CPU-specific: never pull it from a cache built on another
  # CPU, and never let CI push it. Force a local build.
  allowSubstitutes = false;
  preferLocalBuild = true;

  env = (old.env or { }) // (
    if isRust then {
      RUSTFLAGS = ((old.env or { }).RUSTFLAGS or "") + " -C target-cpu=native";
    } else {
      NIX_ENFORCE_NO_NATIVE = "";
      NIX_CFLAGS_COMPILE =
        ((old.env or { }).NIX_CFLAGS_COMPILE or "") + " -march=native -mtune=native";
    }
  );

  meta = (old.meta or { }) // {
    description = (old.meta.description or "${old.pname}")
      + " (native: tuned for the building CPU, local build only)";
  };
})
