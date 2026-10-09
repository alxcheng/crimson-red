#!/usr/bin/env python3
"""Build bh/index/methods.md: every class and method in Battleheart's IL with
its line range, so a reader can jump straight to the code.

UnityScript coroutines compile to nested classes named `$method$NNN` whose
MoveNext() holds the real body; they are listed under their owning class.

Usage: python3 bh/tools/build_il_index.py [path/to/Assembly-UnityScript.il]
"""
import os, re, sys

DEFAULT = "/Users/alexcheng/CascadeProjects/Battleheart datamine/il/Assembly-UnityScript.il"
SRC = sys.argv[1] if len(sys.argv) > 1 else DEFAULT
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "index", "methods.md")

lines = open(SRC, encoding="utf-8", errors="replace").read().split("\n")
classes = []          # {name, start, end, depth, fields, methods:[{name,start,end,sig}]}
stack = []            # open classes
depth = 0
pending = None        # ("class"|"method", obj) waiting for its opening brace
cur_method = None
method_depth = None

def sig_name(text):
    m = re.search(r"([\w$.<>`]+|'[^']+')\s*\(", text)
    return m.group(1).strip("'") if m else "?"

i = 0
while i < len(lines):
    raw = lines[i]; s = raw.strip(); n = i + 1
    if s.startswith(".class "):
        name = s.split()[-1].strip("'")
        c = {"name": name, "start": n, "end": n, "fields": 0, "methods": [],
             "parent": stack[-1]["name"] if stack else None}
        classes.append(c); pending = ("class", c)
    elif s.startswith(".method "):
        text = s; j = i
        while "(" not in text or ")" not in text:
            j += 1; text += " " + lines[j].strip()
        m = {"name": sig_name(text), "start": n, "end": n}
        if stack: stack[-1]["methods"].append(m)
        pending = ("method", m)
    elif s.startswith(".field ") and stack and cur_method is None:
        stack[-1]["fields"] += 1
    opens, closes = s.count("{"), s.count("}")
    if s.startswith('ldstr') or '"' in s:   # braces inside string literals don't nest
        opens = closes = 0
    for _ in range(opens):
        depth += 1
        if pending:
            kind, obj = pending; pending = None
            obj["depth"] = depth
            if kind == "class": stack.append(obj)
            else: cur_method = obj
    for _ in range(closes):
        if cur_method is not None and cur_method.get("depth") == depth:
            cur_method["end"] = n; cur_method = None
        elif stack and stack[-1].get("depth") == depth:
            stack[-1]["end"] = n; stack.pop()
        depth -= 1
    i += 1

top = [c for c in classes if c["parent"] is None]
nested = {}
for c in classes:
    if c["parent"]: nested.setdefault(c["parent"], []).append(c)

out = ["# Battleheart IL — class & method index (generated)", "",
       "Source: `il/Assembly-UnityScript.il` in the datamine (%d lines). Regenerate with" % len(lines),
       "`python3 bh/tools/build_il_index.py`. Line ranges are 1-based and inclusive.", "",
       "Coroutines (`yield` methods) appear twice: a short stub method on the class, and the real",
       "body in a nested `$name$NNN` class's `MoveNext` — read the nested range.", "",
       "| Class | Lines | Size | Fields | Methods |", "|---|---|---|---|---|"]
for c in top:
    out.append("| [%s](#%s) | %d–%d | %d | %d | %d |" % (c["name"], c["name"].lower(), c["start"], c["end"],
               c["end"] - c["start"] + 1, c["fields"], len(c["methods"])))
for c in top:
    out += ["", "## %s" % c["name"], "", "Lines %d–%d. %d fields." % (c["start"], c["end"], c["fields"]), "",
            "| Method | Lines | Size |", "|---|---|---|"]
    for m in c["methods"]:
        out.append("| `%s` | %d–%d | %d |" % (m["name"], m["start"], m["end"], m["end"] - m["start"] + 1))
    subs = nested.get(c["name"], [])
    if subs:
        out += ["", "Coroutine bodies / nested classes:", "", "| Nested class | Lines | Size |", "|---|---|---|"]
        for sc in subs:
            # nested-of-nested (the $ enumerator inside the coroutine class) is folded into its parent range
            out.append("| `%s` | %d–%d | %d |" % (sc["name"], sc["start"], sc["end"], sc["end"] - sc["start"] + 1))
os.makedirs(os.path.dirname(OUT), exist_ok=True)
open(OUT, "w").write("\n".join(out) + "\n")
print("wrote", OUT, "classes:", len(top), "methods:", sum(len(c["methods"]) for c in classes))
