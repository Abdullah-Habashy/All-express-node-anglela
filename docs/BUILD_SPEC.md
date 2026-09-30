# STUDIO SPINE — Build Spec v001
Local-First AI Production Infrastructure for Tyson's studio
Owner: Tyson (creative director / producer, Windows workstation, Egypt)
Builder: Claude Code

---

## 0. HOW TO USE THIS DOCUMENT (read first)

- This file is the single source of truth for the build. Put it in the repo root as `docs/BUILD_SPEC.md` and create a short `CLAUDE.md` that points to it.
- Work **linearly**, phase by phase, step by step. Every step has: **Do → Needs → Produces → Done-check**.
- **Approval gates:** at the end of every phase, STOP, show a summary + demo commands, and wait for Tyson's explicit OK before starting the next phase.
- **Talk to Tyson in Egyptian Arabic.** Code, comments, commit messages, and file content stay in English.
- **Progress updates:** after every step, print a short block:
  ```
  ✅ Done: ...
  🔄 Now: ...
  ⏭️ Left in this phase: ...
  ```
- Do not ask many questions. Make logical engineering decisions, write them in `docs/DECISIONS.md` (one line each: decision + why), and ask only when a decision is irreversible, costs money, or touches his original files.
- Anything you could not verify (versions, licenses, VRAM numbers) → label it `INFERENCE` in the decision log.

---

## 1. NON-NEGOTIABLE RULES

1. **Never delete user files.** No `rm`, no `del`, no emptying trash. "Delete" = move to `<root>/_spine_trash/<date>/` with an entry in the undo log.
2. **Originals are read-only.** Any processing writes a new file. Renames/moves go through the Registry and are logged with an undo record (`spine undo <op_id>`).
3. **Batch operations are dry-run by default.** Real execution requires `--apply`. Dry-run prints a table of exactly what will change.
4. **Unique names, never reused.** All generated names come from the Naming Authority (§4). No component invents file names on its own.
5. **No secrets in the repo.** API keys live in `.env` (gitignored). Provide `.env.example`.
6. **No cloud calls unless the job explicitly says so.** Local-first by default; every cloud call is logged in the Ledger with cost.
7. **Licenses:** before adding any model or library, check its license. Do NOT install anything non-commercial (e.g. BRIA RMBG-2.0 = CC BY-NC, InsightFace model packs = non-commercial) or AGPL code that would be linked into this codebase without asking Tyson first. Record every model + license in `docs/LICENSES.md`.
8. **Pin versions.** Python via `uv` with a lockfile; Node via `package-lock.json`. Fast-moving tools (llama-swap, ComfyUI nodes) pinned to a specific release.
9. **Git:** `git init` in Phase 1; one commit per completed step, message format `phaseN.stepM: <what>`.
10. **API-first, UI-automation last.** Use app APIs (UXP, bpy, ComfyUI HTTP, ffmpeg). UI automation (pywinauto / Windows-MCP) only for apps with no API, and mark it as fragile.
11. **One engine, three faces.** Every capability lives once in the core Python package and is exposed as: HTTP API (for plugins/apps), CLI (`spine ...`), and MCP tools (for Claude). No logic duplicated across faces.

---

## 2. ARCHITECTURE (target)

```
          Claude (chat / Cowork / Claude Code)
                         │ MCP (stdio)
 ┌───────────────────────┴───────────────────────┐
 │ STUDIO SPINE core (Python 3.12, FastAPI)       │
 │ Registry · Naming Authority · Job Queue ·      │
 │ Generation Ledger · Events · Undo log          │
 │ DB: SQLite (WAL) → Postgres+pgvector later     │
 │ Faces: HTTP :8765 · CLI `spine` · MCP server   │
 └──┬────────┬────────┬────────┬────────┬─────────┘
  media    voice    comfy    blender   adobe      docs/research
  worker   worker   worker   worker    bridges    workers (later)
    │
 LOCAL AI GATEWAY: llama-swap (VRAM arbiter) → llama.cpp / LM Studio,
 ComfyUI, embeddings. Router: cheap tasks local, judgment tasks → Claude.
 Cloud stays cloud: Magnific/Seedance, ElevenLabs, Gemini TTS, Claude.
```

