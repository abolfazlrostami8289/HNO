#Requires -Version 5.1
<#
.SYNOPSIS
    نصب‌کننده گرافیکی و آفلاین همیار نجات (نسخه اصلاح‌شده)

.DESCRIPTION
    ایجاد محیط مجازی پایتون و نصب کاملاً آفلاین کتابخانه‌ها از پوشه libraries.
    بدون تغییر PATH ویندوز، بدون نیاز به دسترسی ادمین، بدون پیام‌های بازشو.

.PARAMETER Silent
    اجرای کامل بدون رابط گرافیکی (فقط لاگ). کد خروج ۰ در صورت موفقیت، ۱ در صورت خطا.

.PARAMETER UseSystemPython
    استفاده از پایتون نصب‌شده روی سیستم به جای پایتون همراه پکیج.
#>
[CmdletBinding()]
param(
    [switch]$Silent,
    [switch]$UseSystemPython
)

$ErrorActionPreference = 'Stop'

# =============================================================================
# 0. RESOLVE PATHS
#    $PSScriptRoot is the only reliable way to get the script directory.
#    $MyInvocation.MyCommand.Definition (used previously) returns different
#    values depending on invocation context and was the root cause of the
#    path-mismatch bugs.
# =============================================================================
$BaseDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($BaseDir)) {
    $BaseDir = Split-Path -Parent -Path $MyInvocation.MyCommand.Path
}

$PackageDir    = Join-Path $BaseDir 'HamyarNejat_Package'
$InstallersDir = Join-Path $PackageDir 'installers'
$LibrariesDir  = Join-Path $PackageDir 'libraries'
$LogsDir       = Join-Path $BaseDir   'logs'
$VenvDir       = Join-Path $BaseDir   'venv'
$PythonDir     = Join-Path $BaseDir   'python'          # bundled Python target
$ManifestFile  = Join-Path $BaseDir   'hamyar_env.json'

$LogFile     = Join-Path $LogsDir 'install_debug.log'
$PipOutLog   = Join-Path $LogsDir 'pip_stdout.log'
$PipErrLog   = Join-Path $LogsDir 'pip_stderr.log'
$ProbeOutLog = Join-Path $LogsDir 'probe_stdout.log'
$ProbeErrLog = Join-Path $LogsDir 'probe_stderr.log'

if (-not (Test-Path $LogsDir)) { New-Item -ItemType Directory -Path $LogsDir -Force | Out-Null }

# Candidate locations for requirements.txt, in priority order.
# THE BUG: the original script only ever checked the first entry.
$RequirementsCandidates = @(
    (Join-Path $LibrariesDir 'requirements.lock.txt')
    (Join-Path $LibrariesDir 'requirements.txt')
    (Join-Path $BaseDir      'requirements.lock.txt')
    (Join-Path $BaseDir      'requirements.txt')
    (Join-Path $PackageDir   'requirements.txt')
    (Join-Path $PackageDir   'app\requirements.txt')
)

# Candidate locations for the Streamlit entry point.
$AppCandidates = @(
    (Join-Path $PackageDir 'app\app.py')
    (Join-Path $BaseDir    'app.py')
    (Join-Path $PackageDir 'app.py')
)

# =============================================================================
# 1. LOGGING
# =============================================================================
function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    try { Add-Content -Path $LogFile -Value $line -Encoding UTF8 } catch { }
    if ($Silent) { Write-Host $line }
    trap {
    Write-Log "UNHANDLED: $($_.Exception.Message)" 'ERROR'
    Write-Log "$($_.ScriptStackTrace)" 'ERROR'
    Write-Host "FATAL: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
}


