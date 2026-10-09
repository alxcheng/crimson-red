#!/usr/bin/env python3
"""Extract every script-component instance (MonoBehaviour) from Battleheart's
Unity data: the Inspector-set values that are NOT in the code — per-enemy
health/power/AI type/special-move cooldowns, per-hero attack timings, the
MotherBrain buff/debuff magnitude and duration tables, effect prefab speeds…

How: each Unity 4.7 SerializedFile (format v9) has an object table. Objects of
class 114 are MonoBehaviours; their m_Script pointer names a MonoScript (class
115) whose m_ClassName tells us which game class the bytes belong to. Type
trees are stripped, so the layout comes from the IL: public, non-static fields
in declaration order (see extract_database.py for the primitive encodings).
Object references are stored as (fileID, pathID) and resolved to the target
GameObject's name where possible. Every decode must consume the object's exact
byte size, otherwise it is reported as FAILED and not written.

Usage:  python3 bh/tools/extract_prefabs.py [DataDir] [path/to/Assembly-UnityScript.il]
Writes: bh/data/prefabs/<Class>.json  — list of instances of that class
"""
import glob, json, os, re, struct, sys

ROOT = "/Users/alexcheng/CascadeProjects/Battleheart datamine"
DATA = sys.argv[1] if len(sys.argv) > 1 else ROOT + "/decompiled/resources/assets/bin/Data"
IL = sys.argv[2] if len(sys.argv) > 2 else ROOT + "/il/Assembly-UnityScript.il"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data", "prefabs")

# ---------------------------------------------------------------- IL layouts
def il_layouts(path):
    """{className: [(fieldName, typeString)]} for public instance fields."""
    out, stack, depth, pending, in_method = {}, [], 0, None, None
    for raw in open(path, encoding="utf-8", errors="replace"):
        s = raw.strip()
        if s.startswith(".class "):
            pending = ("class", s.split()[-1].strip("'"))
        elif s.startswith(".method "):
            pending = ("method", None)
        elif s.startswith(".field ") and stack and in_method is None:
            toks = s.split()
            mods = set(toks[1:])
            if "public" in mods and "static" not in mods and "literal" not in mods and "notserialized" not in mods:
                name = toks[-1].strip("'")
                i = 1
                while toks[i] in ("public", "initonly"): i += 1
                ftype = " ".join(toks[i:-1])
                # AnimationState is a plain C# object, not a UnityEngine.Object: never serialized.
                if "UnityEngine.AnimationState" not in ftype:
                    out[stack[-1][0]].append((name, ftype))
        if '"' in s: continue
        for _ in range(s.count("{")):
            depth += 1
            if pending:
                kind, name = pending; pending = None
                if kind == "class":
                    stack.append((name, depth)); out.setdefault(name, [])
                else:
                    in_method = depth
        for _ in range(s.count("}")):
            if in_method == depth: in_method = None
            elif stack and stack[-1][1] == depth: stack.pop()
            depth -= 1
    return out

LAYOUT = il_layouts(IL)
PPTR_PREFIX = "class [UnityEngine]UnityEngine."
VALUE = {"Vector2": "ff", "Vector3": "fff", "Vector4": "ffff", "Quaternion": "ffff",
         "Color": "ffff", "Rect": "ffff", "LayerMask": "I"}

class Fail(Exception): pass

class Reader:
    def __init__(self, buf, pos, end): self.b, self.p, self.end = buf, pos, end
    def align(self): self.p = (self.p + 3) & ~3
    def take(self, fmt):
        n = struct.calcsize("<" + fmt)
        if self.p + n > self.end: raise Fail("read past object end")
        v = struct.unpack_from("<" + fmt, self.b, self.p); self.p += n
        return v
    def i32(self): return self.take("i")[0]
    def f32(self): return round(self.take("f")[0], 6)
    def string(self):
        n = self.i32()
        if n < 0 or self.p + n > self.end: raise Fail("bad string length %d" % n)
        v = self.b[self.p:self.p + n].decode("utf-8", "replace"); self.p += n; self.align()
        return v
    def count(self):
        n = self.i32()
        if n < 0 or n > (self.end - self.p): raise Fail("bad array length %d" % n)
        return n

def read_type(r, t, resolve):
    if t.endswith("[]"):
        el = t[:-2]
        n = r.count()
        if el == "bool":
            v = [bool(x) for x in r.b[r.p:r.p + n]]; r.p += n; r.align(); return v
        return [read_type(r, el, resolve) for _ in range(n)]
    if t == "int32": return r.i32()
    if t == "float32": return r.f32()
    if t == "bool":
        v = r.take("B")[0]; r.align()
        if v > 1: raise Fail("bool byte %d" % v)
        return bool(v)
    if t == "string": return r.string()
    if t.startswith("valuetype [UnityEngine]UnityEngine."):
        name = t.rsplit(".", 1)[1]
        if name not in VALUE: raise Fail("unsupported value type " + name)
        v = r.take(VALUE[name])
        return v[0] if len(v) == 1 else [round(x, 6) for x in v]
    if t.startswith("class "):
        name = t[6:]
        if name.startswith("[UnityEngine]") or (name in LAYOUT and name in MONO_CLASSES):
            return resolve(*r.take("ii"))          # object reference
        if name in LAYOUT:                          # plain [Serializable] class, stored inline
            return {fn: read_type(r, ft, resolve) for fn, ft in LAYOUT[name]}
    raise Fail("unsupported type " + t)

