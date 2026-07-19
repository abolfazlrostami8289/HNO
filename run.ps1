<#
.SYNOPSIS
    اجرا کننده سریع و مخفی همیار نجات (Launcher)
#>

Add-Type -AssemblyName System.Windows.Forms

$BaseDir = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
$AppFile = Join-Path -Path $BaseDir -ChildPath "app.py"
# -----------------------------------------------------------------------------
# ۱: بررسی سریع پیش‌نیازها
# -----------------------------------------------------------------------------
function Show-ErrorAndExit($Message) {
    [System.Windows.Forms.MessageBox]::Show($Message, "خطا در اجرای برنامه", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    Exit
}

# بررسی فایل اصلی برنامه
if (-not (Test-Path $AppFile)) {
    # بررسی مسیر جایگزین (در صورتی که فایل در پوشه روت باشد)
    $AppFileRoot = Join-Path -Path $BaseDir -ChildPath "app.py"
    if (Test-Path $AppFileRoot) {
        $AppFile = $AppFileRoot
    } else {
        Show-ErrorAndExit "فایل اصلی برنامه (app.py) یافت نشد! مطمئن شوید اسکریپت در پوشه صحیح قرار دارد."
    }
}

# بررسی پوشه knowledge
$KnowledgeDir = Join-Path -Path $BaseDir -ChildPath "knowledge"
if (-not (Test-Path $KnowledgeDir)) {
    New-Item -ItemType Directory -Path $KnowledgeDir -Force | Out-Null
}

# بررسی پایتون
$PythonInstalled = $false
try {
    $PythonVersion = & python --version 2>&1
    if ($PythonVersion -match "Python") {
        $PythonInstalled = $true
    }
} catch {}

if (-not $PythonInstalled) {
    Show-ErrorAndExit "پایتون روی این سیستم نصب نیست یا در متغیرهای محیطی سیستم تعریف نشده است."
}

# بررسی اولاما
$OllamaInstalled = $false
try {
    $OllamaVersion = & ollama --version 2>&1
    if ($OllamaVersion -match "ollama") {
        $OllamaInstalled = $true
    }
} catch {}

if (-not $OllamaInstalled) {
    Show-ErrorAndExit "نرم‌افزار Ollama یافت نشد. لطفاً ابتدا مراحل نصب را کامل کنید."
}

# -----------------------------------------------------------------------------
# ۲: فعال‌سازی هوشمند Ollama در پس‌زمینه
# -----------------------------------------------------------------------------
$OllamaProcess = Get-Process -Name "ollama" -ErrorAction SilentlyContinue
$OllamaAppProcess = Get-Process -Name "ollama app" -ErrorAction SilentlyContinue

if (-not $OllamaProcess -and -not $OllamaAppProcess) {
    Start-Process -FilePath "ollama" -ArgumentList "serve" -WindowStyle Hidden
    Start-Sleep -Seconds 2
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

# -----------------------------------------------------------------------------
# ۴: اجرای Streamlit و باز کردن مرورگر
# -----------------------------------------------------------------------------
# اجرای استریم‌لیت در پس‌زمینه و حالت مخفی
Start-Process -FilePath "python" -ArgumentList "-m streamlit run `"$AppFile`" --server.port $SelectedPort --server.headless true" -WindowStyle Hidden

# انتظار برای راه‌اندازی سرور محلی
Start-Sleep -Seconds 4

# باز کردن مرورگر پیش‌فرض سیستم
Start-Process "http://localhost:$SelectedPort"
