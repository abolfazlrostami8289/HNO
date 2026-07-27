#Requires -Version 5.1
<#
.SYNOPSIS
    اجراکننده همیار نجات (Launcher) - نسخه اصلاح‌شده

.DESCRIPTION
    تمام مسیرها از فایل hamyar_env.json خوانده می‌شود که توسط install.ps1 ساخته شده است.
    هیچ مسیری به صورت مستقل حدس زده نمی‌شود.

.PARAMETER ShowConsole
    نمایش زنده خروجی Ollama و Streamlit در کنسول (برای عیب‌یابی).

.PARAMETER Silent
    بدون هیچ پنجره خطا. فقط لاگ و کد خروج.

.PARAMETER Port
    اجبار به استفاده از یک پورت مشخص.

.PARAMETER Force
    اجرای نمونه جدید حتی اگر برنامه از قبل در حال اجرا باشد.
#>
[CmdletBinding()]
param(
    [switch]$ShowConsole,
    [switch]$Silent,
    [int]$Port = 0,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# Localhost must never go through a configured system proxy.
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

if (-not (Test-Path $LogsDir)) { New-Item -ItemType Directory -Path $LogsDir -Force | Out-Null }

$LogFile       = Join-Path $LogsDir 'run_debug.log'
$OllamaOutLog  = Join-Path $LogsDir 'ollama_stdout.log'
$OllamaErrLog  = Join-Path $LogsDir 'ollama_stderr.log'
$StreamlitOut  = Join-Path $LogsDir 'streamlit_stdout.log'
$StreamlitErr  = Join-Path $LogsDir 'streamlit_stderr.log'

# Rotate so each launch is diagnosable on its own.
if (Test-Path $LogFile) {
    $archive = Join-Path $LogsDir ("run_debug_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    try { Move-Item -Path $LogFile -Destination $archive -Force } catch { }
}
# Keep only the 10 newest archives.
Get-ChildItem -Path $LogsDir -Filter 'run_debug_*.log' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -Skip 10 |
    Remove-Item -Force -ErrorAction SilentlyContinue

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    try { Add-Content -Path $LogFile -Value $line -Encoding UTF8 } catch { }
    if ($ShowConsole -or $Silent) { Write-Host $line }
}

Write-Log '=========================================================='
Write-Log 'Launcher script started.'
Write-Log "BaseDir    : $BaseDir"
Write-Log "PowerShell : $($PSVersionTable.PSVersion)"

# =============================================================================
# 1. ERROR SURFACE
#    A styled window rather than a modal MessageBox, shown only on failure.
#    Suppressed entirely with -Silent.
# =============================================================================
function Show-FatalError {
    param([string]$Message, [string]$Hint = '')

    Write-Log "FATAL: $Message" 'ERROR'
    if ($Hint) { Write-Log "HINT: $Hint" 'ERROR' }
    if ($Silent) { return }

    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing

        $f = New-Object System.Windows.Forms.Form
        $f.Text            = 'خطا در اجرای همیار نجات'
        $f.Size            = New-Object System.Drawing.Size(640, 340)
        $f.StartPosition   = 'CenterScreen'
        $f.BackColor       = [System.Drawing.Color]::FromArgb(30, 30, 30)
        $f.ForeColor       = [System.Drawing.Color]::White
        $f.Font            = New-Object System.Drawing.Font('Tahoma', 10)
        $f.RightToLeft     = [System.Windows.Forms.RightToLeft]::Yes
        $f.RightToLeftLayout = $true
        $f.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
        $f.MaximizeBox     = $false

        $t = New-Object System.Windows.Forms.Label
        $t.Text      = 'برنامه اجرا نشد'
        $t.Font      = New-Object System.Drawing.Font('Tahoma', 15, [System.Drawing.FontStyle]::Bold)
        $t.ForeColor = [System.Drawing.Color]::FromArgb(220, 60, 60)
        $t.AutoSize  = $true
        $t.Location  = New-Object System.Drawing.Point(20, 18)
        $f.Controls.Add($t)

        # Read-only multiline box so long errors scroll instead of clipping.
        $b = New-Object System.Windows.Forms.TextBox
        $b.Multiline  = $true
        $b.ReadOnly   = $true
        $b.ScrollBars = 'Vertical'
        $b.Size       = New-Object System.Drawing.Size(580, 150)
        $b.Location   = New-Object System.Drawing.Point(20, 60)
        $b.BackColor  = [System.Drawing.Color]::FromArgb(45, 45, 45)
        $b.ForeColor  = [System.Drawing.Color]::White
        $b.Text       = $Message + $(if ($Hint) { "`r`n`r`n" + $Hint } else { '' })
        $f.Controls.Add($b)

        $p = New-Object System.Windows.Forms.Label
        $p.Text      = "فایل لاگ: $LogFile"
        $p.AutoSize  = $false
        $p.Size      = New-Object System.Drawing.Size(580, 30)
        $p.Location  = New-Object System.Drawing.Point(20, 220)
        $p.ForeColor = [System.Drawing.Color]::Gray
        $p.Font      = New-Object System.Drawing.Font('Tahoma', 8)
        $f.Controls.Add($p)

        $btn = New-Object System.Windows.Forms.Button
        $btn.Text      = 'بستن'
        $btn.Size      = New-Object System.Drawing.Size(120, 34)
        $btn.Location  = New-Object System.Drawing.Point(250, 255)
        $btn.BackColor = [System.Drawing.Color]::FromArgb(139, 0, 0)
        $btn.ForeColor = [System.Drawing.Color]::White
        $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
        $btn.Add_Click({ $f.Close() })
        $f.Controls.Add($btn)

        [void]$f.ShowDialog()
        $f.Dispose()
    } catch {
        Write-Log "Could not display error window: $_" 'WARNING'
    }
}