# Rotate the previous log so each run is diagnosable in isolation.
if (Test-Path $LogFile) {
    $archive = Join-Path $LogsDir ("install_debug_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    try { Move-Item -Path $LogFile -Destination $archive -Force } catch { }
}

Write-Log "=========================================================="
Write-Log "Installation script started."
Write-Log "BaseDir      : $BaseDir"
Write-Log "PowerShell   : $($PSVersionTable.PSVersion)"
Write-Log "OS           : $([System.Environment]::OSVersion.VersionString)"
Write-Log "User         : $env:USERNAME (elevated=$([bool](New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)))"

# =============================================================================
# 2. GUI (auto-runs; no Start button, no MessageBox, no user prompts)
# =============================================================================
$Form = $null; $LabelStatus = $null; $ProgressBar = $null; $LabelDetail = $null

if (-not $Silent) {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $Form = New-Object System.Windows.Forms.Form
    $Form.Text            = 'نصب‌کننده همیار نجات'
    $Form.Size            = New-Object System.Drawing.Size(620, 300)
    $Form.StartPosition   = 'CenterScreen'
    $Form.BackColor       = [System.Drawing.Color]::FromArgb(30, 30, 30)
    $Form.ForeColor       = [System.Drawing.Color]::White
    $Form.Font            = New-Object System.Drawing.Font('Tahoma', 10)
    $Form.RightToLeft     = [System.Windows.Forms.RightToLeft]::Yes
    $Form.RightToLeftLayout = $true
    $Form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $Form.MaximizeBox     = $false
    $Form.MinimizeBox     = $false

    $LabelTitle = New-Object System.Windows.Forms.Label
    $LabelTitle.Text      = 'نصب‌کننده همیار نجات'
    $LabelTitle.Font      = New-Object System.Drawing.Font('Tahoma', 16, [System.Drawing.FontStyle]::Bold)
    $LabelTitle.ForeColor = [System.Drawing.Color]::FromArgb(200, 0, 0)
    $LabelTitle.AutoSize  = $true
    $LabelTitle.Location  = New-Object System.Drawing.Point(20, 18)
    $Form.Controls.Add($LabelTitle)

    # Multi-line, scrollable-height status so long Persian error text is not clipped.
    $LabelStatus = New-Object System.Windows.Forms.Label
    $LabelStatus.Text      = 'در حال آماده‌سازی...'
    $LabelStatus.AutoSize  = $false
    $LabelStatus.Size      = New-Object System.Drawing.Size(560, 90)
    $LabelStatus.Location  = New-Object System.Drawing.Point(20, 62)
    $LabelStatus.ForeColor = [System.Drawing.Color]::LightGray
    $Form.Controls.Add($LabelStatus)

    $ProgressBar = New-Object System.Windows.Forms.ProgressBar
    $ProgressBar.Size     = New-Object System.Drawing.Size(560, 26)
    $ProgressBar.Location = New-Object System.Drawing.Point(20, 165)
    $ProgressBar.Minimum  = 0
    $ProgressBar.Maximum  = 100
    $Form.Controls.Add($ProgressBar)

    $LabelDetail = New-Object System.Windows.Forms.Label
    $LabelDetail.Text      = ''
    $LabelDetail.AutoSize  = $false
    $LabelDetail.Size      = New-Object System.Drawing.Size(560, 40)
    $LabelDetail.Location  = New-Object System.Drawing.Point(20, 200)
    $LabelDetail.ForeColor = [System.Drawing.Color]::Gray
    $LabelDetail.Font      = New-Object System.Drawing.Font('Tahoma', 8)
    $Form.Controls.Add($LabelDetail)
}

function Update-UI {
    param([string]$Message, [int]$Progress = -1, [string]$Color = 'LightGray', [string]$Detail = '')
    Write-Log "UI: $Message" 'INFO'
    if ($Silent) { return }
    $LabelStatus.Text      = $Message
    $LabelStatus.ForeColor = [System.Drawing.Color]::$Color
    if ($Progress -ge 0) { $ProgressBar.Value = [Math]::Min(100, [Math]::Max(0, $Progress)) }
    if ($Detail)         { $LabelDetail.Text  = $Detail }
    [System.Windows.Forms.Application]::DoEvents()
}

function Pump-UI {
    if (-not $Silent) { [System.Windows.Forms.Application]::DoEvents() }
}

# =============================================================================
# 3. PROCESS HELPERS
#    Start-Process -ArgumentList with an array joins elements with a bare space
#    in PS 5.1 and does NOT quote them. We therefore build the argument string
#    ourselves with explicit quoting. This is what broke --find-links on any
#    path containing a space.
# =============================================================================
function Build-ArgString {
    param([string[]]$Parts)
    $quoted = foreach ($p in $Parts) {
        if ($p -match '[\s"]') { '"' + ($p -replace '"', '\"') + '"' } else { $p }
    }
    return ($quoted -join ' ')
}

function Invoke-Tracked {
    <#
      Starts a process, keeps the WinForms UI responsive while it runs
      (no "Not Responding"), redirects both streams to files (avoids the
      classic pipe-buffer deadlock), and returns the exit code.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments   = @(),
        [string]$StdOutFile,
        [string]$StdErrFile,
        [int]$TimeoutSeconds   = 3600
    )

    $argString = Build-ArgString -Parts $Arguments
    Write-Log "EXEC: `"$FilePath`" $argString"

    $splat = @{
        FilePath    = $FilePath
        NoNewWindow = $true
        PassThru    = $true
    }
    if ($argString) { $splat.ArgumentList = $argString }
    if ($StdOutFile) { $splat.RedirectStandardOutput = $StdOutFile }
    if ($StdErrFile) { $splat.RedirectStandardError  = $StdErrFile }

    $proc = Start-Process @splat
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    while (-not $proc.HasExited) {
        Pump-UI
        Start-Sleep -Milliseconds 200
        if ($sw.Elapsed.TotalSeconds -gt $TimeoutSeconds) {
            try { $proc.Kill() } catch { }
            throw "زمان اجرای فرآیند به پایان رسید: $FilePath"
        }
    }
    $proc.WaitForExit()
    Write-Log "EXIT: $($proc.ExitCode) after $([int]$sw.Elapsed.TotalSeconds)s"
    return $proc.ExitCode
}

function Get-LogTail {
    param([string]$Path, [int]$Lines = 40)
    if (-not (Test-Path $Path)) { return '' }
    try { return (Get-Content -Path $Path -Tail $Lines -ErrorAction Stop) -join "`n" } catch { return '' }
}