Principles:
- **DB is the truth; folders are a view.**
- **Workers never call each other.** They take a job, write artifacts, emit an event.
- **One heavy GPU job at a time** (GPU lock in the queue). Light jobs can run in parallel on CPU.
- **Night Shift:** long GPU batches (upscale, indexing, alignment) can be scheduled into a configurable night window.

---

## 3. REPO LAYOUT

```
studio-spine/
  CLAUDE.md
  README.md
  .env.example
  pyproject.toml / uv.lock
  config/
    studio.toml              # roots, watch folders, ports, night window, hardware tier
    delivery_profiles.yaml   # §7
    preflight_rules.yaml     # §5
    naming.yaml              # §4
    models.yaml              # gateway model map (Phase 4)
  spine/
    core/      db.py, models.py, registry.py, naming.py, queue.py, ledger.py, undo.py, events.py
    api/       FastAPI app
    cli/       Typer CLI
    mcp/       MCP server (python `mcp` SDK, FastMCP, stdio)
    workers/   media.py, voice.py, ingest.py, (later: comfy.py, blender.py, docs.py ...)
    preflight/ rules engine
    reports/   HTML report templates (Jinja2)
  tests/
  docs/        BUILD_SPEC.md, DECISIONS.md, LICENSES.md, ENVIRONMENT_REPORT.md, RUNBOOK.md
  scripts/     install/start/stop PowerShell scripts
```

Runtime: start at user logon via **Task Scheduler** (not a Session-0 Windows Service), because Adobe and GPU desktop apps live in the user session. Provide `scripts/install_autostart.ps1` and `scripts/uninstall_autostart.ps1`.

---

## 4. NAMING AUTHORITY (spec)

Format (configurable in `config/naming.yaml`):
```
{project}_{shot}_{type}_v{###}.{ext}
e.g. WARAYA_S07_camref_v003.mp4 · NUTRI_E0142_srt_v001.srt · ITQAN_AD05_edit_v002.prproj
```
- `project`: uppercase ASCII slug (registered once: `spine project add WARAYA`).
- `shot`: `S##`, `E####`, `AD##`, or free slug.
- `type`: from a controlled list (camref, previz, gen, upscale, proxy, edit, srt, vo, thumb, kv, contact, qc, deliver …). Unknown types must be added to the list, not typed ad hoc.
- Version numbers are **allocated by the DB** (atomic), never reused — even if a file is trashed.
- Arabic or messy original names are preserved in the DB field `original_name`; the filesystem name is ASCII.
- Collision check against DB + disk before any write.

---

## 5. PRE-FLIGHT RULES (spec)

Rules live in `config/preflight_rules.yaml`, with per-model profiles. Initial rules:

**Video prompts (Seedance / Magnific video):**
1. **Element coverage:** every element in the shot's `scene_manifest` (list of visible elements from the previz/camref, e.g. road, tunnel, each background car, props, characters) must appear in the prompt as an `@tag` or explicit text. Missing element → FAIL with the list.
2. **Duration match:** generation duration == reference (camref) duration. Mismatch → FAIL.
3. **No silent removals:** any element present in the previous approved scene_manifest but absent from the new one → FAIL unless the change has `approved_by: tyson`.
4. **Length limit:** prompt length ≤ 10,000 characters (Magnific). Configurable per provider.
5. **Banned quality words:** realistic, cinematic, 8K, 4K (as a quality word), hyperrealistic, premium, masterpiece, ultra-detailed … (list in YAML). Model-specific exceptions (approved by Tyson): `photorealistic` allowed **once** on GPT Image 2.5; camera and film-stock names allowed on Nano Banana models.
6. **Avoid-list present:** prompt must contain an explicit avoid/negative block.
7. **Previz is motion-only:** if a previz/camref is attached, the prompt must not describe its look as the target look (flag phrases like "match the render look").

