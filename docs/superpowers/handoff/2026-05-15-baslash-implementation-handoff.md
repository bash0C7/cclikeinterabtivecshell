# baslash implementation — next-session handoff

**Date:** 2026-05-15
**Status at handoff:** spec + plan complete and committed; implementation NOT started.

---

## What you are doing

Execute the **baslash rename + zsh-style + title-bar pivot** implementation
plan via the `superpowers:subagent-driven-development` skill (user's chosen
execution mode).

- **Spec:** `docs/superpowers/specs/2026-05-15-baslash-rename-and-zsh-style-pivot-design.md`
- **Plan:** `docs/superpowers/plans/2026-05-15-baslash-rename-and-zsh-style-pivot.md`

The plan has 14 tasks, each with TDD bite-sized steps and concrete code.
Dispatch a fresh implementer subagent per task; after each, run
spec-compliance review then code-quality review (the skill's prescribed
two-stage review). Continuous execution — do not pause between tasks
unless BLOCKED.

## State at handoff

**Test suite (last verified before handoff):**
- root: 181 tests, 0 failures, 0 errors, 2 omissions
- cclikesh-debug: 80 tests, 0 failures, 0 errors, 2 omissions

**Most recent commits (newest first):**
```
4ac8f7e docs(plan): baslash rename + zsh-style + title-bar pivot implementation plan
35dbad9 docs(spec): narrow baslash scope to macOS + Terminal.app + cmux
396e91f docs(spec): baslash rename + zsh-style + title-bar pivot design
b93df73 docs(handoff): R-specs ALL PASS + TermSim infrastructure landed
722505f fix(test/r3): expand REP \e[Nb in divider-width count
dc96e3c fix(test/r2): assert visible row distance via TermSim
32c9783 feat(debug): TermSim minimal terminal emulator + Captured#screen
9df63fc docs(handoff): diagnostic results from curses noalt diag strategy run
```

**Push status:** `b93df73` and earlier are on `origin/main` (force pushed
earlier this session, 123 commits). The three docs commits (`4ac8f7e`,
`35dbad9`, `396e91f`) are local-only. Push them only if user explicitly
asks; do not push implementation commits autonomously.

**Untracked:** `cclikesh-debug/tmp/` is a pre-existing test artifact (May
14, 2026). Do NOT include in any commit. Leave alone.

## Background context the plan does not repeat

**Why this plan exists** (compressed):

- Today (2026-05-15) we discovered `cclikesh` has a structural scrollback
  truncation bug: ncurses uses DECSTBM (`change_scroll_region`) as a
  sub-region scroll optimization for the body pad, and rows scrolled out
  of the sub-region are discarded — never delivered to terminal scrollback.
- The user reported this as: "治っているが、履歴の途中から消失する。
  terminalのバッファはまだまだあるのに" (scroll-back is broken from a
  certain point even though the terminal buffer has plenty of room).
- Earlier in the session we built `Cclikesh::Debug::TermSim`, a minimal
  terminal emulator, and confirmed via R1/R2/R3 PTY specs that the
  current architecture's bytes look "OK" in a sane sim — but that the
  sim is masking the structural problem.
- We considered a curses → custom-renderer pivot. User pushed back hard:
  "Claude Code を curses やめて多くの regression 出した前例ある". Saved
  to memory `feedback_curses_migration_risk.md`.
- Then the user proposed a much simpler model: zsh-style natural flow
  (no fixed footer) + terminal title bar status (OSC 0/2). This avoids
  the curses fight entirely: body content `puts`'d to stdout naturally
  scrolls to terminal scrollback; status lives in the title bar (no
  on-screen footer).
- User then proposed **renaming `cclikesh` to `baslash`** (ba + slash)
  to honestly mark the identity shift away from "Claude Code Like Shell".
  No backward compatibility — examples are author-owned; breaking is fine.

## Important user-supplied constraints

These are non-negotiable; check `~/.claude/projects/.../memory/MEMORY.md`
for the full list. Highlights relevant to this implementation:

- **Verify before handoff** (`feedback_verify_before_handoff.md`): unit
  test green ≠ feature works. cclikesh/baslash changes must be verified
  via `cclikesh-debug play` (now `baslash-debug play`) PTY recording AND
  real-TTY smoke per Task 14.
- **PTY spec invocation from repo root** (`project_pty_spec_repo_root_invocation.md`):
  PTY specs (`baslash-debug/test/specs/*.rb`) must be `play`'d from the
  repo root, NOT from `baslash-debug/`. Child dies in 0.6s with LoadError
  otherwise.
- **No silent rescue** (`~/dev/src/CLAUDE.md`): `rescue nil` /
  `rescue ... => _` patterns are forbidden. Test code uses
  `omit "reason: #{e.message}"`, production uses log/re-raise/Result.
- **Git ops via subagent** (`~/.claude/CLAUDE.md`): `git status` / `diff`
  / `commit` / `push` go through the `commit-commands` skill or
  `general-purpose` subagent. Bash 直叩き only for 1-2 file `git log -n 3`
  type checks.
- **Test execution via subagent** (`~/dev/src/CLAUDE.md`):
  `bundle exec rake test` goes through general-purpose subagent — only
  pass/fail + count returned to keep main context clean. Single-test
  debug (`-n test_x`) can use Bash directly.
- **No amend on commits**: Always NEW commits, never `git amend`. If the
  pre-commit hook fails, fix the underlying issue and commit again. (The
  current handoff session had one minor amend slip in a subagent — flag
  this in subagent prompts for next session.)
- **`docs/superpowers/` is gitignored**: any spec/plan/handoff doc commit
  needs `git add -f`.
- **No Python** (`~/.claude/CLAUDE.md`): Ruby project. Scripting/tooling/
  analysis must be Ruby.
- **Persona**: respond in Japanese Kansai gyaru ("Jarinko-Chie") — never
  switch to English or standard Japanese in user-facing text.

## Task ordering reminder

The plan is sequential: Task 1 → 14. Each task in turn:

1. Dispatch implementer subagent with full task text + scene-setting
   context. **Pass the entire task block from the plan, including all
   step code blocks.** Don't ask the implementer to read the plan; quote
   it inline.
2. After DONE, dispatch spec-compliance reviewer (uses
   `./spec-reviewer-prompt.md` from the skill).
3. After spec ✅, dispatch code-quality reviewer (uses
   `./code-quality-reviewer-prompt.md`).
4. After both ✅, mark task complete in TaskList and proceed.

The Task 14 (real-TTY smoke) requires human-in-the-loop. Pause there,
ask the user to run the verification steps and report observations.

## After Task 14

After all 14 tasks are complete:
- Dispatch a final code-reviewer subagent for the entire baslash tree.
- Use `superpowers:finishing-a-development-branch` to decide on PR / merge.
- Author writes (or you draft) a final shipping handoff doc summarizing
  what landed, the test counts, and any open follow-ups.

## Open follow-ups outside this plan

- The 3 local docs commits (`4ac8f7e`, `35dbad9`, `396e91f`) — push when
  user is ready, or include with the implementation commits.
- The `cclikesh-debug/tmp/` pre-existing artifact — outside scope.
- Real-TTY retest of R1/R2/R3 in user's actual environment (originally
  noted in `2026-05-15-r-specs-all-pass.md`) — superseded by Task 14
  smoke for the new architecture.
