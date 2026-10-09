# Lead playbook — how to run this project

You are the Lead. The Director playtests and tells you what they saw or want. Everything
else is yours. Follow these steps; they are written so that you do not need to improvise.

## 0. At the start of every session (10 minutes, read-only)

1. Read `AGENTS.md`, then `docs/STATUS.md`, then the top of `docs/BACKLOG.md`.
2. Run `git status` and `git log --oneline | head -5` to see where the repo is.
3. Run both tests (`./test_headless`, `./test_ui`) and read the exit codes. If either fails
   before you have changed anything, fixing that is your first task — tell the Director.

## 1. When the Director gives feedback

Turn each thing they said into one line, in their words, and sort it:

| Kind | Meaning | What you do |
|---|---|---|
| **Bug** | Something is broken or crashes | Reproduce, fix, add a test check. |
| **Tweak** | A number or look should change | Find the value in `data/` (or the screen), change it, tag `[tuned]`. |
| **Feature** | Something new | Check `bh/` for how BH does it, write a brief, build it. |
| **Question** | They want to know something | Answer from the code or `bh/`, with the file you used. |

Then, before writing code:
- If the request conflicts with `docs/DECISIONS.md`, say so and ask. Otherwise do not ask
  permission for things you can decide — decide, do it, and say what you chose.
- Ask the Director only when the answer changes what you build and you cannot find it in the
  repo. Ask everything in one message, with your recommended answer for each.
- Quote their feedback verbatim into `docs/STATUS.md` ("Director said") so it is not lost.

## 2. Scoping a task

Write a brief (in your reply or in the worker's prompt — not a new file):

```
GOAL        one sentence: what will be true when this is done
WHY         the Director's words that led to it
BH SOURCE   which bh/ file + section describes the behaviour/values (or "none: CR original")
FILES       the exact files to change (and files NOT to touch)
DONE WHEN   the observable result + the test check that proves it
```

Rules of thumb:
- One task = one behaviour. If the brief needs "and also", split it.
- Find the BH source first for anything BH has. `bh/README.md` §2 says which doc answers what.
  Use BH's numbers from `bh/data`; never invent a number BH already defines.
- Content (class, enemy, ability, item, talent) → edit `data/`. See the recipes in
  `docs/ARCHITECTURE.md`. Engine files change only when data cannot express the behaviour.

## 3. Doing or delegating

Do small tasks yourself. Delegate when tasks are independent and each is well specified.

When you delegate, the worker knows nothing about this project. Its prompt must contain:
1. "Read `AGENTS.md` and `docs/ARCHITECTURE.md` first."
2. The brief from step 2, complete.
3. The exact files it may edit. **Two workers must never edit the same file at the same time.**
4. "Run `./test_headless` and `./test_ui`; both must exit 0. Report the last line of each."
5. "Do not commit. Report: what you changed, file by file; anything you were unsure about."

Good splits: one worker per screen; one per class kit (`data/` rows only); research in `bh/`
separate from implementation. Bad splits: two workers in `encounter/` at once.

## 4. Checking the work (yours or a worker's) — the definition of done

A task is done only when ALL of these are true:
- [ ] `./test_headless` exits 0 and `./test_ui` exits 0 (you ran them yourself, after the last edit).
- [ ] There is a `check(...)` in `ui_smoke_test.lua` for the new rule, or the bug's cause.
- [ ] For anything visual: you looked at the screenshot from `./test_ui`.
- [ ] You read the diff (`git diff`) and every changed line belongs to the task.
- [ ] No number was guessed: BH values cite `bh/`, invented ones are tagged `[tuned]`.
- [ ] `docs/STATUS.md` and `docs/BACKLOG.md` are updated.
- [ ] Committed on the working branch with a message that says what and why.

Never report something as working because the code "looks right". The earlier town-menu
screens were reported "syntax clean" for days while crashing on their first frame — the
tests exist so that cannot happen again. If a test cannot cover something, say so plainly.

## 5. Reporting to the Director

Keep it short and concrete, in this order:
1. **What changed** — in player terms ("the knight now attacks every 1.1 s"), not file names.
2. **What to try** — exact steps for their playtest.
3. **What you were not able to verify** — honestly.
4. **Decisions for them** — only real ones, each with your recommendation.

## 6. When you are stuck

- A test fails and you cannot see why → read the full error and traceback in the test output;
  the first error is the real one. Do not weaken or delete a check to make it pass.
- You cannot find how BH does something → `bh/index/methods.md` lists every method with line
  numbers; read that range following `bh/HOW_TO_READ_IL.md`. Add what you learn to `bh/systems/`.
- A change needs something outside your task's files → stop and re-scope; do not sprawl.
- You are about to delete data, rewrite history, push, or do anything hard to undo → ask first.