function Stop-WithError {
    param([string]$Message, [string]$Hint = '')
    Show-FatalError -Message $Message -Hint $Hint
    exit 1
}

function Get-LogTail {
    param([string]$Path, [int]$Lines = 25)
    if (-not (Test-Path $Path)) { return '(بدون خروجی)' }
    try {
        $c = @(Get-Content -Path $Path -Tail $Lines -ErrorAction Stop | Where-Object { $_.Trim() })
        if ($c.Count -eq 0) { return '(بدون خروجی)' }
        return ($c -join "`r`n")
    } catch { return '(خواندن لاگ ممکن نشد)' }
}

# =============================================================================
# 2. LOAD THE ENVIRONMENT MANIFEST
#    install.ps1 resolved every path once and recorded it here. The launcher
#    must not re-derive them — independent derivation in two scripts is exactly
#    what produced the silent empty-venv failure.
# =============================================================================
if (-not (Test-Path -LiteralPath $ManifestFile)) {
    Stop-WithError -Message "فایل تنظیمات محیط یافت نشد:`r`n$ManifestFile" `
                   -Hint   'به نظر می‌رسد نصب کامل نشده است. لطفاً ابتدا install.ps1 را اجرا کنید.'
}

try {
    $M = Get-Content -LiteralPath $ManifestFile -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
    Stop-WithError -Message "فایل تنظیمات محیط خراب است:`r`n$ManifestFile" `
                   -Hint   'نصب را دوباره اجرا کنید تا این فایل بازسازی شود.'
}
Write-Log "Manifest loaded (schema $($M.schema_version), generated $($M.generated_at))"

# Every path is validated up front. No fallbacks, no guessing.
$required = @(
    @{ Name = 'venv_python';       Path = $M.venv_python;       Type = 'Leaf'      }
    @{ Name = 'app_file';          Path = $M.app_file;          Type = 'Leaf'      }
    @{ Name = 'ollama_exe';        Path = $M.ollama_exe;        Type = 'Leaf'      }
    @{ Name = 'ollama_models_dir'; Path = $M.ollama_models_dir; Type = 'Container' }
    @{ Name = 'app_dir';           Path = $M.app_dir;           Type = 'Container' }
)
foreach ($r in $required) {
    if ([string]::IsNullOrWhiteSpace($r.Path) -or -not (Test-Path -LiteralPath $r.Path -PathType $r.Type)) {
        # NOTE: there is deliberately NO fallback to global python here.
        # The old "Falling back to global python" branch masked the real failure
        # across six consecutive test runs.
        Stop-WithError -Message "جزء ضروری برنامه یافت نشد.`r`nمورد: $($r.Name)`r`nمسیر: $($r.Path)" `
                       -Hint   'نصب ناقص است. لطفاً install.ps1 را دوباره اجرا کنید.'
    }
    Write-Log "OK $($r.Name): $($r.Path)"
}

if (-not $M.packages_verified) {
    Stop-WithError -Message 'نصب کتابخانه‌ها تأیید نشده است.' `
                   -Hint   'install.ps1 را دوباره اجرا کنید.'
}

# =============================================================================
# 3. NETWORK HELPERS
# =============================================================================
function Test-TcpPort {
    param([string]$ComputerName = '127.0.0.1', [int]$TcpPort, [int]$TimeoutMs = 600)
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $client.BeginConnect($ComputerName, $TcpPort, $null, $null)
        if ($iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) {
            $client.EndConnect($iar)
            return $true
        }
        return $false
    } catch {
        return $false
    } finally {
        $client.Close()
    }
}