Output for every check — always print the 3-line pre-flight:
```
PREFLIGHT  WARAYA_S07_prompt_v004
1) Elements ↔ @tags: PASS (12/12)
2) Duration gen=6.0s ref=6.0s: PASS
3) Removed without approval: PASS (0)
+ length 7,412/10,000 · banned words 0 · avoid-list ✓  → READY
```

---

## 6. DATABASE SCHEMA (Phase 1 minimum)

- `projects(id, slug, title, created_at)`
- `shots(id, project_id, code, title, scene_manifest_json, ref_duration_s)`
- `artifacts(id, name, path, original_name, sha256, kind, width, height, fps, duration_s, codec, audio_json, parent_id, project_id, shot_id, prompt_id, model, status[draft|review|approved|rejected|archived], created_at, meta_json)`
- `prompts(id, name, shot_id, provider, model, text, refs_json, target_duration_s, preflight_json, created_at)`
- `generations(id, prompt_id, provider, model, credits, cost_usd, started_at, finished_at, result_artifact_id, outcome[success|fail|partial], failure_tag, notes)`
- `jobs(id, type, payload_json, status[queued|running|done|failed|cancelled], priority, needs_gpu, attempts, max_attempts, error, log_path, created_at, started_at, finished_at)`
- `events(id, type, ref_id, payload_json, at)`
- `undo_log(op_id, kind[rename|move|trash], from_path, to_path, at, undone_at)`

Optional sidecar: `<file>.spine.json` (on by default for deliverables, off for intermediates; config flag).

---

## 7. DELIVERY PROFILES (starting set, editable YAML)

Each profile: container, video codec, resolution, fps, pixel format, bitrate range, audio codec, sample rate, channels, loudness target (integrated LUFS ± tolerance), true-peak max, max file size (optional), safe-area overlay (title/action %).
Start with: `youtube_16x9_1080p`, `youtube_16x9_4k`, `reels_9x16_1080x1920`, `square_1x1_1080`, `client_master_prores` (placeholder). Loudness targets are config values — do not hardcode; ask Tyson for client-specific targets when first used.

---

# PHASES

Every phase ends with an **APPROVAL GATE**. Do not start the next phase without Tyson's OK.

---

## PHASE 0 — Environment Audit (no installs yet)

### Step 0.1 — Hardware & software inventory
- **Do:** Run read-only detection: `nvidia-smi` (GPU model, VRAM, driver, CUDA), CPU, RAM, disks + free space, OS build, Python/uv/Node/git versions, ffmpeg/ffprobe (version + enabled encoders incl. NVENC), Blender (path/version), ComfyUI (path/version if installed), Video2X, Adobe apps installed (Premiere, After Effects, Photoshop, Illustrator, Media Encoder — versions), LM Studio/Ollama if present.
- **Needs:** nothing.
- **Produces:** `docs/ENVIRONMENT_REPORT.md`.
- **Done-check:** report exists and lists every item above (found / not found).

### Step 0.2 — Pick hardware tier
- **Do:** Classify the machine and write the choice in DECISIONS.md:
  - **T1:** ≤12 GB VRAM · **T2:** 16 GB · **T3:** 24 GB · **T4:** 32 GB+
  Tier drives defaults later: local VLM size (T1: ~4–8B VLM at Q4; T3: ~27B-class at Q4), upscaler (Video2X always; SeedVR2 only T3+ or with block-swap), embeddings model size, local video sandbox (T3+ only).
- **Produces:** tier recorded in `config/studio.toml` (draft).
- **Done-check:** tier + reasoning in DECISIONS.md.

### Step 0.3 — Ask Tyson only these
- Root folders for: projects, downloads/ingest, deliveries (paths).
- Which drive holds the DB and proxies.
- Confirm ports (default HTTP 8765).

### 🛑 APPROVAL GATE 0
Show ENVIRONMENT_REPORT summary + tier + proposed paths. Wait.

---

## PHASE 1 — Studio Spine core (Registry + Naming + Queue + Ledger)

### Step 1.1 — Scaffold
- **Do:** Create repo layout (§3), `uv` project (Python 3.12), FastAPI, Typer, SQLAlchemy/SQLModel, Alembic, Jinja2, watchdog, pydantic, pytest, python `mcp` SDK. `git init`.
- **Produces:** runnable skeleton; `spine --help` works.
- **Done-check:** `uv run pytest` passes (placeholder test); `spine --help` prints commands.

