<#
.SYNOPSIS
    نصب‌کننده گرافیکی و آفلاین همیار نجات
.DESCRIPTION
    این اسکریپت ظاهر گرافیکی نصب کننده را نمایش می‌دهد.
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
$LabelTitle.ForeColor = [System.Drawing.Color]::FromArgb(220, 53, 69) # قرمز
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
$ButtonStart.Location = New-Object System.Drawing.Point(300, 220)
$ButtonStart.BackColor = [System.Drawing.Color]::FromArgb(220, 53, 69) # قرمز
$ButtonStart.ForeColor = [System.Drawing.Color]::White
$ButtonStart.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$ButtonStart.FlatAppearance.BorderSize = 0
$ButtonStart.Cursor = [System.Windows.Forms.Cursors]::Hand
$Form.Controls.Add($ButtonStart)

# دکمه خروج
$ButtonExit = New-Object System.Windows.Forms.Button
$ButtonExit.Text = "خروج"
$ButtonExit.Size = New-Object System.Drawing.Size(150, 40)
$ButtonExit.Location = New-Object System.Drawing.Point(120, 220)
$ButtonExit.BackColor = [System.Drawing.Color]::FromArgb(70, 70, 70) # خاکستری
$ButtonExit.ForeColor = [System.Drawing.Color]::White
$ButtonExit.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$ButtonExit.FlatAppearance.BorderSize = 0
$ButtonExit.Cursor = [System.Windows.Forms.Cursors]::Hand
$ButtonExit.Add_Click({ $Form.Close() })
$Form.Controls.Add($ButtonExit)


# -----------------------------------------------------------------------------
# توابع کمکی
# -----------------------------------------------------------------------------
function Update-UI ($Message, $Progress, $Color = "LightGray") {
    $LabelStatus.Text = $Message
    $LabelStatus.ForeColor = [System.Drawing.Color]::$Color
    $ProgressBar.Value = $Progress
    [System.Windows.Forms.Application]::DoEvents()
}

# -----------------------------------------------------------------------------
# توابع خالی (Mock Functions) برای مراحل بعدی
# -----------------------------------------------------------------------------
function Mock-SystemCheck {
    Update-UI "مرحله ۳: در حال بررسی سیستم (تابع خالی)..." 10
    Start-Sleep -Seconds 1
}

function Mock-PythonInstall {
    Update-UI "مرحله ۴: در حال نصب پایتون (تابع خالی)..." 30
    Start-Sleep -Seconds 1
}

function Mock-LibrariesInstall {
    Update-UI "مرحله ۵: در حال نصب کتابخانه‌ها (تابع خالی)..." 50
    Start-Sleep -Seconds 1
}

function Mock-OllamaInstall {
    Update-UI "مرحله ۶: در حال نصب Ollama و کپی مدل‌ها (تابع خالی)..." 80
    Start-Sleep -Seconds 1
}

function Mock-ShortcutsAndFinalize {
    Update-UI "مرحله ۷: در حال ایجاد میانبرها و نهایی‌سازی (تابع خالی)..." 100 "LimeGreen"
    Start-Sleep -Seconds 1
    [System.Windows.Forms.MessageBox]::Show("تمامی مراحل آزمایشی با موفقیت انجام شد.", "پایان نصب", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
}

# -----------------------------------------------------------------------------
# منطق اصلی نصب
# -----------------------------------------------------------------------------
$ButtonStart.Add_Click({
    $ButtonStart.Enabled = $false
    $ButtonExit.Enabled = $false
    $ButtonStart.BackColor = [System.Drawing.Color]::Gray

    try {
        Mock-SystemCheck
        Mock-PythonInstall
        Mock-LibrariesInstall
        Mock-OllamaInstall
        Mock-ShortcutsAndFinalize
        
        $Form.Close()
    } catch {
        Update-UI "خطا در نصب: $_" $ProgressBar.Value "Red"
        $ButtonStart.Enabled = $true
        $ButtonExit.Enabled = $true
        $ButtonStart.BackColor = [System.Drawing.Color]::FromArgb(220, 53, 69)
    }
})

# -----------------------------------------------------------------------------
# نمایش فرم
# -----------------------------------------------------------------------------
$Form.ShowDialog() | Out-Null
