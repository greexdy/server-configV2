<#
.SYNOPSIS
    Prepares a Windows PC for dedicated CCTV operation.

.DESCRIPTION
    - Creates a local 'CCTV' user.
    - Configures AutoAdminLogon for this user.
    - Optionally sets up a scheduled task to run a specific script/action at logon.
    
.NOTES
    OS: Windows 10/11
    Run as Administrator.
#>

# --- CONFIGURATION SECTION ---
$Username = "CCTV"
# Group membership (Basic User rights only)
$GroupName = "Users"

# --- RUN LAST ACTION / STARTUP CONFIGURATION ---
# Set $EnableStartupAction to $true to automatically run a command when the CCTV user logs in.
$EnableStartupAction = $false 

# The command or script path to execute at login if enabled.
# Example: "C:\Path\To\Your\MonitoringSoftware.exe" or "powershell.exe -File C:\Scripts\Start-CCTV.ps1"
$StartupCommand = "notepad.exe" 
# ---------------------------------------------

# Check for Administrator privileges
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "This script requires Administrator privileges. Please run as Administrator."
    exit 1
}

try {
    Write-Host "=== CCTV User Setup Initiated ===" -ForegroundColor Cyan

    # 1. Create User
    $user = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue
    if ($user) {
        Write-Host "User '$Username' already exists. Skipping creation." -ForegroundColor Yellow
        # We still need the password for AutoLogon configuration
        $passwordSecure = Read-Host "Please enter the EXISTING password for '$Username' to configure AutoLogon" -AsSecureString
    }
    else {
        Write-Host "Creating new user '$Username'..."
        $passwordSecure = Read-Host "Please enter a NEW password for user '$Username'" -AsSecureString
        New-LocalUser -Name $Username -Password $passwordSecure -FullName "CCTV Account" -Description "Dedicated Account for CCTV Monitoring" -PasswordNeverExpires -ErrorAction Stop
        
        # Ensure user is in the correct group (and remove from others if necessary, though New-LocalUser defaults to Users)
        # Note: New-LocalUser creates a member of 'Users' by default.
        Write-Host "User '$Username' created successfully." -ForegroundColor Green
    }

    # Convert SecureString to plain text for Registry (AutoAdminLogon requires plain text in Reg)
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($passwordSecure)
    $passwordPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)

    # 2. Configure AutoAdminLogon
    Write-Host "Configuring AutoAdminLogon..."
    $logonKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
    
    Set-ItemProperty -Path $logonKey -Name "AutoAdminLogon" -Value "1" -Force
    Set-ItemProperty -Path $logonKey -Name "DefaultUserName" -Value $Username -Force
    Set-ItemProperty -Path $logonKey -Name "DefaultPassword" -Value $passwordPlain -Force
    # Ensure Domain is set to local machine name to avoid domain login attempts if joined
    Set-ItemProperty -Path $logonKey -Name "DefaultDomainName" -Value $env:COMPUTERNAME -Force

    Write-Host "AutoAdminLogon configured for user '$Username'." -ForegroundColor Green

    # 3. Configure Startup Action (Optional)
    if ($EnableStartupAction) {
        Write-Host "Configuring Startup Action..."
        
        # --- PREPARE ASSETS ---
        $sharedDir = "C:\ProgramData\CCTV"
        if (-not (Test-Path $sharedDir)) {
            New-Item -Path $sharedDir -ItemType Directory -Force | Out-Null
        }
        
        # Locate and Copy Wallpaper
        $scriptPath = $PSScriptRoot
        if (-not $scriptPath) { $scriptPath = Get-Location }
        $sourceImage = Join-Path $scriptPath "..\Images\RTS_Wallpaper.jpg"
        $destImage = Join-Path $sharedDir "wallpaper.jpg"
        
        if (Test-Path $sourceImage) {
            Copy-Item -Path $sourceImage -Destination $destImage -Force
            Write-Host "Wallpaper copied to '$destImage'." -ForegroundColor Green
        }
        else {
            Write-Warning "Wallpaper not found at '$sourceImage'. Skipping wallpaper setup."
        }

        # --- GENERATE LOGIN SCRIPT ---
        $loginScriptPath = Join-Path $sharedDir "login_script.ps1"
        $loginScriptContent = @"
# CCTV Login Helper Script
# Sets wallpaper and starts application

try {
    # Set Wallpaper
    `$wallpaperPath = "$destImage"
    if (Test-Path `$wallpaperPath) {
        `$code = @'
using System;
using System.Runtime.InteropServices;
public class Wallpaper {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
'@
        Add-Type -TypeDefinition `$code
        [Wallpaper]::SystemParametersInfo(20, 0, `$wallpaperPath, 3)
    }
} catch {
    # Ignore wallpaper errors to ensure app starts
}

# Start Application
Start-Process "$StartupCommand"
"@
        Set-Content -Path $loginScriptPath -Value $loginScriptContent -Force
        
        # --- CONFIGURE SCHEDULED TASK ---
        $taskName = "CCTV_Startup_Action"
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

        $trigger = New-ScheduledTaskTrigger -AtLogOn -User $Username
        # Run the helper script hidden
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$loginScriptPath`""
        
        $principal = New-ScheduledTaskPrincipal -UserId $Username -LogonType Interactive -RunLevel Limited
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 0
        
        Register-ScheduledTask -TaskName $taskName -Trigger $trigger -Action $action -Principal $principal -Settings $settings -Description "Runs CCTV startup action and sets wallpaper" -Force | Out-Null
        
        Write-Host "Scheduled Task '$taskName' created." -ForegroundColor Green
    }
    else {
        Write-Host "Startup action is disabled in configuration. Skipping." -ForegroundColor Gray
    }

    Write-Host ""
    Write-Host "=== Setup Complete ===" -ForegroundColor Cyan
    Write-Host "The system is ready. Reboot to test Auto-Login."
    Write-Host ""

}
catch {
    Write-Error "An error occurred: $_"
    exit 1
}