function Resolve-FirstPath {
    param([string[]]$Candidates, [string]$Label)
    foreach ($c in $Candidates) {
        if (Test-Path -LiteralPath $c -PathType Leaf) {
            Write-Log "$Label resolved to: $c"
            return (Resolve-Path -LiteralPath $c).Path
        }
        Write-Log "$Label not at: $c" 'DEBUG'
    }
    return $null
}

# =============================================================================
# 4. MAIN INSTALL ROUTINE
# =============================================================================
function Start-Installation {

    # -------------------------------------------------------------------------
    # STEP 1 — Environment preflight
    # -------------------------------------------------------------------------
    Update-UI '۱. بررسی مسیر نصب و فضای دیسک...' 2

    # Non-ASCII in the install path genuinely breaks pip/venv script shebangs.
    # Spaces are fine now that every argument is properly quoted.
    if ($BaseDir -match '[^\u0000-\u007F]') {
        throw "مسیر نصب شامل حروف غیر انگلیسی است. لطفاً پوشه را به مسیری مانند C:\HamyarNejat منتقل کنید.`nمسیر فعلی: $BaseDir"
    }
    if ($BaseDir -match '\s') {
        Write-Log "Install path contains spaces (supported, but noted): $BaseDir" 'WARNING'
    }

    # Check the drive the installation actually lives on, not a hardcoded C:.
    $targetDrive = (Split-Path -Qualifier $BaseDir)
    $driveInfo   = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$targetDrive'"
    $freeGB      = [math]::Round($driveInfo.FreeSpace / 1GB, 2)
    Write-Log "Free space on ${targetDrive}: $freeGB GB"
    if ($freeGB -lt 12) {
        throw "فضای کافی در درایو $targetDrive وجود ندارد. حداقل ۱۲ گیگابایت نیاز است (موجود: $freeGB گیگابایت)."
    }
    Update-UI "۲. مسیر نصب معتبر است. فضای آزاد: $freeGB گیگابایت" 5

    # -------------------------------------------------------------------------
    # STEP 2 — Resolve requirements.txt  (THE ORIGINAL BUG)
    # -------------------------------------------------------------------------
    Update-UI '۳. جستجوی فایل requirements...' 7
    $script:RequirementsFile = Resolve-FirstPath -Candidates $RequirementsCandidates -Label 'requirements'

    if (-not $script:RequirementsFile) {
        $tried = ($RequirementsCandidates | ForEach-Object { "  - $_" }) -join "`n"
        throw ("فایل requirements.txt یافت نشد. نصب متوقف شد.`n" +
               "مسیرهای بررسی‌شده:`n$tried`n" +
               "این فایل باید در پوشه HamyarNejat_Package\libraries قرار داشته باشد.")
    }
    $reqLines = @(Get-Content -LiteralPath $script:RequirementsFile |
                  Where-Object { $_.Trim() -and -not $_.Trim().StartsWith('#') })
    Write-Log "requirements entries: $($reqLines.Count)"
    if ($reqLines.Count -eq 0) {
        throw "فایل requirements.txt خالی است: $($script:RequirementsFile)"
    }
    Update-UI "۴. فایل requirements یافت شد ($($reqLines.Count) بسته)." 10 `
              -Detail $script:RequirementsFile

    # -------------------------------------------------------------------------
    # STEP 3 — Validate the offline wheel cache BEFORE touching anything
    # -------------------------------------------------------------------------
    Update-UI '۵. بررسی مخزن آفلاین کتابخانه‌ها...' 12
    if (-not (Test-Path -LiteralPath $LibrariesDir -PathType Container)) {
        throw "پوشه کتابخانه‌های آفلاین یافت نشد: $LibrariesDir"
    }
    $wheels = @(Get-ChildItem -LiteralPath $LibrariesDir -Filter '*.whl' -File -ErrorAction SilentlyContinue)
    $sdists = @(Get-ChildItem -LiteralPath $LibrariesDir -Include '*.tar.gz', '*.zip' -File -Recurse -ErrorAction SilentlyContinue)
    Write-Log "Offline packages found: $($wheels.Count) wheels, $($sdists.Count) source archives"

    if ($wheels.Count -eq 0 -and $sdists.Count -eq 0) {
        throw ("پوشه libraries هیچ فایل نصبی (.whl) ندارد. نصب آفلاین ممکن نیست.`n" +
               "مسیر: $LibrariesDir`n" +
               "روی یک سیستم متصل به اینترنت اجرا کنید:`n" +
               "  python -m pip download -r requirements.txt -d libraries --only-binary=:all:")
    }
    Update-UI "۶. تعداد $($wheels.Count) بسته آفلاین آماده است." 15

    # -------------------------------------------------------------------------
    # STEP 4 — Locate / install Python  (per-user, NO PATH modification)
    # -------------------------------------------------------------------------
    Update-UI '۷. آماده‌سازی مفسر پایتون...' 18
    $PythonExe = $null

    $bundledPython = Join-Path $PythonDir 'python.exe'
    if (Test-Path -LiteralPath $bundledPython) {
        $PythonExe = $bundledPython
        Write-Log "Using previously installed bundled Python: $PythonExe"
    }

    if (-not $PythonExe -and -not $UseSystemPython) {
        $pyInstaller = Get-ChildItem -LiteralPath $InstallersDir -Filter 'python-*.exe' -File -ErrorAction SilentlyContinue |
                       Select-Object -First 1
        if ($pyInstaller) {
            Update-UI '۸. نصب پایتون به صورت پنهان و محلی. لطفاً صبور باشید...' 20
            # InstallAllUsers=0 + PrependPath=0 + explicit TargetDir:
            #   - needs no administrator rights
            #   - never touches the Windows PATH (project constraint)
            #   - gives us a deterministic, known-good interpreter path
            $pyArgs = @(
                '/quiet'
                'InstallAllUsers=0'
                'PrependPath=0'
                'AssociateFiles=0'
                'Shortcuts=0'
                'Include_test=0'
                'Include_launcher=0'
                'Include_doc=0'
                "TargetDir=$PythonDir"
            )
            $code = Invoke-Tracked -FilePath $pyInstaller.FullName -Arguments $pyArgs -TimeoutSeconds 900
            if ($code -ne 0 -and $code -ne 3010) {
                throw "نصب پایتون با خطا مواجه شد. کد خطا: $code"
            }
            if (-not (Test-Path -LiteralPath $bundledPython)) {
                throw "پایتون نصب شد اما فایل اجرایی در مسیر مورد انتظار یافت نشد: $bundledPython"
            }
            $PythonExe = $bundledPython
            Write-Log "Bundled Python installed at: $PythonExe"
        }
    }

    if (-not $PythonExe) {
        # Fall back to a system interpreter, resolved to an ABSOLUTE path so we
        # never depend on PATH state at launch time.
        $found = (Get-Command python.exe -ErrorAction SilentlyContinue |
                  Select-Object -First 1 -ExpandProperty Source)
        if (-not $found) {
            throw ("پایتون روی این سیستم یافت نشد و فایل نصب پایتون هم در پوشه installers وجود ندارد.`n" +
                   "فایل python-3.x.x-amd64.exe را در مسیر زیر قرار دهید:`n$InstallersDir")
        }
        $PythonExe = $found
        Write-Log "Using system Python: $PythonExe" 'WARNING'
    }

    # -------------------------------------------------------------------------
    # STEP 5 — ABI compatibility gate
    #   Wheels are built for one specific cpXY tag. The original version-check
    #   regex accepted 3.11 through 3.19, so a 3.13 host passed the check and
    #   then failed the install with an opaque pip error.
    # -------------------------------------------------------------------------
    Update-UI '۹. بررسی سازگاری نسخه پایتون با بسته‌های آفلاین...' 24
    $code = Invoke-Tracked -FilePath $PythonExe `
                           -Arguments @('-c', 'import sys;print("cp%d%d" % sys.version_info[:2]);print(sys.version)') `
                           -StdOutFile $ProbeOutLog -StdErrFile $ProbeErrLog -TimeoutSeconds 60
    if ($code -ne 0) { throw "اجرای پایتون با خطا مواجه شد. جزئیات در $ProbeErrLog" }

    $probe     = @(Get-Content -LiteralPath $ProbeOutLog | Where-Object { $_.Trim() })
    $pyTag     = $probe[0].Trim()
    $pyVersion = if ($probe.Count -gt 1) { $probe[1].Trim() } else { 'unknown' }
    Write-Log "Python ABI tag: $pyTag / version: $pyVersion"

    if ($wheels.Count -gt 0) {
        $compatible = @($wheels | Where-Object {
            $_.Name -match "-$pyTag-" -or $_.Name -match '-py3-none-any\.whl$' -or $_.Name -match '-py2\.py3-none-any\.whl$'
        })
        $binaryWheels = @($wheels | Where-Object { $_.Name -notmatch '-none-any\.whl$' })
        if ($binaryWheels.Count -gt 0 -and $compatible.Count -eq 0) {
            $sample = ($binaryWheels | Select-Object -First 3 -ExpandProperty Name) -join ', '
            throw ("بسته‌های آفلاین با این نسخه پایتون سازگار نیستند.`n" +
                   "نسخه پایتون: $pyVersion (تگ: $pyTag)`n" +
                   "نمونه بسته‌ها: $sample`n" +
                   "بسته‌ها را با همان نسخه پایتون دوباره دانلود کنید.")
        }
        Write-Log "ABI-compatible wheels: $($compatible.Count) of $($wheels.Count)"
    }
    Update-UI "۱۰. پایتون سازگار است ($pyTag)." 28 -Detail $pyVersion

    # -------------------------------------------------------------------------
    # STEP 6 — Create a clean virtual environment
    # -------------------------------------------------------------------------
    Update-UI '۱۱. ایجاد محیط مجازی پایتون (venv)...' 32
    if (Test-Path -LiteralPath $VenvDir) {
        Write-Log "Removing stale venv at $VenvDir"
        Remove-Item -LiteralPath $VenvDir -Recurse -Force
    }

    $venvOut = Join-Path $LogsDir 'venv_stdout.log'
    $venvErr = Join-Path $LogsDir 'venv_stderr.log'
    # --copies avoids reparse-point issues on some Windows configurations.
    $code = Invoke-Tracked -FilePath $PythonExe `
                           -Arguments @('-m', 'venv', '--copies', $VenvDir) `
                           -StdOutFile $venvOut -StdErrFile $venvErr -TimeoutSeconds 600
    if ($code -ne 0) {
        throw "ایجاد محیط مجازی با خطا مواجه شد (کد $code).`n$(Get-LogTail $venvErr 15)"
    }

    # Verify by artifact, not by exit code alone.
    $VenvPython = Join-Path $VenvDir 'Scripts\python.exe'
    if (-not (Test-Path -LiteralPath $VenvPython)) {
        throw "محیط مجازی ساخته شد اما python.exe یافت نشد: $VenvPython"
    }
    Write-Log "Virtual environment created successfully: $VenvPython"

    # Guarantee pip exists inside the venv.
    $code = Invoke-Tracked -FilePath $VenvPython -Arguments @('-m', 'pip', '--version') `
                           -StdOutFile $ProbeOutLog -StdErrFile $ProbeErrLog -TimeoutSeconds 120
    if ($code -ne 0) {
        Write-Log 'pip missing in venv; running ensurepip.' 'WARNING'
        $code = Invoke-Tracked -FilePath $VenvPython -Arguments @('-m', 'ensurepip', '--default-pip') `
                               -StdOutFile $ProbeOutLog -StdErrFile $ProbeErrLog -TimeoutSeconds 300
        if ($code -ne 0) { throw "pip در محیط مجازی قابل استفاده نیست.`n$(Get-LogTail $ProbeErrLog 15)" }
    }
    Write-Log "pip: $(Get-LogTail $ProbeOutLog 2)"
    Update-UI '۱۲. محیط مجازی آماده شد.' 36

    # -------------------------------------------------------------------------
    # STEP 7 — OFFLINE PIP INSTALL
    # -------------------------------------------------------------------------
    Update-UI '۱۳. نصب آفلاین کتابخانه‌ها. این مرحله چند دقیقه طول می‌کشد...' 40 `
              -Detail "منبع: $LibrariesDir"

    $pipArgs = @(
        '-m', 'pip', 'install'
        '--no-index'                     # never contact PyPI
        '--find-links', $LibrariesDir    # resolve everything from local wheels
        '--only-binary', ':all:'         # fail fast rather than try to compile
        '--no-cache-dir'
        '--disable-pip-version-check'    # suppresses an outbound version ping
        '--no-warn-script-location'
        '--no-input'
        '--isolated'                     # ignore any pip.conf / PIP_* proxy config
        '--verbose'
        '-r', $script:RequirementsFile
    )

    $code = Invoke-Tracked -FilePath $VenvPython -Arguments $pipArgs `
                           -StdOutFile $PipOutLog -StdErrFile $PipErrLog -TimeoutSeconds 3600

    if ($code -ne 0) {
        $errTail = Get-LogTail $PipErrLog 30
        $outTail = Get-LogTail $PipOutLog 30
        Write-Log "pip stderr tail:`n$errTail" 'ERROR'
        Write-Log "pip stdout tail:`n$outTail" 'ERROR'

        # Surface the single most common offline failure explicitly.
        $missing = ''
        if ("$errTail`n$outTail" -match 'No matching distribution found for ([^\s]+)') {
            $missing = "`nبسته ناموجود: $($Matches[1])"
        }
        throw ("نصب کتابخانه‌ها با خطا مواجه شد (کد $code).$missing`n" +
               "لاگ کامل: $PipErrLog")
    }
    Update-UI '۱۴. کتابخانه‌ها نصب شدند. در حال تأیید...' 55

    # -------------------------------------------------------------------------
    # STEP 8 — IMPORT SMOKE TEST
    #   This is the check whose absence let the original bug through: pip was
    #   never run, yet the installer reported success. Never trust the install
    #   step — prove the packages import.
    # -------------------------------------------------------------------------
    $smoke = 'import streamlit, lancedb, langchain_community, langchain_text_splitters; ' +
             'print("IMPORT_OK", streamlit.__version__)'
    $code = Invoke-Tracked -FilePath $VenvPython -Arguments @('-c', $smoke) `
                           -StdOutFile $ProbeOutLog -StdErrFile $ProbeErrLog -TimeoutSeconds 300
    $smokeOut = Get-LogTail $ProbeOutLog 5
    if ($code -ne 0 -or $smokeOut -notmatch 'IMPORT_OK') {
        throw ("کتابخانه‌ها نصب شدند اما قابل بارگذاری نیستند.`n" +
               "$(Get-LogTail $ProbeErrLog 20)")
    }
    Write-Log "Smoke test passed: $smokeOut"

    # Prove the Streamlit CLI itself is runnable — the exact call run.ps1 makes.
    $code = Invoke-Tracked -FilePath $VenvPython -Arguments @('-m', 'streamlit', '--version') `
                           -StdOutFile $ProbeOutLog -StdErrFile $ProbeErrLog -TimeoutSeconds 300
    if ($code -ne 0) {
        throw "اجرای Streamlit ممکن نیست.`n$(Get-LogTail $ProbeErrLog 20)"
    }
    Write-Log "Streamlit CLI: $(Get-LogTail $ProbeOutLog 2)"
    Update-UI '۱۵. صحت نصب کتابخانه‌ها تأیید شد.' 62

    # -------------------------------------------------------------------------
    # STEP 9 — Locate the application entry point
    # -------------------------------------------------------------------------
    Update-UI '۱۶. بررسی فایل اصلی برنامه...' 65
    $AppFile = Resolve-FirstPath -Candidates $AppCandidates -Label 'app.py'
    if (-not $AppFile) {
        $tried = ($AppCandidates | ForEach-Object { "  - $_" }) -join "`n"
        throw "فایل app.py یافت نشد.`nمسیرهای بررسی‌شده:`n$tried"
    }
    $AppDir = Split-Path -Parent $AppFile

    # -------------------------------------------------------------------------
    # STEP 10 — Portable Ollama (in place; no PATH change, no copy to profile)
    # -------------------------------------------------------------------------
    Update-UI '۱۷. آماده‌سازی موتور محلی Ollama...' 70
    $OllamaExe = Join-Path $InstallersDir 'ollama_portable\ollama.exe'
    if (-not (Test-Path -LiteralPath $OllamaExe)) {
        throw ("فایل ollama.exe یافت نشد. نصب متوقف شد.`n" +
               "مسیر مورد انتظار: $OllamaExe")
    }
    Write-Log "Portable Ollama: $OllamaExe"

    # Models are used IN PLACE via OLLAMA_MODELS. This avoids copying several
    # gigabytes into a user profile, and avoids the elevation bug where an
    # elevated installer writes to the administrator's profile instead of the
    # end user's.
    $ModelsDir = Join-Path $InstallersDir 'models'
    if (Test-Path -LiteralPath $ModelsDir) {
        $hasBlobs     = Test-Path (Join-Path $ModelsDir 'blobs')
        $hasManifests = Test-Path (Join-Path $ModelsDir 'manifests')
        if (-not ($hasBlobs -and $hasManifests)) {
            throw ("ساختار پوشه مدل‌ها نامعتبر است. باید شامل blobs و manifests باشد.`n" +
                   "مسیر: $ModelsDir (blobs=$hasBlobs, manifests=$hasManifests)")
        }
        $modelSizeGB = [math]::Round(((Get-ChildItem -LiteralPath $ModelsDir -Recurse -File |
                        Measure-Object -Property Length -Sum).Sum / 1GB), 2)
        Write-Log "Models validated in place: $ModelsDir ($modelSizeGB GB)"
        Update-UI "۱۸. مدل‌های زبانی تأیید شدند ($modelSizeGB گیگابایت)." 78
    } else {
        throw ("پوشه مدل‌های زبانی یافت نشد. نصب متوقف شد.`n" +
               "مسیر مورد انتظار: $ModelsDir")
    }

    # -------------------------------------------------------------------------
    # STEP 11 — Streamlit config: suppress first-run prompt and outbound calls
    # -------------------------------------------------------------------------
    Update-UI '۱۹. تنظیم پیکربندی آفلاین رابط کاربری...' 82
    $stConfigDir = Join-Path $AppDir '.streamlit'
    if (-not (Test-Path $stConfigDir)) { New-Item -ItemType Directory -Path $stConfigDir -Force | Out-Null }
    @'
