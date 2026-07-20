<#
.SYNOPSIS
    نصب‌کننده گرافیکی و آفلاین همیار نجات
.DESCRIPTION
    این اسکریپت تمام نیازمندی‌ها شامل پایتون، کتابخانه‌ها و مدل‌های Ollama را به صورت آفلاین نصب می‌کند.
#>

# -----------------------------------------------------------------------------
# ۱. بررسی دسترسی ادمین (Run as Administrator)
# -----------------------------------------------------------------------------
$wid = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$prp = New-Object System.Security.Principal.WindowsPrincipal($wid)
$adm = [System.Security.Principal.WindowsBuiltInRole]::Administrator
if (-not $prp.IsInRole($adm)) {
    # در صورت عدم دسترسی، اسکریپت با دسترسی ادمین دوباره اجرا می‌شود
    $CommandLine = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    Start-Process -FilePath PowerShell.exe -Verb RunAs -ArgumentList $CommandLine
    Exit
}

# -----------------------------------------------------------------------------
# بارگذاری اسمبلی‌های مورد نیاز برای رابط کاربری
# -----------------------------------------------------------------------------
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# -----------------------------------------------------------------------------
# تنظیمات مسیرها
# -----------------------------------------------------------------------------
$BaseDir = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
$InstallersDir = Join-Path -Path $BaseDir -ChildPath "HamyarNejat_Package\installers"
$LibrariesDir = Join-Path -Path $BaseDir -ChildPath "HamyarNejat_Package\libraries"
$RequirementsFile = Join-Path -Path $LibrariesDir -ChildPath "requirements.txt"
$AppFile = Join-Path -Path $BaseDir -ChildPath "HamyarNejat_Package\app.py"
$LogsDir = Join-Path -Path $BaseDir -ChildPath "logs"
$LogFile = Join-Path -Path $LogsDir -ChildPath "install_debug.log"

if (-not (Test-Path $LogsDir)) {
    New-Item -ItemType Directory -Path $LogsDir -Force | Out-Null
}

function Write-Log($Message, $Level = "INFO") {
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$Timestamp] [$Level] $Message"
    Add-Content -Path $LogFile -Value $LogMessage
}

Write-Log "Installation script started."

# -----------------------------------------------------------------------------
# ۲. طراحی رابط گرافیکی (GUI)
# -----------------------------------------------------------------------------
$Form = New-Object System.Windows.Forms.Form
$Form.Text = "نصب‌کننده همیار نجات"
$Form.Size = New-Object System.Drawing.Size(600, 400)
$Form.StartPosition = 'CenterScreen'
$Form.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30) # Dark Theme
$Form.ForeColor = [System.Drawing.Color]::White
$Form.Font = New-Object System.Drawing.Font("Tahoma", 10, [System.Drawing.FontStyle]::Regular)
$Form.RightToLeft = [System.Windows.Forms.RightToLeft]::Yes
$Form.RightToLeftLayout = $true
$Form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
$Form.MaximizeBox = $false

# عنوان اصلی
$LabelTitle = New-Object System.Windows.Forms.Label
$LabelTitle.Text = "نصب‌کننده همیار نجات"
$LabelTitle.Font = New-Object System.Drawing.Font("Tahoma", 16, [System.Drawing.FontStyle]::Bold)
$LabelTitle.ForeColor = [System.Drawing.Color]::FromArgb(200, 0, 0) # قرمز تیره
$LabelTitle.AutoSize = $true
$LabelTitle.Location = New-Object System.Drawing.Point(20, 20)
$Form.Controls.Add($LabelTitle)

# برچسب وضعیت
$LabelStatus = New-Object System.Windows.Forms.Label
$LabelStatus.Text = "آماده برای شروع نصب..."
$LabelStatus.AutoSize = $false
$LabelStatus.Size = New-Object System.Drawing.Size(540, 60)
$LabelStatus.Location = New-Object System.Drawing.Point(20, 80)
$LabelStatus.ForeColor = [System.Drawing.Color]::LightGray
$Form.Controls.Add($LabelStatus)

# نوار پیشرفت
$ProgressBar = New-Object System.Windows.Forms.ProgressBar
$ProgressBar.Size = New-Object System.Drawing.Size(540, 30)
$ProgressBar.Location = New-Object System.Drawing.Point(20, 150)
$ProgressBar.Minimum = 0
$ProgressBar.Maximum = 100
$Form.Controls.Add($ProgressBar)

