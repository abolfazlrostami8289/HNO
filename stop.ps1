#Requires -Version 5.1
<#
.SYNOPSIS
    خاموش‌کننده امن همیار نجات

.DESCRIPTION
    مدل‌های زبانی را از حافظه خارج می‌کند و سپس فرآیندهای Streamlit و Ollama
    را به همراه تمام زیرفرآیندهایشان می‌بندد.

    ایمنی: پیش از بستن هر فرآیند، هویت آن (مسیر فایل اجرایی و زمان شروع)
    بررسی می‌شود تا در صورت بازاستفاده شدن شناسه فرآیند توسط ویندوز،
    برنامه دیگری به اشتباه بسته نشود.

.PARAMETER Force
    بستن Ollama حتی اگر توسط این برنامه اجرا نشده باشد.

.PARAMETER All
    جستجو و بستن تمام فرآیندهای مرتبط بر اساس مسیر فایل اجرایی،
    حتی اگر فایل hamyar_pids.json موجود نباشد.

.PARAMETER Silent
    بدون هیچ پنجره‌ای. فقط لاگ و کد خروج.
#>
[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$All,
    [switch]$Silent,
    [int]$TimeoutSeconds = 15
)

$ErrorActionPreference = 'Stop'
[System.Net.WebRequest]::DefaultWebProxy = $null

# =============================================================================
# 0. PATHS AND LOGGING
# =============================================================================
$BaseDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($BaseDir)) {
    $BaseDir = Split-Path -Parent -Path $MyInvocation.MyCommand.Path
}

$LogsDir      = Join-Path $BaseDir 'logs'
$ManifestFile = Join-Path $BaseDir 'hamyar_env.json'
$PidFile      = Join-Path $LogsDir 'hamyar_pids.json'
$LogFile      = Join-Path $LogsDir 'stop_debug.log'

if (-not (Test-Path $LogsDir)) { New-Item -ItemType Directory -Path $LogsDir -Force | Out-Null }

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    try { Add-Content -Path $LogFile -Value $line -Encoding UTF8 } catch { }
    Write-Host $line
}

Write-Log '=========================================================='
Write-Log 'Shutdown script started.'

# =============================================================================
# 1. LOAD CONTEXT (best effort - the stop script must work even if these are
#    missing, otherwise a half-broken install can never be cleaned up)
# =============================================================================
$M = $null
if (Test-Path -LiteralPath $ManifestFile) {
    try {
        $M = Get-Content -LiteralPath $ManifestFile -Raw -Encoding UTF8 | ConvertFrom-Json
        Write-Log 'Manifest loaded.'
    } catch {
        Write-Log "Manifest unreadable: $_" 'WARNING'
    }
} else {
    Write-Log 'Manifest not found; running in reduced-safety mode.' 'WARNING'
}

$P = $null
if (Test-Path -LiteralPath $PidFile) {
    try {
        $P = Get-Content -LiteralPath $PidFile -Raw -Encoding UTF8 | ConvertFrom-Json
        Write-Log "PID file loaded: streamlit=$($P.streamlit_pid) ollama=$($P.ollama_pid) owned=$($P.ollama_owned) port=$($P.port)"
    } catch {
        Write-Log "PID file unreadable: $_" 'WARNING'
    }
} else {
    Write-Log 'PID file not found.' 'WARNING'
}

if (-not $P -and -not $All) {
    Write-Log 'Nothing recorded to stop. Use -All to sweep by executable path.'
}

# =============================================================================
# 2. PROCESS HELPERS
# =============================================================================
function Get-ProcInfo {
    param([int]$TargetPid)
    if ($TargetPid -le 0) { return $null }
    try {
        return Get-CimInstance Win32_Process -Filter "ProcessId = $TargetPid" -ErrorAction Stop
    } catch {
        return $null
    }
}