function Invoke-LocalApi {
    param([string]$Uri, [int]$TimeoutSec = 5)
    try {
        return Invoke-RestMethod -Uri $Uri -Method Get -TimeoutSec $TimeoutSec -ErrorAction Stop
    } catch {
        return $null
    }
}

function Test-StreamlitHealth {
    param([int]$TcpPort)
    foreach ($path in @('/_stcore/health', '/healthz')) {
        try {
            $r = Invoke-WebRequest -Uri "http://127.0.0.1:$TcpPort$path" -UseBasicParsing `
                                   -TimeoutSec 3 -ErrorAction Stop
            if ($r.StatusCode -eq 200) { return $true }
        } catch { }
    }
    return $false
}

# =============================================================================
# 4. SINGLE-INSTANCE CHECK
#    The old script picked the next free port, so every launch spawned another
#    Streamlit server and another browser tab — concurrent writers to the same
#    chat_history.json. Reuse a healthy instance instead.
# =============================================================================
$CandidatePorts = if ($Port -gt 0) { @($Port) } else { @(8501, 8502, 8503, 8504) }

if (-not $Force -and $Port -eq 0) {
    foreach ($p in $CandidatePorts) {
        if ((Test-TcpPort -TcpPort $p) -and (Test-StreamlitHealth -TcpPort $p)) {
            Write-Log "Existing healthy instance found on port $p. Reusing it."
            Start-Process "http://127.0.0.1:$p"
            Write-Log 'Browser opened against existing instance. Exiting.'
            exit 0
        }
    }
}

# =============================================================================
# 5. OLLAMA ENVIRONMENT AND STARTUP
#    Models are used in place via OLLAMA_MODELS, and ollama.exe is invoked by
#    absolute path — the launcher never depends on the Windows PATH.
# =============================================================================
$OllamaHost = if ($M.ollama_host) { $M.ollama_host } else { '127.0.0.1:11434' }

$env:OLLAMA_HOST       = $OllamaHost
$env:OLLAMA_MODELS     = $M.ollama_models_dir
$env:OLLAMA_KEEP_ALIVE = '30m'   # keeps the 8B model resident between questions
$env:OLLAMA_NOPRUNE    = '1'     # never delete blobs we shipped deliberately
$env:NO_PROXY          = '127.0.0.1,localhost'

Write-Log "OLLAMA_HOST   = $env:OLLAMA_HOST"
Write-Log "OLLAMA_MODELS = $env:OLLAMA_MODELS"

$OllamaBase = "http://$OllamaHost"
$OllamaProc = $null

if (Invoke-LocalApi -Uri "$OllamaBase/api/tags" -TimeoutSec 3) {
    # A process existing is not the same as the API being reachable, which is
    # why the old Get-Process check was unreliable. This tests the API itself.
    Write-Log 'Ollama API already responding. Reusing the running server.'
    Write-Log 'NOTE: a pre-existing server may use a different models directory.' 'WARNING'
} else {
    Write-Log "Starting Ollama: $($M.ollama_exe) serve"

    $ollamaSplat = @{
        FilePath     = $M.ollama_exe
        ArgumentList = 'serve'
        PassThru     = $true
    }
    if ($ShowConsole) {
        $ollamaSplat.NoNewWindow = $true
    } else {
        $ollamaSplat.WindowStyle             = 'Hidden'
        $ollamaSplat.RedirectStandardOutput  = $OllamaOutLog
        $ollamaSplat.RedirectStandardError   = $OllamaErrLog
    }

    try {
        $OllamaProc = Start-Process @ollamaSplat
        Write-Log "Ollama process started (PID $($OllamaProc.Id))"
    } catch {
        Stop-WithError -Message "اجرای موتور Ollama ممکن نشد.`r`n$($_.Exception.Message)" `
                       -Hint   "مسیر: $($M.ollama_exe)"
    }

    # Poll for readiness rather than sleeping a fixed 2 seconds.
    Write-Log 'Waiting for Ollama API...'
    $ready = $false
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt 90) {
        if ($OllamaProc -and $OllamaProc.HasExited) {
            $tail = Get-LogTail $OllamaErrLog 20
            Stop-WithError -Message "موتور Ollama بلافاصله متوقف شد (کد $($OllamaProc.ExitCode)).`r`n`r`n$tail" `
                           -Hint   'احتمالاً پورت 11434 توسط برنامه دیگری اشغال است.'
        }
        if (Invoke-LocalApi -Uri "$OllamaBase/api/tags" -TimeoutSec 3) { $ready = $true; break }
        Start-Sleep -Milliseconds 700
    }
    if (-not $ready) {
        Stop-WithError -Message "موتور Ollama در زمان مجاز آماده نشد (۹۰ ثانیه).`r`n`r`n$(Get-LogTail $OllamaErrLog 20)" `
                       -Hint   "لاگ: $OllamaErrLog"
    }
    Write-Log "Ollama API ready after $([int]$sw.Elapsed.TotalSeconds)s"
}

# -----------------------------------------------------------------------------
# 5b. Verify the required models are actually visible to this server.
#     If a pre-existing Ollama is serving a different models directory, the
#     hand-copied models are invisible and every chat turn fails at runtime.
# -----------------------------------------------------------------------------
$RequiredModels = @('aya-expanse:8b', 'bge-m3')
$tags = Invoke-LocalApi -Uri "$OllamaBase/api/tags" -TimeoutSec 10
$available = @()
if ($tags -and $tags.models) { $available = @($tags.models | ForEach-Object { $_.name }) }
Write-Log "Models visible to Ollama: $($available -join ', ')"

$missing = @()
foreach ($need in $RequiredModels) {
    $bare = $need.Split(':')[0]
    $hit = $available | Where-Object { $_ -eq $need -or $_ -eq "$need`:latest" -or $_ -like "$bare`:*" }
    if (-not $hit) { $missing += $need }
}
if ($missing.Count -gt 0) {
    Stop-WithError -Message ("مدل‌های زبانی مورد نیاز در دسترس نیستند:`r`n  " + ($missing -join "`r`n  ") +
                             "`r`n`r`nمدل‌های موجود: " + $(if ($available.Count) { $available -join ', ' } else { 'هیچ' })) `
                   -Hint   ("پوشه مدل‌ها: $($M.ollama_models_dir)`r`n" +
                            'اگر نسخه دیگری از Ollama در حال اجراست، ابتدا آن را ببندید و دوباره تلاش کنید.')
}
Write-Log 'Required models verified.'

# =============================================================================
# 6. PORT SELECTION
# =============================================================================
$SelectedPort = 0
foreach ($p in $CandidatePorts) {
    if (-not (Test-TcpPort -TcpPort $p -TimeoutMs 300)) { $SelectedPort = $p; break }
}
if ($SelectedPort -eq 0) {
    Stop-WithError -Message ("تمام پورت‌های برنامه اشغال هستند: " + ($CandidatePorts -join ', ')) `
                   -Hint   'برنامه‌های مشابه را ببندید یا با پارامتر -Port یک پورت دیگر بدهید.'
}
Write-Log "Selected available port: $SelectedPort"

# =============================================================================
# 7. START STREAMLIT
#    Output is ALWAYS redirected to log files. The old script combined
#    -WindowStyle Hidden with no redirection, so a ModuleNotFoundError was
#    completely invisible and the browser simply opened onto a dead port.
# =============================================================================
Write-Log "Starting Streamlit from $($M.venv_python)"
Write-Log "Working directory: $($M.app_dir)"

# Clear previous run output so the tail we read on failure is from this launch.
foreach ($f in @($StreamlitOut, $StreamlitErr)) {
    Set-Content -Path $f -Value '' -Encoding UTF8 -ErrorAction SilentlyContinue
}

$env:STREAMLIT_BROWSER_GATHER_USAGE_STATS = 'false'
$env:STREAMLIT_SERVER_HEADLESS            = 'true'
$env:PYTHONUNBUFFERED                     = '1'
$env:PYTHONIOENCODING                     = 'utf-8'

$stArgs = @(
    '-m', 'streamlit', 'run', "`"$($M.app_file)`""
    '--server.port', $SelectedPort
    '--server.address', '127.0.0.1'
    '--server.headless', 'true'
    '--server.fileWatcherType', 'none'
    '--browser.gatherUsageStats', 'false'
    '--global.developmentMode', 'false'
) -join ' '

$stSplat = @{
    FilePath         = $M.venv_python
    ArgumentList     = $stArgs
    WorkingDirectory = $M.app_dir      # so .streamlit/config.toml is picked up
    PassThru         = $true
}
if ($ShowConsole) {
    # Live output for debugging.
    $stSplat.NoNewWindow = $true
} else {
    $stSplat.WindowStyle            = 'Hidden'
    $stSplat.RedirectStandardOutput = $StreamlitOut
    $stSplat.RedirectStandardError  = $StreamlitErr
}

try {
    $StProc = Start-Process @stSplat
    Write-Log "Streamlit process started (PID $($StProc.Id))"
} catch {
    Stop-WithError -Message "اجرای Streamlit ممکن نشد.`r`n$($_.Exception.Message)" `
                   -Hint   "مفسر: $($M.venv_python)"
}

# -----------------------------------------------------------------------------
# 7b. Wait for the port to actually serve, and catch an early crash.
# -----------------------------------------------------------------------------
Write-Log 'Waiting for Streamlit to become ready...'
$ready = $false
$sw = [System.Diagnostics.Stopwatch]::StartNew()

while ($sw.Elapsed.TotalSeconds -lt 120) {
    if ($StProc.HasExited) {
        # This is the case that used to fail silently.
        $err = Get-LogTail $StreamlitErr 25
        $out = Get-LogTail $StreamlitOut 15
        Write-Log "Streamlit exited early with code $($StProc.ExitCode)" 'ERROR'
        Write-Log "stderr:`r`n$err" 'ERROR'

        $hint = "لاگ کامل: $StreamlitErr"
        if ("$err`n$out" -match "No module named '?([A-Za-z0-9_\.]+)") {
            $hint = "کتابخانه '$($Matches[1])' نصب نشده است. install.ps1 را دوباره اجرا کنید.`r`n$hint"
        }
        Stop-WithError -Message "Streamlit بلافاصله متوقف شد (کد $($StProc.ExitCode)).`r`n`r`n$err" -Hint $hint
    }

    if ((Test-TcpPort -TcpPort $SelectedPort -TimeoutMs 400) -and (Test-StreamlitHealth -TcpPort $SelectedPort)) {
        $ready = $true
        break
    }
    Start-Sleep -Milliseconds 600
}

if (-not $ready) {
    Stop-WithError -Message ("Streamlit در زمان مجاز آماده نشد (۱۲۰ ثانیه).`r`n`r`n" + (Get-LogTail $StreamlitErr 25)) `
                   -Hint   "لاگ: $StreamlitErr"
}
Write-Log "Streamlit ready on port $SelectedPort after $([int]$sw.Elapsed.TotalSeconds)s"

# =============================================================================
# 8. RECORD PIDS (so a stop script can shut everything down cleanly)
# =============================================================================
try {
    $pids = [ordered]@{
        started_at    = (Get-Date -Format 'o')
        port          = $SelectedPort
        streamlit_pid = $StProc.Id
        ollama_pid    = $(if ($OllamaProc) { $OllamaProc.Id } else { $null })
        ollama_owned  = [bool]$OllamaProc   # false if we attached to an existing server
    }
    $pids | ConvertTo-Json | Set-Content -Path $PidFile -Encoding UTF8
    Write-Log "PID file written: $PidFile"
} catch {
    Write-Log "Could not write PID file: $_" 'WARNING'
}

# =============================================================================
# 9. OPEN THE BROWSER
#    Only now, once the server has genuinely answered a health check.
#    127.0.0.1 rather than localhost: on Windows, localhost can resolve to ::1
#    first while the server is bound to IPv4.
# =============================================================================
$url = "http://127.0.0.1:$SelectedPort"
Write-Log "Opening browser at $url"
try {
    Start-Process $url
} catch {
    Write-Log "Failed to open browser automatically: $_" 'WARNING'
    Show-FatalError -Message "برنامه اجرا شد اما مرورگر باز نشد.`r`nلطفاً این آدرس را در مرورگر باز کنید:`r`n$url"
}

Write-Log 'Launcher completed successfully.'
exit 0