### Step 1.2 — DB + migrations
- **Do:** Implement schema §6 with Alembic; SQLite in WAL mode at the path from config.
- **Done-check:** `spine db init` creates DB; migration test passes.

### Step 1.3 — Naming Authority
- **Do:** Implement §4. CLI: `spine name new --project WARAYA --shot S07 --type camref --ext mp4` → returns next unique name and reserves it.
- **Done-check:** tests: concurrency (10 parallel reservations → 10 distinct versions), no reuse after trash, collision with existing disk file detected.

### Step 1.4 — Registry
- **Do:** `spine register <path> --project --shot --type [--parent]` → probes the file (ffprobe for media), computes sha256, renames via Naming Authority (dry-run unless `--apply`), stores record, writes sidecar if enabled. `spine info <name|path>` shows lineage (parents/children, prompt, model, status). `spine status <name> approved|rejected|review`.
- **Done-check:** register a sample video + image; `spine info` shows full lineage; undo works (`spine undo <op_id>` restores original name/path).

### Step 1.5 — Job queue + GPU lock
- **Do:** SQLite-backed queue; worker loop process; `needs_gpu` jobs take a global GPU lock (one at a time); retries (`max_attempts` default 2); per-job log file; night-window scheduling flag (`--night`). CLI: `spine jobs list|retry|cancel|logs`.
- **Done-check:** enqueue 3 dummy GPU jobs + 3 CPU jobs → GPU ones run serially, CPU ones in parallel; a failing job retries once then shows `failed` with log.

### Step 1.6 — Generation Ledger
- **Do:** `spine ledger log --prompt <name> --provider magnific --model seedance-2.5 --credits N --outcome fail --tag <failure_tag>`; failure tags list in YAML (e.g. identity_drift, element_invented, wrong_duration, camera_ignored, plastic_texture, text_broken, physics_break). `spine ledger report --project WARAYA` → HTML: attempts per shot, spend, top failure tags.
- **Done-check:** seed 10 fake entries → report renders correctly.

### Step 1.7 — HTTP API + MCP server
- **Do:** Expose registry, naming, jobs, ledger via FastAPI (`/docs` works) and via MCP tools: `name_new`, `artifact_register`, `artifact_info`, `artifact_set_status`, `jobs_enqueue`, `jobs_status`, `ledger_log`, `ledger_report`. Provide the exact `claude mcp add ...` command in README.
- **Done-check:** from a Claude Code session, call `artifact_info` on a registered file and get lineage back.

### Step 1.8 — Autostart
- **Do:** PowerShell scripts to start API + worker at logon via Task Scheduler; `scripts/status.ps1`.
- **Done-check:** after logout/login the API answers on the configured port.

### 🛑 APPROVAL GATE 1
Demo: register → name → lineage → undo → queue → ledger report → MCP call. Wait.

---

## PHASE 2 — Pre-flight Engine

### Step 2.1 — Rules engine
- **Do:** Implement §5 as a rules engine reading `config/preflight_rules.yaml` with per-provider/per-model profiles. Input: prompt text + shot (scene_manifest, ref_duration) + model. Output: structured result + the 3-line block.
- **Done-check:** unit tests for each rule, including the model exceptions (`photorealistic` once on GPT Image 2.5 passes, twice fails; camera/film-stock names allowed on Nano Banana).

### Step 2.2 — Scene manifest tools
- **Do:** `spine shot manifest set S07 --elements road,tunnel,car_bg_01,...` and `spine shot manifest diff` (vs last approved). Later (Phase 6) Blender will export manifests automatically.
- **Done-check:** removing an element without `--approved` makes pre-flight FAIL.

### Step 2.3 — Integration faces
- **Do:** CLI `spine preflight <prompt_file> --shot WARAYA_S07 --model seedance-2.5`; MCP tool `preflight_check`; saving a prompt via `spine prompt save` automatically runs pre-flight and stores the result.
- **Done-check:** a prompt with a missing @tag returns FAIL listing the missing element; a clean one returns READY.

