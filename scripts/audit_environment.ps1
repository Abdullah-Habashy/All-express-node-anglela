<#
.SYNOPSIS
  Studio Spine - Phase 0 environment audit (READ-ONLY).

.DESCRIPTION
  Detects the hardware and software Studio Spine depends on and writes a Markdown report.
  Installs nothing, changes nothing, needs no admin rights. The only file written is the report.
  Local HTTP probes (ComfyUI / LM Studio / Ollama) are GET requests to 127.0.0.1 only.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\audit_environment.ps1
#>
[CmdletBinding()]
param(
    [string]$OutFile = (Join-Path $PSScriptRoot '..\docs\ENVIRONMENT_REPORT_WORKSTATION.md')
)

$ErrorActionPreference = 'SilentlyContinue'
$lines = New-Object System.Collections.Generic.List[string]

function Add-Line([string]$s = '') { $lines.Add($s) }

function Add-Row([string]$item, [string]$status, [string]$detail) {
    $clean = ($detail -replace '\|', '/') -replace "`r?`n", ' '
    Add-Line ("| {0} | {1} | {2} |" -f $item, $status, $clean)
}

# Run a native command and return its first output line (or $null if the command does not exist).
function Get-FirstLine([string]$exe, [string[]]$argv) {
    $cmd = Get-Command $exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $cmd) { return $null }
    $out = & $cmd.Source @argv 2>&1 | Select-Object -First 1
    if ($out) { return "$out".Trim() }
    return ''
}

# Return every existing path matching any of the given wildcard patterns.
function Find-Paths([string[]]$patterns) {
    $found = @()
    foreach ($p in $patterns) {
        $found += Get-Item -Path $p -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }
    }
    return $found | Select-Object -Unique
}

function Get-FileVersion([string]$path) {
    $vi = (Get-Item $path -ErrorAction SilentlyContinue).VersionInfo
    if ($vi -and $vi.ProductVersion) { return $vi.ProductVersion.Trim() }
    return 'version unknown'
}

function Test-LocalHttp([string]$url) {
    try { return Invoke-RestMethod -Uri $url -TimeoutSec 2 -UseBasicParsing } catch { return $null }
}

$fixedDrives = Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object { $_.DeviceID }

Add-Line '# Studio Spine - Workstation Environment Report'
Add-Line ''
Add-Line ("Generated: {0} on {1} by scripts/audit_environment.ps1 (read-only)." -f (Get-Date -Format 'yyyy-MM-dd HH:mm'), $env:COMPUTERNAME)
Add-Line ''

# ---------------------------------------------------------------- OS / CPU / RAM
Add-Line '## System'
Add-Line ''
Add-Line '| Item | Status | Detail |'
Add-Line '|---|---|---|'
$os = Get-CimInstance Win32_OperatingSystem
$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
Add-Row 'OS' 'found' ("{0} {1} (build {2}.{3}, {4})" -f $os.Caption, $cv.DisplayVersion, $os.BuildNumber, $cv.UBR, $os.OSArchitecture)
foreach ($cpu in Get-CimInstance Win32_Processor) {
    Add-Row 'CPU' 'found' ("{0} - {1} cores / {2} threads" -f $cpu.Name.Trim(), $cpu.NumberOfCores, $cpu.NumberOfLogicalProcessors)
}
$ramGb = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
Add-Row 'RAM' 'found' ("{0} GB" -f $ramGb)
Add-Line ''