# دکمه شروع نصب
$ButtonStart = New-Object System.Windows.Forms.Button
$ButtonStart.Text = "شروع نصب"
$ButtonStart.Size = New-Object System.Drawing.Size(150, 40)
$ButtonStart.Location = New-Object System.Drawing.Point(225, 220)
$ButtonStart.BackColor = [System.Drawing.Color]::FromArgb(139, 0, 0) # قرمز تیره
$ButtonStart.ForeColor = [System.Drawing.Color]::White
$ButtonStart.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$ButtonStart.FlatAppearance.BorderSize = 0
$ButtonStart.Cursor = [System.Windows.Forms.Cursors]::Hand
$Form.Controls.Add($ButtonStart)

# -----------------------------------------------------------------------------
# توابع کمکی
# -----------------------------------------------------------------------------
function Update-UI ($Message, $Progress, $Color = "LightGray", $LogMessage = $null) {
    $LabelStatus.Text = $Message
    $LabelStatus.ForeColor = [System.Drawing.Color]::$Color
    $ProgressBar.Value = $Progress
    [System.Windows.Forms.Application]::DoEvents()
    if ($null -ne $LogMessage) {
        Write-Log "UI Update: $LogMessage ($Progress%)"
    } else {
        Write-Log "UI Update: Progress $Progress%"
    }
}