### 🛑 APPROVAL GATE 2

---

## PHASE 3 — Media Factory + Delivery QC

### Step 3.1 — Recipes (ffmpeg wrappers, all as jobs)
- **Do:** `probe`, `proxy` (half-res H.264 or ProRes Proxy, configurable), `frames` (every N s / scene changes), `audio-extract`, `contact-sheet` (grid with timecodes + filename header), `loudnorm` (two-pass, target from profile), `transcode --profile <delivery_profile>`, `batch-rename` (via Naming Authority, dry-run default). Use NVENC if available, CPU fallback.
- **Done-check:** each recipe has a test on sample media and registers its output with correct lineage.

### Step 3.2 — Technical QC checks
- **Do:** black frames, frozen frames, silence, scene cuts, duplicate consecutive frames, exposure jumps (YAVG deltas via `signalstats`), resolution/fps/pixel-format vs profile, loudness integrated + true peak vs profile, A/V duration mismatch, audio channel layout. Evaluate existing tools (e.g. `rendercheck`, `loudcheck`, MediaConch) — **wrap them if they cover a check well, don't rewrite**. Record the choice in DECISIONS.md.
- **Produces:** `spine qc <file> --profile youtube_16x9_1080p` → HTML report with PASS/FAIL per check, timestamps, thumbnails at each defect, and the exact ffmpeg fix command where applicable.
- **Done-check:** a test clip with injected black frames + a loudness error fails exactly on those checks.

### Step 3.3 — Safe-area overlay
- **Do:** generate overlay PNG/preview for title-safe/action-safe per profile (16:9, 9:16, 1:1) and a check that burns the overlay onto sampled frames for review.
- **Done-check:** overlay previews render for all profiles.

### Step 3.4 — Delivery package
- **Do:** `spine deliver <artifact> --profile ...` → transcode + QC + package folder (file + QC report + SRT if linked) named by Naming Authority; blocked if QC fails unless `--override "reason"` (logged).
- **Done-check:** end-to-end delivery on a sample.

### 🛑 APPROVAL GATE 3

---

## PHASE 4 — Local AI Gateway

### Step 4.1 — Gateway
- **Do:** Install **llama-swap** (pinned release) in front of llama.cpp server (and/or LM Studio server if Tyson prefers). Create `config/models.yaml` mapping task → model based on the hardware tier. Use a VLM whose vision path actually works in the chosen runtime (verify image input end-to-end; note: some runtimes don't wire the vision projector for newer multimodal models — test, don't assume). Configure VRAM groups/TTLs so the LLM unloads when ComfyUI needs the GPU.
- **Done-check:** OpenAI-compatible `/v1/chat/completions` works for a text task and an image task.

### Step 4.2 — Task contracts + router
- **Do:** In `spine/ai/`: each task has a pydantic output schema (e.g. `caption_image`, `tag_asset`, `classify_file`, `suggest_name_parts`, `ocr_cleanup_ar`, `summarize`, `translate_draft`). Router: tasks marked `local` go to the gateway; tasks marked `claude` go to the Claude API (key in .env, only if enabled). Retries on invalid JSON; log token usage.
- **Done-check:** swapping the model in `models.yaml` requires zero code changes; all contract tests pass on the local model.

### 🛑 APPROVAL GATE 4

---

## PHASE 5 — Subtitle & Voice Factory

### Step 5.1 — Mode A: script-known alignment (priority)
- **Do:** Given audio + the exact script text (MSA or Egyptian), run CTC forced alignment (evaluate `ctc-forced-aligner` with language `ara`; it supports word/char level) → word timestamps → subtitle segmentation → SRT/VTT.
  Arabic segmentation rules (configurable): max 2 lines, ~40 chars/line (config), min 1.0 s / max 6 s per cue, never split a chemical formula / number+unit / English term, keep Latin terms in Latin script, remove diacritics in display text optionally (flag) while keeping them for alignment.
- **Done-check:** on 3 of Tyson's real episodes, cue timing visually checked in Premiere; drift < 100 ms (measure against manual spot checks).