[global]
developmentMode = false

[server]
headless = true
fileWatcherType = "none"
address = "127.0.0.1"
enableCORS = false
enableXsrfProtection = true

[browser]
gatherUsageStats = false

[runner]
fastReruns = true
'@ | Set-Content -Path (Join-Path $stConfigDir 'config.toml') -Encoding UTF8
    Write-Log "Wrote Streamlit config to $stConfigDir"

    # -------------------------------------------------------------------------
    # STEP 12 — Environment manifest
    #   The launcher must READ these absolute paths instead of re-deriving them.
    #   Independent path derivation in install.ps1 and run.ps1 is what caused
    #   both the empty-venv bug and the earlier "venv not found" fallback.
    # -------------------------------------------------------------------------
    Update-UI '۲۰. ثبت تنظیمات محیط اجرا...' 88
    $manifest = [ordered]@{
        schema_version    = 2
        generated_at      = (Get-Date -Format 'o')
        base_dir          = $BaseDir
        python_exe        = $PythonExe
        python_version    = $pyVersion
        python_abi_tag    = $pyTag
        venv_dir          = $VenvDir
        venv_python       = $VenvPython
        app_file          = $AppFile
        app_dir           = $AppDir
        requirements_file = $script:RequirementsFile
        libraries_dir     = $LibrariesDir
        ollama_exe        = $OllamaExe
        ollama_models_dir = $ModelsDir
        ollama_host       = '127.0.0.1:11434'
        packages_verified = $true
    }
    $manifest | ConvertTo-Json -Depth 4 | Set-Content -Path $ManifestFile -Encoding UTF8
    Write-Log "Manifest written: $ManifestFile"

    # -------------------------------------------------------------------------
    # STEP 13 — Desktop shortcut (current user; installer is NOT elevated)
    # -------------------------------------------------------------------------
    Update-UI '۲۱. ایجاد شورتکات دسکتاپ...' 93
    $launcher = Join-Path $BaseDir 'Start_Hamyar.bat'
    if (-not (Test-Path -LiteralPath $launcher)) {
        Write-Log "Launcher not found at $launcher; skipping shortcut." 'WARNING'
    } else {
        $desktop  = [Environment]::GetFolderPath('Desktop')
        $lnkPath  = Join-Path $desktop 'Hamyar Nejat.lnk'
        $icon     = Join-Path $BaseDir 'logo.ico'
        $wsh      = New-Object -ComObject WScript.Shell

        $lnk      = $wsh.CreateShortcut($lnkPath)
        $lnk.TargetPath       = $launcher
        $lnk.WorkingDirectory = $BaseDir
        $lnk.Description      = 'همیار نجات - دستیار هوشمند آفلاین'
        if (Test-Path -LiteralPath $icon) { $lnk.IconLocation = $icon }
        $lnk.Save()

        # Stop shortcut
        $stopLnkPath = Join-Path $desktop 'Hamyar Nejat - Stop.lnk'
        $stopLnk = $wsh.CreateShortcut($stopLnkPath)
        $stopLnk.TargetPath       = (Join-Path $BaseDir 'Stop_Hamyar.bat')
        $stopLnk.WorkingDirectory = $BaseDir
        $stopLnk.Save()

        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($wsh) | Out-Null
        Write-Log "Shortcut created: $lnkPath and $stopLnkPath"
    }

    Update-UI '۲۲. نصب با موفقیت به پایان رسید.' 100 'LimeGreen' `
              -Detail 'برنامه از طریق شورتکات دسکتاپ اجرا می‌شود.'
    Write-Log 'INSTALLATION COMPLETED SUCCESSFULLY.'
}

# =============================================================================
# 5. ENTRY POINT
# =============================================================================
$script:ExitCode = 0

function Invoke-Main {
    try {
        Start-Installation
        $script:ExitCode = 0
        if (-not $Silent) {
            # Auto-close after a short pause. No MessageBox, no click required.
            $timer = New-Object System.Windows.Forms.Timer
            $timer.Interval = 2500
            $timer.Add_Tick({ $timer.Stop(); $Form.Close() })
            $timer.Start()
        }
    }
    catch {
        $script:ExitCode = 1
        $msg = $_.Exception.Message
        Write-Log "INSTALLATION FAILED: $msg" 'ERROR'
        Write-Log "ScriptStackTrace: $($_.ScriptStackTrace)" 'ERROR'
        Update-UI "خطا در نصب:`n$msg" -Color 'Red' -Detail "جزئیات کامل: $LogFile"
        # The window intentionally stays open on failure so the user can read
        # the reason. Nothing to click, nothing to dismiss.
    }
}

if ($Silent) {
    Invoke-Main
    Write-Log "Exiting with code $script:ExitCode"
    exit $script:ExitCode
} else {
    $Form.Add_Shown({ Invoke-Main })
    [void]$Form.ShowDialog()
    $Form.Dispose()
    Write-Log "Exiting with code $script:ExitCode"
    exit $script:ExitCode
}
