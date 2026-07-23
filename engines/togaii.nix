{ lib, mkEngine, fetchFromGitHub }:

mkEngine rec {
  pname = "togaii";
  version = "1.2.1a";

  # Thomas Gaksch's original superchessengine.com is offline. Joachim26/TogaII
  # is the only actively maintained import; it carries Toga II 1.2.1a plus
  # extra UCI options (Movetime/Nodes/Depth/Wait For limits) that make it
  # usable as a throttled sparring partner, which is why it is preferred here
  # over a frozen 1.4beta tarball.
  src = fetchFromGitHub {
    owner = "Joachim26";
    repo = "TogaII";
    rev = "40b306a2f46d8c887770d3a4372ac3711d4f8221";
    hash = "sha256-iXAco4xnjRJE0m0zSndu4RbnLLDcMi7ZdtrB/t7UnKA=";
  };

  sourceRoot = "source/src";

  makeTarget = "togaii";

  binaries = [ "togaii" ];

  postPatch = ''
    # Upstream still calls the binary `fruit`, inherited from Fruit 2.1.
    # Rename it so it does not collide with the actual fruit package in a
    # shared profile.
    substituteInPlace Makefile --replace-fail 'EXE = fruit' 'EXE = togaii'

    # `ld -s` is obsolete on Darwin and errors on recent cctools.
    substituteInPlace Makefile --replace-fail 'LDFLAGS += -s' '# LDFLAGS += -s'
  '';

  meta = with lib; {
    description = "Toga II, Thomas Gaksch's Fruit 2.1 derivative, modified for human-speed play";
    homepage = "https://www.chessprogramming.org/Toga";
    # This repo ships no LICENSE file. The grant is inherited: Toga II is a
    # direct derivative of Fruit 2.1, which is GPL-2.0-or-later, so it cannot
    # lawfully be distributed under narrower terms. Gaksch's own Toga II
    # 1.4beta5c release notice states this explicitly ("Toga II 1.4beta5c
    # based on Fruit 2.1 by Fabien Letouzey. This program is free software;
    # ... either version 2 of the License, or (at your option) any later
    # version"), preserved in the LICENSE file that ships with DeepToga.
    # Also recorded in docs/excluded.md.
    license = licenses.gpl2Plus;
    maintainers = [ ];
  };
}