### Step 5.2 — Mode B: ASR (no script)
- **Do:** Build a **benchmark harness first**: 10 short Egyptian-dialect clips + Tyson-corrected transcripts → compute WER/CER (jiwer) for candidates: faster-whisper large-v3 / large-v3-turbo, WhisperX pipeline, and Egyptian-tuned models (e.g. QwenCleo-ASR — its benchmark is self-reported, so verify here). Pick the winner by numbers, record in DECISIONS.md. Then pipeline: VAD → ASR → alignment → optional diarization → SRT.
- **Done-check:** benchmark table in `docs/ASR_BENCHMARK.md`; chosen model produces SRT for a new clip.

### Step 5.3 — Voice QC (TTS vs script)
- **Do:** For generated voiceovers (ElevenLabs or Tyson's own Gemini TTS tool), run ASR on the output and diff against the script → report: skipped words, substituted words, extra words, long pauses, clipping, loudness. Hook point for his existing fact-check pipeline (ask Tyson for its location/interface; don't rebuild it).
- **Done-check:** a clip with a deliberately skipped word is flagged at the right timestamp.

### Step 5.4 — Batch + watcher
- **Do:** Batch mode for the 560-episode bank: folder of `{episode}.wav` + `{episode}.txt` → SRT + QC report per episode, all registered. Night-window capable.
- **Done-check:** 20-episode batch runs unattended; summary report lists any failures.

### 🛑 APPROVAL GATE 5

---

## PHASE 6 — Ingest Robot

### Step 6.1 — Watchers
- **Do:** Watch configured folders (downloads, cloud-export folder, deliveries). On new media: wait until file is stable → probe → match to a Ledger generation (by time window / prompt id in filename / ask via review queue if ambiguous) → register with Naming Authority (dry-run preview in the review queue until Tyson enables auto-apply per folder).
- **Done-check:** dropping 5 files produces 5 correct registrations with lineage.

### Step 6.2 — Source prep
- **Do:** If resolution < target of the project profile → enqueue upscale (Video2X by default; SeedVR2 only if tier allows — use low noise settings on already-clean AI footage and keep color correction on; verify quality on a sample before enabling as default). Then proxy + contact sheet + technical QC.
- **Done-check:** a 720p clip arrives in the project as upscaled master + proxy + contact sheet + QC report, all linked.

### Step 6.3 — Notifications
- **Do:** Windows toast notifications for finished batches/failures (and optional Telegram bot if Tyson wants phone alerts — ask).
- **Done-check:** toast appears on batch completion.

### 🛑 APPROVAL GATE 6

---

## PHASE 7 — Blender Previz Director

### Step 7.1 — Bridge
- **Do:** Install the original `blender-mcp` (MIT) for live control; build our own bpy library in `spine/blender/` for deterministic operations (do not depend on third-party forks with hundreds of unreviewed tools).
- **Done-check:** Claude can inspect the live scene and our library runs headless (`blender -b -P`).

### Step 7.2 — Previz toolkit
- **Do:** Functions: camera rig by **FOV in degrees** + height/distance/offset; spline camera moves with duration in seconds; role-colored proxy materials (color = role; green front / red back); clay / silhouette / value / thumbnail render passes; text-block placeholders for stills; light-direction markers.
- **Done-check:** a sample scene renders all 4 review passes.

### Step 7.3 — Camref export + manifest
- **Do:** Export camref video at exact target duration and fps; auto-generate the shot's `scene_manifest` from the visible objects (object names = @tags) and push it to the Registry → Pre-flight uses it automatically.
- **Done-check:** camref duration == shot ref_duration; manifest lists every visible proxy.

### 🛑 APPROVAL GATE 7

---

## PHASE 8 — Asset Brain v1

