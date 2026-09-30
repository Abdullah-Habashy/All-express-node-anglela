# Studio Spine — Environment Report (Phase 0, Step 0.1)

Date: 2026-09-30 · Method: read-only detection, nothing installed.

## ⚠️ Scope — read this first

This audit ran inside the **Claude Code cloud container** (Ubuntu 24.04 VM), **not on Tyson's Windows workstation**.
The container has no GPU, no Windows, no Adobe apps, and no access to the workstation's drives.
So Section A is accurate for the build/CI box only. **It says nothing about the production machine.**

The real workstation audit is `scripts/audit_environment.ps1` (read-only, no admin, installs nothing).
It writes `docs/ENVIRONMENT_REPORT_WORKSTATION.md` covering every item in Step 0.1 plus a suggested tier.
Section B stays **PENDING** until that report exists.

```powershell
# On the workstation, from the repo root:
powershell -ExecutionPolicy Bypass -File scripts\audit_environment.ps1
```

---

## A. Cloud build container (audited 2026-09-30)

| Item | Status | Detail |
|---|---|---|
| OS | found | Ubuntu 24.04.4 LTS, Linux 6.18.44 x86_64 (VM) |
| CPU | found | Intel Xeon @ 2.10 GHz, 4 cores / 4 threads |
| RAM | found | 15 GiB, no swap |
| Disk `/` | found | 252 GB volume, **~30 GB writable allowance** for this session |
| GPU / `nvidia-smi` | **NOT FOUND** | no `/dev/nvidia*`, no `libcuda` |
| CUDA | **NOT FOUND** | no driver, no `nvcc`, no `torch` |
| Python | found | 3.11.15 (default `python3`), **3.12.3** available as `python3.12` |
| uv | found | 0.8.17 |
| Node / npm | found | v22.22.0 / 10.9.4 |
| git | found | 2.43.0 |
| ffmpeg / ffprobe | found | 6.1.1 (Ubuntu build, GPL) |
| ffmpeg encoders | info | libx264, libx265, libsvtav1, prores / prores_ks, aac; `h264_nvenc`/`hevc_nvenc`/`av1_nvenc` compiled in |
| NVENC runtime | **FAIL** | test encode produced no packets — no NVIDIA driver (expected) |
| Blender | NOT FOUND | |
| ComfyUI | NOT FOUND | |
| Video2X | NOT FOUND | |
| Adobe Premiere Pro | NOT FOUND | Linux — not possible here |
| Adobe After Effects | NOT FOUND | Linux — not possible here |
| Adobe Photoshop | NOT FOUND | Linux — not possible here |
| Adobe Illustrator | NOT FOUND | Linux — not possible here |
| Adobe Media Encoder | NOT FOUND | Linux — not possible here |
| LM Studio | NOT FOUND | |
| Ollama | NOT FOUND | |
| llama.cpp / llama-swap | NOT FOUND | (Phase 4 installs these) |
| Docker | found | 29.6.2 (extra, not required) |
| PowerShell | NOT FOUND | so `audit_environment.ps1` was **not executed here** |
| Port 8765 | free | |

**What this box is good for:** writing and testing the pure-Python core (Registry, Naming, Queue, Ledger, Pre-flight)
and CPU-only ffmpeg recipes. It is **not** a valid target for GPU, NVENC, Adobe, Blender, Task Scheduler, or Windows paths.

---

## B. Tyson's Windows workstation — PENDING

Run `scripts/audit_environment.ps1` and commit `docs/ENVIRONMENT_REPORT_WORKSTATION.md`, or paste its contents in chat.
It checks: OS build · CPU · RAM · every fixed disk (size, free, SSD/HDD, bus) · NVIDIA GPU (model, VRAM, driver, CUDA) ·
Python/uv/Node/npm/git/Docker/WSL · ffmpeg/ffprobe version + encoders + a real NVENC test encode ·
Blender · ComfyUI (folders + running server on :8188/:8000) · Video2X · Premiere / After Effects / Photoshop /
Illustrator / Media Encoder versions · LM Studio · Ollama · llama.cpp / llama-swap · ports 8765/8188/1234/11434 ·
suggested hardware tier.
