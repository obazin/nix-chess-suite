#!/usr/bin/env python3
"""Regenerate Engines.md from the flake's engine metadata plus the curated
strength/algorithm table below. Run from the repo root:  python3 ci/gen-engines-md.py
Source links and platforms come from each engine's meta; Elo and eval method
are curated here (update when adding engines). WINDOWS is the set of engines
that currently cross-compile — refresh from the latest CI Windows job."""
import json, subprocess, sys

# Engines that currently cross-compile to Windows (from the CI windows job).
WINDOWS = set("""akimbo berserk bit-genie blackmarlin carp clover ct800 deepov
demolito fabchess glaurung laser loki minic napoleon obsidian reckless rodent-iv
rustic senpai shallow-blue stash stockfish svart velvet vice viridithas wahoo
weiss willow wukong wyldchess xiphos""".split())

# (approx Elo, eval/algorithm, language). Elo is ballpark (CCRL/TCEC/class).
DATA = {
 "stockfish":(3650,"NNUE","C++"),"lc0":(3500,"NN + MCTS","C++"),
 "lc0-t1-256":(3300,"NN + MCTS","C++"),"minic":(3690,"NNUE","C++"),
 "berserk":(3616,"NNUE","C"),"obsidian":(3618,"NNUE","C++"),
 "plentychess":(3611,"NNUE","C++"),"caissa":(3610,"NNUE","C++"),
 "rubichess":(3602,"NNUE","C"),"viridithas":(3602,"NNUE","Rust"),
 "alexandria":(3602,"NNUE","C++"),"clover":(3597,"NNUE","C++"),
 "seer":(3585,"NNUE","C++"),"igel":(3577,"NNUE","C++"),
 "stormphrax":(3535,"NNUE","C++"),"heimdall":(3500,"NNUE","Nim"),
 "velvet":(3500,"NNUE","Rust"),"blackmarlin":(3450,"NNUE","Rust"),
 "arasan":(3450,"NNUE","C++"),"reckless":(3420,"NNUE","Rust"),
 "avalanche":(3400,"NNUE","Zig"),"marvin":(3300,"NNUE","C++"),
 "carp":(3300,"NNUE","Rust"),"akimbo":(3300,"NNUE","Rust"),
 "xiphos":(3300,"HCE","C"),"laser":(3280,"HCE","C++"),
 "leorik":(3200,"NNUE","C#"),"texel":(3200,"NNUE","C++"),
 "vajolet2":(3200,"NNUE","C++"),"svart":(3200,"NNUE","Rust"),
 "gull":(3150,"HCE","C++"),"winter":(3100,"LogReg eval","C++"),
 "lynx":(3100,"HCE","C#"),"wahoo":(3082,"HCE","Rust"),
 "stash":(3050,"NNUE","C"),"weiss":(3000,"HCE","C"),
 "counter":(3000,"NNUE","Go"),"senpai":(2950,"HCE","C++"),
 "fabchess":(2950,"HCE","Rust"),"combusken":(2950,"HCE","Go"),
 "amoeba":(2900,"HCE","D"),"demolito":(2900,"HCE","C"),
 "rodent-iv":(2900,"HCE","C++"),"bit-genie":(2870,"NNUE","C++"),
 "zurichess":(2800,"HCE","Go"),"glaurung":(2790,"HCE","C++"),
 "exchess":(2770,"HCE","C++"),"cheng4":(2750,"NNUE","C++"),
 "deeptoga":(2750,"HCE","C++"),"discocheck":(2700,"HCE","C++"),
 "togaii":(2680,"HCE","C++"),"gambitfruit":(2670,"HCE","C++"),
 "wyldchess":(2600,"HCE","C"),"maxima2":(2600,"HCE","C++"),
 "blunder":(2600,"HCE","Go"),"willow":(2600,"NNUE","C++"),
 "loki":(2490,"HCE","C++"),"tucano":(2450,"HCE","C"),
 "napoleon":(2400,"HCE","C++"),"jazz":(2300,"HCE","C++"),
 "sjaak2":(2300,"HCE","C++"),"sayuri":(2250,"HCE","C++"),
 "fruit":(2200,"HCE","C++"),"dumb":(2200,"HCE","D"),
 "ct800":(2150,"HCE","C"),"cinnamon":(2100,"HCE","C++"),
 "deepov":(2000,"HCE","C++"),"pulse":(1950,"HCE","C++"),
 "shallow-blue":(1900,"HCE","C++"),"vice":(1900,"HCE","C"),
 "rustic":(1800,"HCE","Rust"),"wukong":(1700,"HCE","C"),
 "mister-queen":(1700,"HCE","C"),
}
for r in range(1100,2000,100): DATA[f"maia-{r}"]=(r,"Human-like NN","C++ (Lc0)")

def meta():
    expr = """
      let
        f = builtins.getFlake (toString ./.);
        p = f.packages.aarch64-darwin;
        keep = n: ! (builtins.elem n [ "default" "all" ])
                  && builtins.substring 0 4 n != "win-";
        ns = builtins.filter keep (builtins.attrNames p);
        m = n: {
          homepage = p.${n}.meta.homepage or "";
          platforms = p.${n}.meta.platforms or [];
          license = p.${n}.meta.license.spdxId
                      or (p.${n}.meta.license.shortName or "");
        };
      in builtins.listToAttrs (map (n: { name = n; value = m n; }) ns)
    """
    out = subprocess.check_output(["nix","eval","--impure","--json","--expr",expr])
    return json.loads(out)

def plat(name,m):
    ps=set(m["platforms"])
    parts=[]
    if any(p.endswith("-linux") for p in ps): parts.append("Linux")
    if "aarch64-darwin" in ps: parts.append("macOS")
    if name in WINDOWS: parts.append("Windows")
    return ", ".join(parts) or "—"

def main():
    M=meta()
    rows=[]
    for n,m in M.items():
        elo,algo,lang=DATA.get(n,(0,"?","?"))
        rows.append((n,elo,algo,lang,plat(n,m),m["license"] or "—",m["homepage"]))
    rows.sort(key=lambda r:(-r[1],r[0]))
    L=["# Engine catalogue","",
       "All engines in this collection, with an **approximate** playing strength, the",
       "platforms they build on, their main evaluation method, and a link to source.","",
       "> Elo figures are rough (CCRL/TCEC where available, engine class otherwise) — a",
       "> ballpark, not a ranking. Maia strengths are the *target human rating* each net",
       "> emulates, not engine strength. Windows coverage is still expanding (cross-",
       "> compiled where shown); Linux and macOS (arm64) are fully verified.","",
       "| Engine | ~Elo | Eval / algorithm | Language | Platforms | License | Source |",
       "|---|---:|---|---|---|---|---|"]
    for n,elo,algo,lang,pl,lic,home in rows:
        L.append(f"| {n} | {elo or '—'} | {algo} | {lang} | {pl} | {lic} | {'[link]('+home+')' if home else '—'} |")
    L+=["","*Generated by `ci/gen-engines-md.py` from the flake metadata; rerun after adding engines.*"]
    open("Engines.md","w").write("\n".join(L)+"\n")
    print(f"wrote Engines.md ({len(rows)} engines)")

if __name__=="__main__": main()