# ---------------------------------------------------------------- GPU
Add-Line '## GPU'
Add-Line ''
Add-Line '| Item | Status | Detail |'
Add-Line '|---|---|---|'
$maxVramGb = 0
$smiPath = (Get-Command nvidia-smi -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if (-not $smiPath -and (Test-Path 'C:\Windows\System32\nvidia-smi.exe')) { $smiPath = 'C:\Windows\System32\nvidia-smi.exe' }
if ($smiPath) {
    $header = (& $smiPath 2>&1) -join "`n"
    $cuda = if ($header -match 'CUDA Version:\s*([\d\.]+)') { $Matches[1] } else { 'unknown' }
    $rows = & $smiPath --query-gpu=name,memory.total,driver_version --format=csv,noheader,nounits 2>&1
    foreach ($r in $rows) {
        $parts = "$r".Split(',') | ForEach-Object { $_.Trim() }
        if ($parts.Count -ge 3) {
            $gb = [math]::Round([double]$parts[1] / 1024, 1)
            if ($gb -gt $maxVramGb) { $maxVramGb = $gb }
            Add-Row 'NVIDIA GPU' 'found' ("{0} - {1} GB VRAM - driver {2} - CUDA {3}" -f $parts[0], $gb, $parts[2], $cuda)
        }
    }
} else {
    Add-Row 'nvidia-smi' 'NOT FOUND' 'No NVIDIA driver tools on PATH or in System32'
}
foreach ($vc in Get-CimInstance Win32_VideoController) {
    Add-Row 'Video adapter (WMI)' 'found' ("{0} - driver {1} (WMI AdapterRAM is capped at 4 GB; trust nvidia-smi for VRAM)" -f $vc.Name, $vc.DriverVersion)
}
Add-Line ''

# ---------------------------------------------------------------- Disks
Add-Line '## Disks'
Add-Line ''
Add-Line '| Drive | Label | FS | Size GB | Free GB | Physical disk |'
Add-Line '|---|---|---|---|---|---|'
foreach ($ld in Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3') {
    $media = ''
    $part = Get-Partition -DriveLetter $ld.DeviceID.TrimEnd(':') -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($part) {
        $pd = Get-PhysicalDisk -ErrorAction SilentlyContinue | Where-Object { $_.DeviceId -eq "$($part.DiskNumber)" } | Select-Object -First 1
        if ($pd) { $media = "{0} / {1} / {2}" -f $pd.MediaType, $pd.BusType, $pd.FriendlyName }
    }
    Add-Line ("| {0} | {1} | {2} | {3} | {4} | {5} |" -f $ld.DeviceID, $ld.VolumeName, $ld.FileSystem,
        [math]::Round($ld.Size / 1GB), [math]::Round($ld.FreeSpace / 1GB), $media)
}
Add-Line ''

# ---------------------------------------------------------------- Toolchain
Add-Line '## Toolchain'
Add-Line ''
Add-Line '| Item | Status | Detail |'
Add-Line '|---|---|---|'
foreach ($t in @(
        @{ n = 'Python'; e = 'python'; a = @('--version') },
        @{ n = 'uv'; e = 'uv'; a = @('--version') },
        @{ n = 'Node'; e = 'node'; a = @('--version') },
        @{ n = 'npm'; e = 'npm'; a = @('--version') },
        @{ n = 'git'; e = 'git'; a = @('--version') },
        @{ n = 'Docker'; e = 'docker'; a = @('--version') })) {
    $v = Get-FirstLine $t.e $t.a
    if ($null -eq $v) { Add-Row $t.n 'NOT FOUND' '' }
    else { Add-Row $t.n 'found' ("{0} ({1})" -f $v, (Get-Command $t.e | Select-Object -First 1).Source) }
}
$pyAll = Get-Command py -ErrorAction SilentlyContinue
if ($pyAll) { Add-Row 'Python installs (all)' 'found' ((& py -0p 2>&1) -join ' ; ') }
$wslDistros = Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss' -ErrorAction SilentlyContinue |
    ForEach-Object { (Get-ItemProperty $_.PSPath).DistributionName }
if ($wslDistros) { Add-Row 'WSL distros' 'found' ($wslDistros -join ', ') } else { Add-Row 'WSL distros' 'NOT FOUND' '' }
Add-Line ''

# ---------------------------------------------------------------- ffmpeg
Add-Line '## ffmpeg / ffprobe'
Add-Line ''
Add-Line '| Item | Status | Detail |'
Add-Line '|---|---|---|'
foreach ($e in 'ffmpeg', 'ffprobe') {
    $v = Get-FirstLine $e @('-hide_banner', '-version')
    if ($null -eq $v) { Add-Row $e 'NOT FOUND' '' } else { Add-Row $e 'found' ("{0} ({1})" -f $v, (Get-Command $e).Source) }
}
if (Get-Command ffmpeg -ErrorAction SilentlyContinue) {
    $enc = & ffmpeg -hide_banner -encoders 2>&1 | Where-Object { "$_" -match 'nvenc|_amf|_qsv|prores|libx264|libx265|libsvtav1| aac ' } |
        ForEach-Object { ("$_".Trim() -split '\s+')[1] }
    Add-Row 'Relevant encoders' 'info' ($enc -join ', ')
    & ffmpeg -hide_banner -loglevel error -f lavfi -i 'color=c=black:s=640x360:d=1' -c:v h264_nvenc -f null - 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { Add-Row 'NVENC runtime test (h264_nvenc -> null)' 'PASS' 'GPU encoding works' }
    else { Add-Row 'NVENC runtime test (h264_nvenc -> null)' 'FAIL' 'compiled-in or missing, but not usable at runtime' }
}
Add-Line ''

# ---------------------------------------------------------------- Creative / AI apps
Add-Line '## Creative and AI apps'
Add-Line ''
Add-Line '| Item | Status | Detail |'
Add-Line '|---|---|---|'

# Blender
$blender = Find-Paths @(
    "$env:ProgramFiles\Blender Foundation\*\blender.exe",
    "${env:ProgramFiles(x86)}\Steam\steamapps\common\Blender\blender.exe")
$bCmd = (Get-Command blender -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if ($bCmd) { $blender = @($bCmd) + $blender | Select-Object -Unique }
if ($blender) { foreach ($b in $blender) { Add-Row 'Blender' 'found' ("{0} ({1})" -f (Get-FileVersion $b), $b) } }
else { Add-Row 'Blender' 'NOT FOUND' '' }

# ComfyUI (folders + running server)
$comfyPatterns = @(
    "$env:USERPROFILE\*comfy*", "$env:USERPROFILE\Desktop\*comfy*", "$env:USERPROFILE\Documents\*comfy*",
    "$env:USERPROFILE\Downloads\*comfy*", "$env:LOCALAPPDATA\Programs\*comfy*")
foreach ($d in $fixedDrives) { $comfyPatterns += "$d\*comfy*"; $comfyPatterns += "$d\AI\*comfy*" }
$comfyDirs = Find-Paths $comfyPatterns | Where-Object { Test-Path $_ -PathType Container }
foreach ($c in $comfyDirs) {
    $verFile = Get-ChildItem -Path $c -Filter 'comfyui_version.py' -Recurse -Depth 2 -ErrorAction SilentlyContinue | Select-Object -First 1
    $ver = 'version unknown'
    if ($verFile -and ((Get-Content $verFile.FullName -Raw) -match '__version__\s*=\s*"([^"]+)"')) { $ver = $Matches[1] }
    Add-Row 'ComfyUI folder' 'found' ("{0} ({1})" -f $ver, $c)
}
if (-not $comfyDirs) { Add-Row 'ComfyUI folder' 'NOT FOUND' 'searched user folders and drive roots' }
foreach ($port in 8188, 8000) {
    $s = Test-LocalHttp "http://127.0.0.1:$port/system_stats"
    if ($s -and $s.system) { Add-Row "ComfyUI server :$port" 'running' ("comfyui {0}, python {1}" -f $s.system.comfyui_version, $s.system.python_version) }
}

# Video2X
$v2x = Find-Paths @(
    "$env:ProgramFiles\Video2X*\*.exe", "$env:LOCALAPPDATA\Programs\Video2X*\*.exe",
    "$env:USERPROFILE\Downloads\*video2x*\*.exe", "$env:USERPROFILE\Desktop\*video2x*\*.exe") |
    Where-Object { $_ -match 'video2x' -and $_ -notmatch 'unins' }
$vCmd = (Get-Command video2x -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if ($vCmd) { $v2x = @($vCmd) + $v2x | Select-Object -Unique }
if ($v2x) { foreach ($p in $v2x) { Add-Row 'Video2X' 'found' ("{0} ({1})" -f (Get-FileVersion $p), $p) } }
else { Add-Row 'Video2X' 'NOT FOUND' '' }

# Adobe apps (from the uninstall registry)
$uninstall = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*')
$installed = Get-ItemProperty $uninstall -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName }
foreach ($app in 'Premiere Pro', 'After Effects', 'Photoshop', 'Illustrator', 'Media Encoder') {
    $hits = $installed | Where-Object { $_.DisplayName -match "Adobe $app" } | Sort-Object DisplayName -Unique
    if ($hits) { foreach ($h in $hits) { Add-Row "Adobe $app" 'found' ("{0} - {1}" -f $h.DisplayName, $h.DisplayVersion) } }
    else {
        $dir = Find-Paths @("$env:ProgramFiles\Adobe\Adobe $app*") | Select-Object -First 1
        if ($dir) { Add-Row "Adobe $app" 'found' ("folder only: {0}" -f $dir) } else { Add-Row "Adobe $app" 'NOT FOUND' '' }
    }
}

# LM Studio
$lms = Find-Paths @(
    "$env:LOCALAPPDATA\Programs\LM Studio\LM Studio.exe", "$env:LOCALAPPDATA\Programs\lm-studio\LM Studio.exe",
    "$env:USERPROFILE\.lmstudio\bin\lms.exe", "$env:USERPROFILE\.cache\lm-studio\bin\lms.exe")
if ($lms) { foreach ($p in $lms) { Add-Row 'LM Studio' 'found' ("{0} ({1})" -f (Get-FileVersion $p), $p) } }
else { Add-Row 'LM Studio' 'NOT FOUND' '' }
$lmsApi = Test-LocalHttp 'http://127.0.0.1:1234/v1/models'
if ($lmsApi) { Add-Row 'LM Studio server :1234' 'running' ("{0} model(s) listed" -f @($lmsApi.data).Count) }

# Ollama
$ollama = (Get-Command ollama -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if (-not $ollama) { $ollama = Find-Paths @("$env:LOCALAPPDATA\Programs\Ollama\ollama.exe") | Select-Object -First 1 }
if ($ollama) { Add-Row 'Ollama' 'found' ("{0} ({1})" -f (Get-FileVersion $ollama), $ollama) } else { Add-Row 'Ollama' 'NOT FOUND' '' }
$ollamaApi = Test-LocalHttp 'http://127.0.0.1:11434/api/version'
if ($ollamaApi) { Add-Row 'Ollama server :11434' 'running' ("version {0}" -f $ollamaApi.version) }

# llama.cpp / llama-swap (Phase 4 will install these; just record if already present)
foreach ($e in 'llama-server', 'llama-swap') {
    $p = (Get-Command $e -ErrorAction SilentlyContinue | Select-Object -First 1).Source
    if ($p) { Add-Row $e 'found' $p } else { Add-Row $e 'NOT FOUND' '' }
}
Add-Line ''

# ---------------------------------------------------------------- Ports
Add-Line '## Ports'
Add-Line ''
Add-Line '| Port | Status |'
Add-Line '|---|---|'
foreach ($port in 8765, 8188, 1234, 11434) {
    $l = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($l) {
        $proc = (Get-Process -Id $l.OwningProcess -ErrorAction SilentlyContinue).ProcessName
        Add-Line ("| {0} | IN USE by {1} |" -f $port, $proc)
    } else { Add-Line ("| {0} | free |" -f $port) }
}
Add-Line ''

# ---------------------------------------------------------------- Tier suggestion (BUILD_SPEC Step 0.2)
if ($maxVramGb -ge 31) { $tier = 'T4' } elseif ($maxVramGb -ge 23) { $tier = 'T3' } elseif ($maxVramGb -ge 15) { $tier = 'T2' } else { $tier = 'T1' }
Add-Line '## Suggested hardware tier'
Add-Line ''
Add-Line ("Max NVIDIA VRAM detected: **{0} GB** -> suggested tier **{1}** (T1 <=12 GB, T2 16 GB, T3 24 GB, T4 32 GB+; reported VRAM is rounded down with ~1 GB tolerance)." -f $maxVramGb, $tier)

$dir = Split-Path -Parent $OutFile
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
$lines | Out-File -FilePath $OutFile -Encoding utf8
Write-Host ("Report written to {0}" -f (Resolve-Path $OutFile))
Write-Host ("Suggested tier: {0} (max VRAM {1} GB)" -f $tier, $maxVramGb)
