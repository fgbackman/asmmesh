#!/usr/bin/env python3
"""watch.py — has bitchat changed its protocol since the commit asmmesh follows?

asmmesh speaks bitchat's Bluetooth protocol (src/bc_*.s), ported from one commit of
bitchat's public source (github.com/permissionlesstech/bitchat, public domain). If bitchat
changes the wire format, an older asmmesh stops talking to it. This compares the files that
define that format, at the commit asmmesh follows (baseline.json) and at bitchat's main now:

  * every constant that shapes the wire: enum cases (message types, payload types, TLV tags),
    `static let` values (sizes, flags, limits, UUIDs), Noise protocol names
  * which of those files changed at all, and the commits that changed them

    python3 tools/bitchat/watch.py            check (exit 0 nothing changed, 1 changed, 2 error)
    python3 tools/bitchat/watch.py --accept   after asmmesh is updated: follow main's commit now

Needs git and the network (github.com). bitchat is kept in ~/.cache/asmmesh-bitchat.
"""
import json, os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
BASELINE = os.path.join(HERE, "baseline.json")
REPO = "https://github.com/permissionlesstech/bitchat.git"
CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")), "asmmesh-bitchat")

# a constant: `case name = value`, `static let name[: Type] = value`; and "Noise_…" names
CASE = re.compile(r"^\s*case\s+(\w+)\s*=\s*([^/{]+?)\s*(?://.*)?$")
LET = re.compile(r"^\s*(?:public\s+|internal\s+|private\s+|fileprivate\s+)*static\s+let\s+(\w+)\s*(?::\s*[^=]+)?=\s*(.+?)\s*(?://.*)?$")
TYPE = re.compile(r"^\s*(?:public\s+|internal\s+|private\s+|fileprivate\s+|final\s+|indirect\s+)*(?:enum|struct|class|extension)\s+([\w.]+)")
NOISE = re.compile(r'"(Noise_[A-Za-z0-9_]+)"')


def main():
    accept = "--accept" in sys.argv[1:]
    base = json.load(open(BASELINE))
    try:
        head = fetch()
    except subprocess.CalledProcessError as e:
        print("bitchat watch: couldn't reach bitchat's source:", (e.stderr or "").strip()[:300])
        return 2
    if accept:
        base["commit"] = head
        base["date"] = git("log", "-1", "--format=%cs", head).strip()
        json.dump(base, open(BASELINE, "w"), indent=2)
        open(BASELINE, "a").write("\n")
        print("bitchat watch: now following", head[:7], base["date"])
        return 0
    return report(base, head)


def report(base, head):
    old = base["commit"]
    files = base["files"]
    print(f"bitchat watch: asmmesh follows {old[:7]} ({base['date']}); bitchat main is {head[:7]} "
          f"({git('log', '-1', '--format=%cs', head).strip()})")
    if git("rev-parse", old).strip() == head:
        print("No change: bitchat's main is the commit asmmesh follows.")
        return 0
    changed_files = [f for f in files if blob(old, f) != blob(head, f)]
    new_files = [f for f in git("diff", "--name-only", "--diff-filter=A", old, head).split()
                 if re.search(r"(Protocol|Packet|Noise|Announce|Fragment|Message|Payload)\w*\.swift$", f)
                 and "Test" not in f and "/Views/" not in f and f not in files]
    if not changed_files and not new_files:
        print(f"No protocol change: {count(old, head)} commits since, none in the files that "
              "define the wire format.")
        return 0
    worse = False
    for f in changed_files:
        a, b = facts(show(old, f)), facts(show(head, f))
        print(f"\n== {f}" + ("  (DELETED or moved)" if b is None else
                              "  (NEW since then)" if a is None else ""))
        if a is None:
            a = {}
        if b is None:
            worse = True
            continue
        gone = sorted(set(a) - set(b))
        added = sorted(set(b) - set(a))
        moved = sorted(k for k in set(a) & set(b) if a[k] != b[k])
        for k in moved:
            print(f"   CHANGED  {k}: {a[k]}  ->  {b[k]}")
        for k in gone:
            print(f"   REMOVED  {k} = {a[k]}")
        for k in added:
            print(f"   new      {k} = {b[k]}")
        worse |= bool(moved or gone)
        if not (moved or gone or added):
            print("   no constant changed; the code did (check the commits below)")
        for line in git("log", "--format=   %h %cs %s", f"{old}..{head}", "--", f).splitlines()[:8]:
            print(line)
    for f in new_files:
        print(f"\n== {f}  (a NEW protocol file)")
        for k, v in sorted(facts(show(head, f)).items())[:20]:
            print(f"   new      {k} = {v}")
    print()
    if worse:
        print("VERDICT: bitchat changed or removed something asmmesh relies on. Check src/bc_*.s "
              "against it, test with the current bitchat, then run watch.py --accept.")
    else:
        print("VERDICT: bitchat added things (new types or limits) or changed code around the "
              "protocol. asmmesh should still talk to it; read the commits above, then --accept.")
    return 1


def facts(text):
    """{"Type.name": value} for the constants in a Swift file (None if it doesn't exist)"""
    if text is None:
        return None
    out, kind = {}, "?"
    for line in text.splitlines():
        m = TYPE.match(line)
        if m:
            kind = m.group(1)
        m = CASE.match(line) or LET.match(line)
        if m and len(m.group(2)) <= 140:
            key = f"{kind}.{m.group(1)}"
            n = 2
            while key in out:                     # the same name twice (#if testnet / mainnet)
                key = f"{kind}.{m.group(1)}#{n}"
                n += 1
            out[key] = " ".join(m.group(2).split())
        for name in NOISE.findall(line):
            out[f"noise:{name}"] = "used"
    return out


def fetch():
    if not os.path.isdir(os.path.join(CACHE, ".git")):
        os.makedirs(os.path.dirname(CACHE), exist_ok=True)
        subprocess.run(["git", "clone", "-q", "--filter=blob:none", REPO, CACHE],
                       check=True, capture_output=True, text=True)
    git("fetch", "-q", "origin", "main")
    return git("rev-parse", "origin/main").strip()


def git(*args):
    return subprocess.run(["git", "-C", CACHE, *args], check=True, capture_output=True, text=True).stdout


def show(commit, path):
    try:
        return git("show", f"{commit}:{path}")
    except subprocess.CalledProcessError:
        return None


def blob(commit, path):
    try:
        return git("rev-parse", f"{commit}:{path}").strip()
    except subprocess.CalledProcessError:
        return None


def count(old, head):
    return int(git("rev-list", "--count", f"{old}..{head}").strip())


if __name__ == "__main__":
    sys.exit(main())
