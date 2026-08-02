{ lib, fetchurl }:

# Lc0 networks, packaged apart from the engines that run them.
#
# engines/lc0.nix ships executables only, for the reason set out in its header:
# the right net is a function of backend, VRAM and time control, and pinning one
# for everyone means shipping a large file that is wrong for most people. The
# answer is not to enumerate the combinations — four backends times three sizes
# is twelve packages that still do not cover the space, since within one backend
# the right net depends on the card. It is to keep the two axes separate and let
# them compose: `lc0-metal.withNet lc0-net-t1-512` materialises exactly the pair
# you asked for, and nothing else has to exist.
#
# These are deliberately NOT in the engine registry, so they stay out of
# `checks` and out of the chess-engines-all bundle. CI never fetches them, and
# `nix profile install .#default` does not hand anyone ~870 MB of weights they
# did not ask for. Fetch is by URL and SRI hash, so a net is content-addressed
# like any other pin.
#
# `architecture` is the field that makes the compatibility guard in
# engines/lc0.nix work, and it is not cosmetic: lc0's OpenCL backend accepts
# only classical/SE-ResNet networks with RELU, so handing it an attention-body
# net is a hard failure at startup. Every value below was read off
# `lc0 describenet`, not guessed from the filename. See docs/lc0-networks.md.

let
  baseUrl = "https://storage.lczero.org/files/networks-contrib";

  networks = {
    "744706" = {
      file = "744706.pb.gz";
      hash = "sha256-Qw+awinq/BtMMFuiCt9+S0xdego/AyMHOYrI40m3Isg=";
      architecture = "se-resnet";
      description = "SE-ResNet 10x128, 6.1 MB — smallest useful net, and OpenCL-safe";
    };
    "ld2" = {
      file = "LD2.pb.gz";
      hash = "sha256-BLohTOEnfs6beB6KHsHvLdTY8pT0lsyOb+8yXymNtgo=";
      architecture = "se-resnet";
      description = "SE-ResNet 10x128, 6.1 MB — sibling of 744706, OpenCL-safe";
    };
    "sv-t60" = {
      file = "sv-t60-3010.pb.gz";
      hash = "sha256-LlAsOU5eVXZkaUZCDC12P2MWW4lKPeqaFdMv7QWwewQ=";
      architecture = "se-resnet";
      description = "SE-ResNet 30x384, 131 MB — strongest OpenCL-compatible net";
    };
    "t1-256" = {
      file = "t1-256x10-distilled-swa-2432500.pb.gz";
      hash = "sha256-vCemyuitNvK5qApq2dq7DW/aJbHn9IGnm8NZ4U9WNAY=";
      architecture = "attention";
      description = "attention 10x8h distilled, 35.4 MB — the practical CPU default";
    };
    "t1-512" = {
      file = "t1-512x15x8h-distilled-swa-3395000.pb.gz";
      hash = "sha256-H9sVGeWwLgPx2SAeyOuV9kDjLMZFmk8UwOq2iQ3Al+g=";
      architecture = "attention";
      description = "attention 15x8h distilled, 142.8 MB — the practical GPU default";
    };
    "bt3" = {
      file = "BT3-768x15x24h-swa-2790000.pb.gz";
      hash = "sha256-4wZ3V9H8LfxmlHsh0VrODO30xUJU/B3oPXfDeKPouOE=";
      architecture = "attention";
      description = "attention multihead 15x24h, 182.1 MB — discrete GPU";
    };
    "bt4" = {
      file = "BT4-1024x15x32h-swa-6147500-policytune-332.pb.gz";
      hash = "sha256-5q2p1sSnab+rOqCEjYLK64CapF+D5sYF/FijHSG91hg=";
      architecture = "attention";
      description = "attention multihead 15x32h, 364.9 MB — strongest here, discrete GPU only";
    };
  };

  mkNet = short: net:
    (fetchurl {
      # Named for the attribute rather than the upstream filename, so the store
      # path says which net this is without decoding a training-run name.
      name = "lc0-net-${short}.pb.gz";
      url = "${baseUrl}/${net.file}";
      inherit (net) hash;
      meta = {
        description = "Lc0 network: ${net.description}";
        homepage = "https://lczero.org/play/networks/";
        # The weights are released by the LCZero project under the GPL alongside
        # the engine; see docs/lc0-networks.md for provenance of each file.
        license = lib.licenses.gpl3Only;
        platforms = lib.platforms.all;
      };
    }).overrideAttrs (_: {
      passthru = {
        shortName = short;
        upstreamFile = net.file;
        inherit (net) architecture;
      };
    });
in
lib.mapAttrs' (short: net: lib.nameValuePair "lc0-net-${short}" (mkNet short net))
  networks