function Test-ProcessIdentity {
    <#
      Guards against PID reuse. Windows recycles process IDs, so a recorded PID
      may now belong to something completely unrelated. We require the
      executable path to match, and the process to have started no earlier than
      the launcher run that recorded it.
    #>
    param(
        [int]$TargetPid,
        [string]$ExpectedPath,
        [string]$ExpectedNameLike,
        [datetime]$NotBefore = [datetime]::MinValue
    )

    $info = Get-ProcInfo -TargetPid $TargetPid
    if (-not $info) {
        Write-Log "PID $TargetPid is not running."
        return $false
    }

    if ($ExpectedPath -and $info.ExecutablePath) {
        if ($info.ExecutablePath -ne $ExpectedPath) {
            Write-Log "PID $TargetPid path mismatch (expected '$ExpectedPath', found '$($info.ExecutablePath)'). Refusing to stop." 'WARNING'
            return $false
        }
    } elseif ($ExpectedNameLike) {
        # ExecutablePath can be empty when we lack rights to read it.
        if ($info.Name -notlike $ExpectedNameLike) {
            Write-Log "PID $TargetPid name mismatch (expected '$ExpectedNameLike', found '$($info.Name)'). Refusing to stop." 'WARNING'
            return $false
        }
    }

    if ($NotBefore -gt [datetime]::MinValue -and $info.CreationDate) {
        # 60s tolerance for clock granularity between the two scripts.
        if ($info.CreationDate -lt $NotBefore.AddSeconds(-60)) {
            Write-Log "PID $TargetPid started before this session ($($info.CreationDate)). Refusing to stop." 'WARNING'
            return $false
        }
    }

    return $true
}

function Get-DescendantIds {
    param([int]$ParentId, [int]$Depth = 0)
    if ($Depth -gt 6) { return @() }   # guard against pathological trees
    $ids = @()
    try {
        $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId = $ParentId" -ErrorAction SilentlyContinue)
    } catch {
        return @()
    }
    foreach ($c in $children) {
        $ids += [int]$c.ProcessId
        $ids += Get-DescendantIds -ParentId ([int]$c.ProcessId) -Depth ($Depth + 1)
    }
    return $ids
}

function Get-WorkingSetMB {
    param([int[]]$Ids)
    $total = 0
    foreach ($i in $Ids) {
        try {
            $p = Get-Process -Id $i -ErrorAction Stop
            $total += $p.WorkingSet64
        } catch { }
    }
    return [math]::Round($total / 1MB, 1)
}

function Stop-ProcessTree {
    <#
      Terminates descendants first, then the parent. Ollama spawns separate
      model-runner child processes which hold the bulk of the RAM; killing only
      the parent can leave those orphaned and resident.
    #>
    param([int]$RootPid, [string]$Label)

    $descendants = @(Get-DescendantIds -ParentId $RootPid | Sort-Object -Unique)
    $all = @($descendants) + @($RootPid)
    $mb = Get-WorkingSetMB -Ids $all
    Write-Log "$Label tree: PID $RootPid plus $($descendants.Count) child process(es), holding $mb MB."

    # Pass 1 - polite close for anything that owns a window.
    foreach ($id in $all) {
        try {
            $proc = Get-Process -Id $id -ErrorAction Stop
            if ($proc.MainWindowHandle -ne 0) {
                [void]$proc.CloseMainWindow()
                Write-Log "Sent close request to PID $id."
            }
        } catch { }
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt 3) {
        $alive = @($all | Where-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue })
        if ($alive.Count -eq 0) { break }
        Start-Sleep -Milliseconds 250
    }

    # Pass 2 - terminate children first, then the root.
    foreach ($id in ($descendants + @($RootPid))) {
        try {
            if (Get-Process -Id $id -ErrorAction SilentlyContinue) {
                Stop-Process -Id $id -Force -ErrorAction Stop
                Write-Log "Terminated PID $id."
            }
        } catch {
            Write-Log "Could not terminate PID $id : $($_.Exception.Message)" 'WARNING'
        }
    }

    # Confirm.
    $sw.Restart()
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        $alive = @($all | Where-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue })
        if ($alive.Count -eq 0) {
            Write-Log "$Label stopped cleanly. Freed approximately $mb MB."
            return $true
        }
        Start-Sleep -Milliseconds 300
    }

    $stubborn = @($all | Where-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue })
    Write-Log "$Label: $($stubborn.Count) process(es) still running: $($stubborn -join ', ')" 'WARNING'
    return $false
}