# ------------------------------------------------------------ serialized files
def parse_file(path):
    b = open(path, "rb").read()
    if len(b) < 20: return None
    meta_size, file_size, version, data_off = struct.unpack_from(">IIII", b, 0)
    if version != 9 or file_size != len(b): return None
    p = 20
    z = b.index(b"\0", p); p = z + 1                 # unity version string
    p += 4                                           # platform
    (ntypes,) = struct.unpack_from("<i", b, p); p += 4
    if ntypes != 0: return None                      # type trees present: not expected
    p += 4                                           # padding/bigID flag
    (nobj,) = struct.unpack_from("<i", b, p); p += 4
    objs = {}
    for _ in range(nobj):
        path_id, start, size, type_id, class_id, _d = struct.unpack_from("<iIIihh", b, p); p += 20
        objs[path_id] = (data_off + start, size, class_id)
    (next_,) = struct.unpack_from("<i", b, p); p += 4
    exts = []
    for _ in range(next_):
        z = b.index(b"\0", p); p = z + 1             # asset name (empty)
        p += 16 + 4                                  # guid, type
        z = b.index(b"\0", p); exts.append(b[p:z].decode()); p = z + 1
    return {"b": b, "objs": objs, "exts": exts, "name": os.path.basename(path)}

FILES = {}
for path in sorted(glob.glob(os.path.join(DATA, "*"))):
    if os.path.isfile(path) and ".split" not in path and not path.endswith(".resS"):
        try: f = parse_file(path)
        except (ValueError, struct.error): f = None
        if f: FILES[f["name"].lower()] = f

def target(f, file_id, path_id):
    if path_id == 0: return None, None
    if file_id == 0: return f, path_id
    name = os.path.basename(f["exts"][file_id - 1]).lower()
    return FILES.get(name), path_id

def obj_name(f, path_id, depth=0):
    """Name of an object; components borrow their GameObject's name."""
    if not f or path_id not in f["objs"] or depth > 2: return None
    start, size, cid = f["objs"][path_id]
    b = f["b"]
    if cid == 1:                                     # GameObject: components, layer, name
        (n,) = struct.unpack_from("<i", b, start)
        p = start + 4 + n * 12 + 4
        (ln,) = struct.unpack_from("<i", b, p)
        return b[p + 4:p + 4 + ln].decode("utf-8", "replace")
    if cid in (4, 23, 33, 82, 111, 102, 114, 20, 137, 198):   # components: first field = m_GameObject
        fid, pid = struct.unpack_from("<ii", b, start)
        tf, tp = target(f, fid, pid)
        return obj_name(tf, tp, depth + 1)
    (ln,) = struct.unpack_from("<i", b, start)       # named assets start with m_Name
    if 0 < ln < 200 and start + 4 + ln <= start + size:
        return b[start + 4:start + 4 + ln].decode("utf-8", "replace")
    return None

def script_class(f, path_id):
    if not f or path_id not in f["objs"]: return None
    start, size, cid = f["objs"][path_id]
    if cid != 115: return None
    r = Reader(f["b"], start, start + size)
    r.string(); r.i32(); r.i32()                     # m_Name, m_ExecutionOrder, m_PropertiesHash
    return r.string()                                # m_ClassName

# which IL classes are attached scripts (referenced by pointer) vs inline data classes
MONO_CLASSES = set()
for f in FILES.values():
    for pid, (start, size, cid) in f["objs"].items():
        if cid == 115:
            MONO_CLASSES.add(script_class(f, pid))

results, failed = {}, []
for f in FILES.values():
    for pid, (start, size, cid) in sorted(f["objs"].items()):
        if cid != 114: continue
        r = Reader(f["b"], start, start + size)
        go = r.take("ii"); r.take("B"); r.align()
        sf, sp = target(f, *r.take("ii"))
        cls = script_class(sf, sp)
        r.string()                                   # m_Name
        if cls not in LAYOUT: continue               # engine/UI script, not game code
        def resolve(fid, ppid, f=f):
            tf, tp = target(f, fid, ppid)
            if tp is None: return None
            return {"ref": obj_name(tf, tp) or "?", "file": tf["name"] if tf else "?", "id": tp}
        try:
            fields = {fn: read_type(r, ft, resolve) for fn, ft in LAYOUT[cls]}
            if r.p != start + size: raise Fail("decoded %d of %d bytes" % (r.p - start, size))
        except (Fail, struct.error) as e:
            failed.append("%s #%d %s: %s" % (f["name"], pid, cls, e)); continue
        gf, gp = target(f, *go)
        results.setdefault(cls, []).append(
            {"object": obj_name(gf, gp) or "?", "file": f["name"], "id": pid, "fields": fields})

os.makedirs(OUT, exist_ok=True)
for cls, rows in sorted(results.items()):
    rows.sort(key=lambda r: (r["object"], r["file"], r["id"]))
    with open(os.path.join(OUT, cls + ".json"), "w") as fh:
        json.dump(rows, fh, indent=1, ensure_ascii=False); fh.write("\n")
    print("%-26s %4d instances" % (cls, len(rows)))
print("files scanned: %d, script classes: %d, FAILED decodes: %d" % (len(FILES), len(MONO_CLASSES), len(failed)))
for line in failed[:40]: print("  FAILED", line)
