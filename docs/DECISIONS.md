# Decisions Log

One line per decision: **decision — why**. Unverified facts are tagged `INFERENCE`.

## Phase 0

- 2026-09-30 · phase0.step0 · Spec copied to `docs/BUILD_SPEC.md`; the uploaded original was left untouched — Rule 2 (originals read-only) and the upload folder is outside the repo.
- 2026-09-30 · phase0.step0 · Repo was already `git init`-ed (empty) on branch `claude/studio-spine-build-spec-j1cqib`; Phase 0 commits use `phase0.stepN:` — the repo exists, and Rule 9's one-commit-per-step also applies to Phase 0.
- 2026-09-30 · phase0.step1 · Audit ran in the Claude Code cloud container, not the workstation; added read-only `scripts/audit_environment.ps1` for the real machine — the container can't see Tyson's GPU, drives or Adobe apps.
- 2026-09-30 · phase0.step1 · Audit script writes a separate `docs/ENVIRONMENT_REPORT_WORKSTATION.md` — keeps the container report and the workstation report from overwriting each other.
- 2026-09-30 · phase0.step2 · Hardware tier = **T1, PROVISIONAL** — the only measured machine has 0 GB VRAM, and T1 is the safe floor (small VLM, Video2X only, no SeedVR2, no local video sandbox). `INFERENCE`: Tyson's workstation tier is unknown; raise it once the workstation report gives real VRAM.
- 2026-09-30 · phase0.step2 · Tier thresholds with ~1 GB tolerance: ≥31 GB → T4, ≥23 → T3, ≥15 → T2, else T1 — cards report slightly less than their nominal size (a 16 GB card shows ~15.9 GB), and in-between sizes round down.
- 2026-09-30 · phase0.step2 · Proposed: SQLite DB and proxies on a local NVMe/SSD, **never** in a OneDrive / Google Drive / Dropbox / network folder — SQLite WAL needs a local filesystem with working file locks; cloud-sync clients corrupt live DBs.
- 2026-09-30 · phase0.step2 · API binds to `127.0.0.1` only (default port 8765) — local-first; nothing on the LAN until Tyson asks.
- 2026-09-30 · phase0.step2 · Default night window 01:00–07:00 local time (editable in `config/studio.toml`) — placeholder until Tyson says when the machine is idle.