# =============================================================================
# 3. UNLOAD MODELS FROM RAM FIRST
#    Ollama exposes keep_alive=0 to evict a loaded model. Doing this before
#    termination releases the several GB an 8B model occupies in an orderly
#    way, rather than relying on process teardown.
# =============================================================================
function Invoke-ModelUnload {
    $ollamaHost = if ($M -and $M.ollama_host) { $M.ollama_host } else { '127.0.0.1:11434' }
    $base = "http://$ollamaHost"

    $running = $null
    try {
        $running = Invoke-RestMethod -Uri "$base/api/ps" -Method Get -TimeoutSec 5 -ErrorAction Stop
    } catch {
        Write-Log 'Ollama API not responding; skipping graceful model unload.'
        return
    }

    if (-not $running -or -not $running.models -or @($running.models).Count -eq 0) {
        Write-Log 'No models currently loaded in memory.'
        return
    }

    foreach ($model in $running.models) {
        $name = $model.name
        $sizeMB = if ($model.size) { [math]::Round($model.size / 1MB, 0) } else { 0 }
        Write-Log "Unloading model '$name' ($sizeMB MB) from memory..."
        try {
            $body = @{ model = $name; keep_alive = 0 } | ConvertTo-Json -Compress
            Invoke-RestMethod -Uri "$base/api/generate" -Method Post -Body $body `
                              -ContentType 'application/json' -TimeoutSec 30 -ErrorAction Stop | Out-Null
            Write-Log "Model '$name' unloaded."
        } catch {
            Write-Log "Could not unload '$name': $($_.Exception.Message)" 'WARNING'
        }
    }
    Start-Sleep -Seconds 1
}

# =============================================================================
# 4. SHUTDOWN SEQUENCE
# =============================================================================
$stoppedAnything = $false
$startedAt = [datetime]::MinValue
if ($P -and $P.started_at) {
    try { $startedAt = [datetime]::Parse($P.started_at) } catch { }
}

Invoke-ModelUnload

# ---- 4a. Streamlit -----------------------------------------------------------
if ($P -and $P.streamlit_pid) {
    $expected = if ($M) { $M.venv_python } else { $null }
    if (Test-ProcessIdentity -TargetPid ([int]$P.streamlit_pid) -ExpectedPath $expected `
                             -ExpectedNameLike 'python*.exe' -NotBefore $startedAt) {
        if (Stop-ProcessTree -RootPid ([int]$P.streamlit_pid) -Label 'Streamlit') { $stoppedAnything = $true }
    }
} else {
    Write-Log 'No Streamlit PID recorded.'
}

# ---- 4b. Ollama --------------------------------------------------------------
if ($P -and $P.ollama_pid) {
    if (-not $P.ollama_owned -and -not $Force) {
        # The launcher attached to a server it did not start. Something else on
        # this machine may depend on it, so we leave it alone by default.
        Write-Log 'Ollama was already running before launch and is not owned by this app. Leaving it running (use -Force to stop it anyway).'
    } else {
        $expected = if ($M) { $M.ollama_exe } else { $null }
        if (Test-ProcessIdentity -TargetPid ([int]$P.ollama_pid) -ExpectedPath $expected `
                                 -ExpectedNameLike 'ollama*.exe' -NotBefore $startedAt) {
            if (Stop-ProcessTree -RootPid ([int]$P.ollama_pid) -Label 'Ollama') { $stoppedAnything = $true }
        }
    }
} else {
    Write-Log 'No Ollama PID recorded.'
}

# ---- 4c. Optional sweep by executable path ----------------------------------
# Targets ONLY the exact binaries this installation owns, so a separate Python
# or Ollama installation elsewhere on the machine is never touched.
if ($All) {
    Write-Log 'Sweeping for stray processes belonging to this installation...'
    $targets = @()
    if ($M -and $M.venv_python) { $targets += $M.venv_python }
    if ($M -and $M.ollama_exe)  { $targets += $M.ollama_exe }

    if ($targets.Count -eq 0) {
        Write-Log 'No manifest paths available; sweep skipped.' 'WARNING'
    } else {
        foreach ($exe in $targets) {
            $escaped = $exe.Replace('\', '\\')
            $found = @(Get-CimInstance Win32_Process -Filter "ExecutablePath = '$escaped'" -ErrorAction SilentlyContinue)
            foreach ($f in $found) {
                Write-Log "Stray process found: PID $($f.ProcessId) ($exe)"
                if (Stop-ProcessTree -RootPid ([int]$f.ProcessId) -Label 'Stray') { $stoppedAnything = $true }
            }
        }
    }
}

# =============================================================================
# 5. CLEAN UP
# =============================================================================
if (Test-Path -LiteralPath $PidFile) {
    try {
        Remove-Item -LiteralPath $PidFile -Force
        Write-Log 'PID file removed.'
    } catch {
        Write-Log "Could not remove PID file: $_" 'WARNING'
    }
}

if ($stoppedAnything) {
    Write-Log 'Shutdown completed. همیار نجات بسته شد.'
} else {
    Write-Log 'Nothing was running. برنامه از قبل بسته بود.'
}

if (-not $Silent -and -not $stoppedAnything -and -not $All) {
    Write-Host ''
    Write-Host 'برنامه در حال اجرا نبود.' -ForegroundColor Yellow
    Start-Sleep -Seconds 2
}

exit 0
