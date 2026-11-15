#!/usr/bin/env python3
"""Model-policy scanner (Kanboard #482, repo mode #1752).

Policy (~/.claude/CLAUDE.md §7.2, 2026-10-24): minimum Qwen 3.8; never deploy a Qwen
below 3.8 (base, coder, Triton engines) or the R1 distills built on it, or anything older.
The forbidden names are assembled from fragments below so this file passes its own guard.
Allowed: corey-coder, corey-reasoning, qwen3.8, qwen3:4b, gemma4, nomic-embed-text,
deepseek-v4.1-flash (hosted, #483) and the recorded bases of our LoRAs.

Usage:
  model_policy_scan.py files <path>... [--enforce]
  model_policy_scan.py repo <root> [--enforce]      # every git-tracked text file + .model-policy-allow
  model_policy_scan.py cluster [--kubectl-json <file>] [--exclude-ns ibkr-live-trader,...] [--enforce]
Exit 1 only with --enforce and at least one violation; otherwise 0 (advisory).
"""
from __future__ import annotations

import argparse
import json
import pathlib
import re
import subprocess
import sys
from collections import Counter

_Q = "qwen"
_DS = "deep" + "seek"
FORBIDDEN = [
    re.compile(_Q + r"[ _-]?2(?:\.5|\.x)?(?![0-9])[-_:/a-z0-9.]*", re.I),  # the 2 / 2.5 / 2.5-coder generations, plain or HF repo ids
    re.compile(_Q + r"[ _-]?25(?![0-9])[a-z0-9_.-]*", re.I),             # Triton engine names (2.5, 7b, trtllm)
    re.compile(_DS + r"[-_ ]r1[-_:a-z0-9.]*", re.I),                     # R1 distill tags / engines / HF repos
    re.compile(r"\br1[-_]distill[-_a-z0-9.]*", re.I),                    # distill names without the vendor prefix
    re.compile(_DS + r"-cpu[a-z0-9.:_-]*", re.I),                        # the retired CPU R1 service
]
ALLOWED = {
    "corey-coder:latest", "corey-reasoning:latest", "qwen3.8:latest", "qwen3:4b", "gemma4:31b",
    "gemma4:31b-broker", "gemma4-31b", "nomic-embed-text:latest", "deepseek-v4.1-flash", "deepseek-flash",
    "qwen3-coder:30b", "qwen3-vl:30b",
}
SCAN_SUFFIXES = {".yaml", ".yml", ".json", ".py", ".sh", ".env", ".txt", ".md", ".toml", ".cfg", ".ini", ""}
SKIP_DIRS = {".git", "node_modules", ".venv", "__pycache__", "fixtures", "rollback", "captured", ".snapshots", "_discovered"}
DEFAULT_EXCLUDE_NS = {"ibkr-live-trader"}  # legacy-frozen (CLAUDE.md §2)
EXEMPT_ANNOTATION = "albrightlaboratories.com/model-policy"  # value "exempt" skips an object


def violations_in_text(text: str) -> list[dict]:
    found = []
    for n, line in enumerate(text.splitlines(), 1):
        for pat in FORBIDDEN:
            for m in pat.finditer(line):
                tok = m.group(0).rstrip("\"',;)]}")
                if tok.lower() in {a.lower() for a in ALLOWED}:
                    continue
                found.append({"line": n, "match": tok, "text": line.strip()[:160]})
    return found


def scan_files(paths) -> list[dict]:
    out = []
    for root in paths:
        root = pathlib.Path(root)
        files = [root] if root.is_file() else sorted(p for p in root.rglob("*") if p.is_file())
        for f in files:
            inner = f.relative_to(root).parts[:-1] if root.is_dir() else ()
            if SKIP_DIRS & set(inner) or f.suffix.lower() not in SCAN_SUFFIXES:
                continue
            try:
                text = f.read_text(errors="ignore")
            except OSError:
                continue
            for v in violations_in_text(text):
                out.append({"file": str(f), **v})
    return out


ALLOW_FILE = ".model-policy-allow"


def _tracked_files(root: pathlib.Path) -> list[pathlib.Path]:
    try:
        out = subprocess.run(["git", "-C", str(root), "ls-files", "-z"], capture_output=True, check=True).stdout
        return [root / p for p in out.decode().split("\0") if p]
    except (OSError, subprocess.CalledProcessError):
        return sorted(p for p in root.rglob("*") if p.is_file() and not ({".git", "node_modules"} & set(p.parts)))