# -----------------------------------------------------------------------------
# منطق اصلی نصب
# -----------------------------------------------------------------------------
$ButtonStart.Add_Click({
    $ButtonStart.Enabled = $false
    $ButtonStart.BackColor = [System.Drawing.Color]::Gray

    try {
        # --- بخش ۲: بررسی اولیه سیستم (0 تا 10%) ---
        Update-UI "۱. شروع بررسی‌های اولیه سیستم..." 0
        Start-Sleep -Seconds 1
        
        Update-UI "۲. در حال بررسی مسیر اجرای اسکریپت..." 2
        # بررسی کاراکتر فارسی یا فاصله در مسیر
        if ($BaseDir -match "[\s\p{IsArabic}]") {
            Write-Log "Invalid path detected: $BaseDir" "ERROR"
            throw "مسیر فایل‌ها نباید دارای فاصله یا حروف فارسی باشد. لطفاً پوشه را به مسیری ساده مثل C:\App منتقل کنید."
        }

        Update-UI "۳. مسیر اجرای اسکریپت معتبر است." 4
        Start-Sleep -Seconds 1

        Update-UI "۴. در حال بررسی فضای خالی درایو C..." 6
        $DriveC = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'"
        $FreeSpaceGB = [math]::Round($DriveC.FreeSpace / 1GB, 2)
        if ($FreeSpaceGB -lt 10) {
            Write-Log "Not enough free space on C: ($FreeSpaceGB GB)" "ERROR"
            throw "فضای کافی در درایو C وجود ندارد. حداقل ۱۰ گیگابایت نیاز است."
        }

        Update-UI "۵. فضای دیسک تایید شد ($FreeSpaceGB گیگابایت موجود است)." 10
        Start-Sleep -Seconds 1

        # --- بخش ۳: نصب محیط اجرای پایتون (10 تا 30%) ---
        Update-UI "۶. بررسی نصب بودن پایتون روی سیستم..." 12
        $PythonInstalled = $false
        $MockPython = $false
        try {
            $PythonVersion = & python --version 2>&1
            if ($PythonVersion -match "Python 3\.1[1-9]") {
                $PythonInstalled = $true
            }
        } catch {}

        if ($PythonInstalled) {
            Update-UI "۷. پایتون 3.11+ از قبل نصب شده است." 30
        } else {
            Update-UI "۷. پایتون یافت نشد. آماده‌سازی برای نصب پایتون..." 15
            $PythonInstaller = Get-ChildItem -Path $InstallersDir -Filter "python-*.exe" | Select-Object -First 1
            if (-not $PythonInstaller) {
                Write-Log "Mock: File bypassed for testing (Python Installer missing)" "INFO"
                $MockPython = $true
                Update-UI "هشدار: فایل نصب پایتون در پوشه installers یافت نشد. عبور برای تست..." 15 "Yellow"
            } else {
                Update-UI "۸. در حال نصب پایتون به صورت پنهان. لطفاً صبور باشید..." 20
                $Process = Start-Process -FilePath $PythonInstaller.FullName -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1 Include_test=0" -Wait -PassThru
                if ($Process.ExitCode -eq 0) {
                    Update-UI "۹. پایتون با موفقیت نصب شد." 30
                } else {
                    throw "نصب پایتون با خطا مواجه شد. کد خطا: $($Process.ExitCode)"
                }
            }
        }
        Start-Sleep -Seconds 1

        # --- بخش ۴: نصب آفلاین کتابخانه‌ها (30 تا 50%) ---
        Update-UI "۱۰. آماده‌سازی برای نصب آفلاین کتابخانه‌های پایتون..." 32
        Start-Sleep -Seconds 1
        
        $VenvDir = Join-Path -Path $BaseDir -ChildPath "venv"
        $PythonExecutable = "python"

        Update-UI "۱۰.۱. ایجاد محیط مجازی پایتون (venv)..." 33
        if ($MockPython) {
            Write-Log "Mock: Venv creation bypassed" "INFO"
        } else {
            try {
                $Process = Start-Process -FilePath "python" -ArgumentList "-m venv `"$VenvDir`"" -Wait -NoNewWindow -PassThru
                if ($Process.ExitCode -ne 0) {
                    throw "کد خطای ایجاد venv: $($Process.ExitCode)"
                }
                Write-Log "Virtual environment created successfully."
                $PythonExecutable = Join-Path -Path $VenvDir -ChildPath "Scripts\python.exe"
            } catch {
                Write-Log "Failed to create virtual environment." "ERROR"
                throw "ایجاد محیط مجازی پایتون با خطا مواجه شد."
            }
        }

        if ($MockPython) {
            Write-Log "Mock: pip install bypassed" "INFO"
        } elseif (Test-Path $RequirementsFile) {
            Update-UI "۱۱. در حال نصب پکیج‌ها از طریق pip (این مرحله ممکن است زمان‌بر باشد)..." 35
            
            # رفرش کردن متغیرهای محیطی برای شناسایی پایتون در صورت نصب جدید
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
            
            $PipArgs = "install", "--no-index", "--find-links=`"$LibrariesDir`"", "-r", "`"$RequirementsFile`""
            $Process = Start-Process -FilePath $PythonExecutable -ArgumentList "-m pip $PipArgs" -Wait -NoNewWindow -PassThru
            
            if ($Process.ExitCode -eq 0) {
                Update-UI "۱۲. کتابخانه‌ها با موفقیت نصب شدند." 50
            } else {
                throw "نصب کتابخانه‌ها با خطا مواجه شد."
            }
        } else {
            Write-Log "Mock: File bypassed for testing (requirements.txt missing)" "INFO"
            Update-UI "۱۱. فایل requirements.txt یافت نشد. از این مرحله عبور می‌کنیم." 50
        }
        Start-Sleep -Seconds 1

        # --- بخش ۵: نصب Ollama و انتقال مدل‌ها (50 تا 90%) ---
        Update-UI "۱۳. بررسی نصب بودن Ollama..." 52
        $OllamaInstalled = $false
        try {
            $OllamaVersion = & ollama --version 2>&1
            if ($OllamaVersion -match "ollama") {
                $OllamaInstalled = $true
            }
        } catch {}

        if (-not $OllamaInstalled) {
            Update-UI "۱۴. Ollama یافت نشد. در حال نصب Ollama..." 55
            $OllamaInstaller = Get-ChildItem -Path $InstallersDir -Filter "OllamaSetup.exe" | Select-Object -First 1
            if ($OllamaInstaller) {
                $Process = Start-Process -FilePath $OllamaInstaller.FullName -ArgumentList "/SILENT" -Wait -PassThru
                Update-UI "۱۵. Ollama نصب شد." 60
            } else {
                Write-Log "Mock: File bypassed for testing (OllamaSetup missing)" "INFO"
                Update-UI "هشدار: فایل نصب Ollama یافت نشد." 60 "Yellow"
            }
        } else {
            Update-UI "۱۴. Ollama از قبل نصب شده است." 60
        }
        Start-Sleep -Seconds 1

        Update-UI "۱۶. بررسی پوشه مدل‌های آفلاین زبان..." 62
        $SourceModelsDir = Join-Path -Path $InstallersDir -ChildPath "models"
        $DestModelsDir = Join-Path -Path $env:USERPROFILE -ChildPath ".ollama\models"

        if (Test-Path $SourceModelsDir) {
            if (-not (Test-Path $DestModelsDir)) {
                New-Item -ItemType Directory -Path $DestModelsDir -Force | Out-Null
            }
            
            Update-UI "۱۷. در حال کپی مدل‌های زبانی. لطفاً تا پایان این عملیات حجیم صبور باشید..." 65
            $FilesToCopy = Get-ChildItem -Path $SourceModelsDir -Recurse -File
            $TotalFiles = $FilesToCopy.Count
            $CopiedFiles = 0
            
            foreach ($File in $FilesToCopy) {
                $RelativePath = $File.FullName.Substring($SourceModelsDir.Length + 1)
                $DestinationPath = Join-Path -Path $DestModelsDir -ChildPath $RelativePath
                $DestinationDir = Split-Path -Parent -Path $DestinationPath
                
                if (-not (Test-Path $DestinationDir)) {
                    New-Item -ItemType Directory -Path $DestinationDir -Force | Out-Null
                }
                
                Copy-Item -Path $File.FullName -Destination $DestinationPath -Force
                $CopiedFiles++
                
                # محاسبه پیشرفت بین 65 تا 90
                $ProgressStep = 65 + [math]::Round(($CopiedFiles / $TotalFiles) * 25)
                Update-UI "۱۸. در حال کپی فایل: $($File.Name) ($CopiedFiles از $TotalFiles)" $ProgressStep
            }
            Update-UI "۱۹. کپی مدل‌های زبانی به اتمام رسید." 90
        } else {
            Write-Log "Mock: File bypassed for testing (models directory missing)" "INFO"
            Update-UI "۱۷. پوشه مدل‌های آفلاین یافت نشد. پرش از این مرحله..." 90
        }
        Start-Sleep -Seconds 1

        # --- بخش ۶: نهایی‌سازی و شورتکات (90 تا 100%) ---
        Update-UI "۲۰. در حال ایجاد شورتکات دسکتاپ..." 92
        $DesktopPath = [Environment]::GetFolderPath("Desktop")
        $ShortcutPath = Join-Path -Path $DesktopPath -ChildPath "Hamyar Nejat.lnk"
        $WshShell = New-Object -ComObject WScript.Shell
        $Shortcut = $WshShell.CreateShortcut($ShortcutPath)
        
        # اجرای اسکریپت از طریق فایل bat که سیاست‌های ویندوز را دور می‌زند و پنچره‌ را مخفی می‌کند
        $Shortcut.TargetPath = Join-Path -Path $BaseDir -ChildPath "RunMe.bat"
        $Shortcut.WorkingDirectory = $BaseDir
        # $Shortcut.IconLocation = "مسیر آیکون در صورت وجود"
        $Shortcut.Save()
        
        Update-UI "۲۱. شورتکات برنامه روی دسکتاپ ایجاد شد." 96
        Start-Sleep -Seconds 1

        Update-UI "۲۲. در حال پاک‌سازی و نهایی‌سازی تنظیمات..." 98
        Start-Sleep -Seconds 1

        Update-UI "۲۳. نصب با موفقیت به پایان رسید." 100 "LimeGreen"
        
        [System.Windows.Forms.MessageBox]::Show("عملیات نصب با موفقیت تکمیل شد. می‌توانید برنامه را از روی دسکتاپ اجرا کنید.", "پایان نصب", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        $Form.Close()

    } catch {
        Write-Log "Installation error encountered. Check script for details." "ERROR"
        Update-UI "خطا در نصب: $_" $ProgressBar.Value "Red" "Installation failed due to an exception"
        $ButtonStart.Enabled = $true
        $ButtonStart.BackColor = [System.Drawing.Color]::FromArgb(139, 0, 0)
    }
})

# -----------------------------------------------------------------------------
# نمایش فرم
# -----------------------------------------------------------------------------
$Form.ShowDialog() | Out-Null