### Step 8.1 — Index
- **Do:** Image/video embeddings (evaluate a multimodal embedding model vs SigLIP-family by retrieval tests on Tyson's own assets), shot/scene detection for video (PySceneDetect; evaluate TransNetV2), keyframe embeddings, perceptual-hash near-duplicates, VLM captions + tags via Gateway (local). Vector store: pgvector (migrate to Postgres) or LanceDB — decide by benchmark, log it.
- **Done-check:** index 1,000 mixed assets unattended (night mode).

### Step 8.2 — Search UI (localhost)
- **Do:** Simple web UI: text search, search-by-image, filters (project, status, model, type), duplicates view, lineage view, approve/reject buttons writing to Registry. MCP tool `asset_search`.
- **Done-check:** "night road with red car" returns relevant shots; duplicates view finds planted duplicates.

### Step 8.3 — Reference libraries (optional)
- **Do:** Propose whether to run Immich read-only on reference/photo folders (Docker/WSL2) instead of indexing them ourselves. Ask Tyson.
- **Face grouping:** check license of any face model before use (many are non-commercial).

### 🛑 APPROVAL GATE 8

---

## PHASE 9 — Premiere Assembly & QC Markers (UXP)

### Step 9.1 — Plugin scaffold
- **Do:** Premiere UXP panel (start from Adobe's official `uxp-premiere-pro-samples`, TypeScript types from `@adobe/premierepro`). Talks to Spine HTTP API on localhost.
- **Done-check:** panel loads via UXP Developer Tool and lists Spine projects.

### Step 9.2 — Features
- **Do:** (1) Build sequence from a shot list in order (clips pre-sequenced with match transitions — never alter frame content); (2) import SRT from Voice Factory; (3) add markers from QC reports (color per severity); (4) export via delivery presets and register the export. Before building a sequence, the panel shows the plan (steps/decisions) and waits for Tyson's confirm.
- Known API gaps (e.g. time remapping) → create a marker "manual: …" instead of trying.
- **Done-check:** a 6-clip test ad assembles correctly with markers + captions.

### 🛑 APPROVAL GATE 9

---

## PHASE 10 — Chemistry Document Brain

### Step 10.1 — Ingest
- **Do:** Docling for digital PDFs; for scanned Arabic pages run a small OCR benchmark (e.g. PaddleOCR-VL, dots.ocr, a Qwen VLM) on 20 real pages from Tyson's books, measured by CER against hand-corrected text; pick by numbers. Keep page numbers and bounding boxes.
- **Done-check:** `docs/OCR_BENCHMARK.md` + one full book ingested.

### Step 10.2 — Source-locked retrieval
- **Do:** Hybrid retrieval (dense + sparse, e.g. BGE-M3) + reranker. Answers must cite chunk + page for every sentence; any sentence without support is rejected/flagged. Tools: `doc_ask`, `doc_coverage` (lesson objectives ↔ script coverage matrix), `doc_unsupported` (flags claims in a script not found in the source).
- **Done-check:** on 10 test questions, every answer cites pages; a planted unsupported claim is flagged.

### 🛑 APPROVAL GATE 10

---

## LATER BACKLOG (do not start without approval)
Visual QC Inspector (VLM frame inspection, identity consistency, hands/face flags) · ComfyUI Utility Farm (headless ComfyUI + official comfy-mcp + recipes: bg removal, interpolation, relight, inpaint, upscale) · Reference Breakdown Tool (shot-by-shot analysis of reference films) · Research Knowledge Base (Zotero + zotero-mcp + web archive + entities: stories/characters/timelines/facts/contradictions) · AE Template Render Farm (ExtendScript + aerender) · Photoshop Bridge (UXP panel ↔ ComfyUI, results as layers, correct Arabic text typeset as real text layers) · Review Room · Font Intelligence (fontTools + fontbakery + HarfBuzz Arabic coverage + FontBase collections sync file) · Windows automation fallback (pywinauto / Windows-MCP) for apps without API · Local Motion Sandbox (Wan / LTX via ComfyUI, tier T3+ only; LTX-2 license free under $10M revenue — record in LICENSES.md).

---

## DEFINITION OF DONE (every phase)
- Tests pass (`uv run pytest`).
- CLI, HTTP, and MCP faces all work for the new capability.
- `docs/RUNBOOK.md` updated: how to start, stop, and recover.
- DECISIONS.md and LICENSES.md updated.
- Demo commands printed for Tyson + progress block.
