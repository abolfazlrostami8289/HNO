<#
.SYNOPSIS
    اجرا کننده سریع و مخفی همیار نجات (Launcher)
#>

Add-Type -AssemblyName System.Windows.Forms

$BaseDir = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
$AppFile = Join-Path -Path $BaseDir -ChildPath "HamyarNejat_Package\app\app.py"
$LogsDir = Join-Path -Path $BaseDir -ChildPath "logs"
$LogFile = Join-Path -Path $LogsDir -ChildPath "run_debug.log"

if (-not (Test-Path $LogsDir)) {
    New-Item -ItemType Directory -Path $LogsDir -Force | Out-Null
}

function Write-Log($Message, $Level = "INFO") {
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$Timestamp] [$Level] $Message"
    Add-Content -Path $LogFile -Value $LogMessage
}

Write-Log "Launcher script started."

# -----------------------------------------------------------------------------
# ۱: بررسی سریع پیش‌نیازها
# -----------------------------------------------------------------------------
function Show-ErrorAndExit($Message) {
    Write-Log "Error: $Message" "ERROR"
    [System.Windows.Forms.MessageBox]::Show($Message, "خطا در اجرای برنامه", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    Exit
}

# بررسی فایل اصلی برنامه
if (-not (Test-Path $AppFile)) {
    # بررسی مسیر جایگزین (در صورتی که فایل در پوشه روت پکیج باشد)
    $AppFileFallback = Join-Path -Path $BaseDir -ChildPath "HamyarNejat_Package\app.py"
    if (Test-Path $AppFileFallback) {
        $AppFile = $AppFileFallback
    } else {
        Show-ErrorAndExit "فایل اصلی برنامه یافت نشد! مطمئن شوید فایل app.py در پوشه HamyarNejat_Package قرار دارد."
    }
}
Write-Log "AppFile verified at: $AppFile"

# بررسی پوشه knowledge
$KnowledgeDir = Join-Path -Path $BaseDir -ChildPath "HamyarNejat_Package\knowledge"
if (-not (Test-Path $KnowledgeDir)) {
    New-Item -ItemType Directory -Path $KnowledgeDir -Force | Out-Null
}
Write-Log "Knowledge directory checked/created."

# بررسی پایتون
$PythonInstalled = $false
try {
    $PythonVersion = & python --version 2>&1
    if ($PythonVersion -match "Python") {
        $PythonInstalled = $true
    }
} catch {
    Write-Log "Failed to check python version: $_" "WARNING"
}

if (-not $PythonInstalled) {
    Show-ErrorAndExit "پایتون روی این سیستم نصب نیست یا در متغیرهای محیطی سیستم تعریف نشده است."
}
Write-Log "Python is installed."

# بررسی اولاما
$OllamaInstalled = $false
try {
    $OllamaVersion = & ollama --version 2>&1
    if ($OllamaVersion -match "ollama") {
        $OllamaInstalled = $true
    }
} catch {
    Write-Log "Failed to check ollama version: $_" "WARNING"
}

if (-not $OllamaInstalled) {
    Show-ErrorAndExit "نرم‌افزار Ollama یافت نشد. لطفاً ابتدا مراحل نصب را کامل کنید."
}
Write-Log "Ollama is installed."

# -----------------------------------------------------------------------------
# ۲: فعال‌سازی هوشمند Ollama در پس‌زمینه
# -----------------------------------------------------------------------------
$OllamaProcess = Get-Process -Name "ollama" -ErrorAction SilentlyContinue
$OllamaAppProcess = Get-Process -Name "ollama app" -ErrorAction SilentlyContinue

if (-not $OllamaProcess -and -not $OllamaAppProcess) {
    Write-Log "Starting Ollama process in the background..."
    Start-Process -FilePath "ollama" -ArgumentList "serve" -WindowStyle Hidden
    Start-Sleep -Seconds 2
} else {
    Write-Log "Ollama process is already running."
}

# -----------------------------------------------------------------------------
# ۳: مدیریت پورت‌ها
# -----------------------------------------------------------------------------
function Get-AvailablePort {
    $Ports = @(8501, 8502, 8503, 8504)
    $ipGlobalProperties = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties()
    $tcpListeners = $ipGlobalProperties.GetActiveTcpListeners()
    
    foreach ($Port in $Ports) {
        $isOccupied = $false
        foreach ($listener in $tcpListeners) {
            if ($listener.Port -eq $Port) {
                $isOccupied = $true
                break
            }
        }
        if (-not $isOccupied) {
            return $Port
        }
    }
    return $null
}

$SelectedPort = Get-AvailablePort
if ($null -eq $SelectedPort) {
    Show-ErrorAndExit "تمام پورت‌های پیش‌فرض برنامه (8501 تا 8504) اشغال هستند. لطفاً برنامه‌های مشابه را ببندید."
}
Write-Log "Selected available port: $SelectedPort"

# -----------------------------------------------------------------------------
# ۴: اجرای Streamlit و باز کردن مرورگر
# -----------------------------------------------------------------------------
# اجرای استریم‌لیت در پس‌زمینه و حالت مخفی
Write-Log "Starting Streamlit application..."
$VenvPython = Join-Path -Path $BaseDir -ChildPath "venv\Scripts\python.exe"

if (-not (Test-Path $VenvPython)) {
    Write-Log "Virtual environment python not found at $VenvPython. Falling back to global python." "WARNING"
    $VenvPython = "python"
}

try {
    Start-Process -FilePath $VenvPython -ArgumentList "-m streamlit run `"$AppFile`" --server.port $SelectedPort --server.headless true" -WindowStyle Hidden
} catch {
    Show-ErrorAndExit "خطا در اجرای Streamlit: $_"
}

# انتظار برای راه‌اندازی سرور محلی
Start-Sleep -Seconds 4

# باز کردن مرورگر پیش‌فرض سیستم
Write-Log "Opening browser at http://localhost:$SelectedPort"
try {
    Start-Process "http://localhost:$SelectedPort"
} catch {
    Write-Log "Failed to open browser: $_" "WARNING"
}