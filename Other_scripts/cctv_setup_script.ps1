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
        $taskName = "CCTV_Startup_Action"
        
        # Unregister existing if any
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

        # Create new task
        $trigger = New-ScheduledTaskTrigger -AtLogOn -User $Username
        # Note: For simple executable paths, specific arguments should be separated. 
        # Here we assume a simple command string for demonstration. 
        # For complex scripts, use: -Execute "powershell.exe" -Argument "-File ..."
        $action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c start $StartupCommand"
        
        Register-ScheduledTask -TaskName $taskName -Trigger $trigger -Action $action -Description "Runs CCTV startup action" -RunLevel Limited -User $Username -Force | Out-Null
        
        Write-Host "Scheduled Task '$taskName' created to run '$StartupCommand' at login." -ForegroundColor Green
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
