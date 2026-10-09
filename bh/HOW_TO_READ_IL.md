# How to read the Battleheart source and write a `bh/systems/` doc

Battleheart (BH) was written in UnityScript for Unity 4.7. We do not have the original
script files; we have the compiled code disassembled to CIL text:

    /Users/alexcheng/CascadeProjects/Battleheart datamine/il/Assembly-UnityScript.il   (108,668 lines)

Find any class or method by line in [`index/methods.md`](index/methods.md). Read a range with a
file-read tool (offset + limit) — never load the whole file. The game's data tables (items,
classes, powers, levels, waves, loot, XP curve) are already decoded in [`data/`](data/); cite
them by file and id instead of re-deriving them.

## Reading CIL quickly

- It is a stack machine. `ldc.r4 0.35` / `ldc.i4.s 20` push constants; `ldfld X` reads field X;
  `stfld X` writes it; `call`/`callvirt` call a method; `brtrue/brfalse/blt/bge…` branch to an
  `IL_xxxx` label. A formula is the sequence of pushes followed by `mul/add/sub/div`.
- **Constants are the payload.** Every literal number, string (`ldstr`), animation name, prefab
  path and tag is worth recording exactly.
- UnityScript's dynamic typing shows up as `Boo.Lang.Runtime.RuntimeServices::Invoke/GetProperty/
  SetProperty/op_*` calls with the member name as an `ldstr` just before — read the string to know
  which member is touched.
- Coroutines (`yield`): the method on the class is a stub. The real body is the `MoveNext` of a
  nested class named `$methodName$NNN`. It starts with a `switch` on `$state` (resume points);
  locals are hoisted to fields named `$localName$NNN`. `WaitForSeconds` + a `ldc.r4` before it is
  a timed delay — record the duration.
- `GetComponent`, `GameObject.Find("…")`, `SendMessage("…")`, `Instantiate(Resources.Load("…"))`
  show how objects talk to each other — record the target and message name.
- `Random.Range(a, b)`, `Time.deltaTime`, `Mathf.*`, `Vector3.Distance` are where tuning lives.

## What a `bh/systems/*.md` doc must contain

1. **Title + scope line**: class, methods covered, IL line range.
2. **Summary** (≤ 15 lines, plain language): what this code does in the game, as a player would
   see it.
3. **Fields**: table of every field this code reads or writes — name, type, meaning, default
   value if a constructor/`Awake` sets one.
4. **One section per method** (or per branch of a giant method): purpose, then the logic as
   numbered steps or pseudocode. Include every formula with its real constants, every timer,
   every probability, every state/enum value and what it means, every string identifier.
5. **Citations**: tag each fact `[IL L12345]` or `[IL L12345-12390]` (line numbers in the .il
   file). A fact with no citation is not allowed.
6. **Lookup tables** where the code switches on an id (enemy type, class id, power index,
   item id): one row per case, with what it does. Resolve ids to names via `bh/data/*.json`
   when possible.
7. **Uncertain / not determined**: list anything you could not pin down. Write `UNVERIFIED:`
   in front of any statement that is an inference rather than read from the code. Never guess a
   number — if you did not see it in the IL or in `bh/data`, say so.
8. **Cross-references**: other methods/classes this code calls or is called by (name + line).

Style: write for a reader who has never seen BH and cannot ask questions. Prefer tables and
short pseudocode over prose. Be complete rather than brief — this is a reference, not a summary.
Older research notes exist (`work/*.md` in this repo, `docs/*.md` in the datamine); treat them
as hints only, verify against the IL, and list any contradiction you find in section 7.