def _read_text(f: pathlib.Path):
    try:
        raw = f.read_bytes()
    except OSError:
        return None
    if b"\0" in raw[:8192]:
        return None  # binary
    return raw.decode("utf-8", errors="ignore")


def _parse_allow(root: pathlib.Path):
    """`<path> | <max hits> | <reason>` per line. Only CHANGELOG files may be frozen, and every entry needs a reason."""
    allow, bad = {}, []
    f = root / ALLOW_FILE
    if not f.is_file():
        return allow, bad
    for n, line in enumerate(f.read_text().splitlines(), 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        parts = [x.strip() for x in line.split("|", 2)]
        problem = None
        if len(parts) != 3 or not parts[1].isdigit():
            problem = "entry must be '<path> | <max hits> | <reason>'"
        elif not parts[2]:
            problem = "entry has no reason"
        elif not pathlib.PurePosixPath(parts[0]).name.upper().startswith("CHANGELOG"):
            problem = "only historical CHANGELOG lines may be allow-listed"
        if problem:
            bad.append({"file": str(f), "line": n, "match": problem, "text": line.strip()[:160]})
        else:
            allow[parts[0]] = int(parts[1])
    return allow, bad


def scan_repo(root) -> list[dict]:
    """Repo-wide guard (#1752): every tracked text file, no skipped directories."""
    root = pathlib.Path(root).resolve()
    allow, out = _parse_allow(root)
    for f in _tracked_files(root):
        rel = f.relative_to(root).as_posix()
        if rel == ALLOW_FILE:
            continue
        text = _read_text(f)
        if text is None:
            continue
        vs = violations_in_text(text)
        if vs and rel in allow and len(vs) <= allow[rel]:
            continue
        out.extend({"file": str(f), **v} for v in vs)
    return out


def scan_cluster(items_json: dict, exclude_namespaces=DEFAULT_EXCLUDE_NS) -> list[dict]:
    out = []
    for item in items_json.get("items", []):
        md = item.get("metadata", {})
        ns = md.get("namespace", "")
        if ns in exclude_namespaces or (md.get("annotations") or {}).get(EXEMPT_ANNOTATION) == "exempt":
            continue  # legacy-frozen namespace, or an object that carries the policy text itself (e.g. the scanner's ConfigMap)
        for v in violations_in_text(json.dumps(item)):
            out.append({"namespace": ns, "kind": item.get("kind"), "name": md.get("name"), "match": v["match"]})
    return out


def _report(vs: list[dict], key: str) -> None:
    if not vs:
        print("model-policy: 0 violations")
        return
    print(f"model-policy: {len(vs)} violation(s)")
    for k, n in sorted(Counter(v[key] for v in vs).items()):
        print(f"  {k}: {n}")
    seen = set()
    for v in vs:
        ident = (v.get("file") or f"{v['namespace']}/{v['kind']}/{v['name']}", v["match"])
        if ident in seen:
            continue
        seen.add(ident)
        print(f"  - {ident[0]}: {ident[1]}")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="mode", required=True)
    f = sub.add_parser("files"); f.add_argument("paths", nargs="+"); f.add_argument("--enforce", action="store_true")
    r = sub.add_parser("repo"); r.add_argument("root"); r.add_argument("--enforce", action="store_true")
    c = sub.add_parser("cluster"); c.add_argument("--kubectl-json"); c.add_argument("--exclude-ns", default=",".join(sorted(DEFAULT_EXCLUDE_NS))); c.add_argument("--enforce", action="store_true")
    a = ap.parse_args(argv)
    if a.mode == "files":
        vs = scan_files(a.paths); _report(vs, "file")
    elif a.mode == "repo":
        vs = scan_repo(a.root); _report(vs, "file")
    else:
        if a.kubectl_json:
            data = json.loads(pathlib.Path(a.kubectl_json).read_text())
        else:
            data = json.loads(subprocess.check_output(["kubectl", "get", "deployments,statefulsets,cronjobs,configmaps", "-A", "-o", "json"]))
        vs = scan_cluster(data, {x for x in a.exclude_ns.split(",") if x}); _report(vs, "namespace")
    return 1 if (vs and a.enforce) else 0


if __name__ == "__main__":
    sys.exit(main())
