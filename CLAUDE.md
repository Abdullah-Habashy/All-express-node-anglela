# CLAUDE.md — Studio Spine

**Single source of truth:** [`docs/BUILD_SPEC.md`](docs/BUILD_SPEC.md). Read it fully before any work.

## How to work
- Work linearly, phase by phase, step by step (Do → Needs → Produces → Done-check).
- STOP at every **Approval Gate** and wait for Tyson's explicit OK before the next phase.
- Talk to Tyson in **Egyptian Arabic**. Code, comments, commits, and file content stay in English.
- After every step print a progress block: `✅ Done` / `🔄 Now` / `⏭️ Left in this phase`.
- Log engineering decisions in `docs/DECISIONS.md` (one line: decision + why). Unverified facts → label `INFERENCE`.
- Ask only when a decision is irreversible, costs money, or touches Tyson's original files.

## Non-Negotiable Rules (BUILD_SPEC §1)
1. **Never delete user files.** No `rm`/`del`/emptying trash. "Delete" = move to `<root>/_spine_trash/<date>/` + undo-log entry.
2. **Originals are read-only.** Processing writes a new file. Renames/moves go through the Registry with an undo record (`spine undo <op_id>`).
3. **Batch operations are dry-run by default.** Real execution needs `--apply`; dry-run prints a table of exactly what will change.
4. **Unique names, never reused.** All generated names come from the Naming Authority (§4).
5. **No secrets in the repo.** Keys live in `.env` (gitignored); ship `.env.example`.
6. **No cloud calls unless the job explicitly says so.** Every cloud call is logged in the Ledger with cost.
7. **Licenses first.** No non-commercial (e.g. BRIA RMBG-2.0, InsightFace packs) or linked AGPL code without asking Tyson. Record every model + license in `docs/LICENSES.md`.
8. **Pin versions.** Python via `uv` + lockfile; Node via `package-lock.json`; fast-moving tools pinned to a release.
9. **Git:** one commit per completed step, message `phaseN.stepM: <what>`.
10. **API-first, UI-automation last.** UI automation only for apps with no API, marked fragile.
11. **One engine, three faces.** Each capability lives once in the core package, exposed via HTTP API, CLI (`spine ...`), and MCP tools. No duplicated logic.
