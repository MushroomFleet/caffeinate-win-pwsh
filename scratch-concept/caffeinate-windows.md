# Caffeinate for Windows (PowerShell Script)

This is a self-contained PowerShell utility that mimics the macOS `caffeinate` CLI command. It supports native sub-flags (`-s`, `-i`, `-d`), standalone timeout durations, and process wrapping modes.

## Installation Instructions

1. **Open your PowerShell Profile:**
   Run the following command in PowerShell to open your user profile script in Notepad:
   ```powershell
   if (!(Test-Path $PROFILE)) { New-Item -Type File -Path $PROFILE -Force }; notepad $PROFILE
   ```

2. **Paste the Script:**
   Copy the code block below, paste it at the bottom of the Notepad file, save, and exit.

3. **Reload your Profile:**
   To apply the changes immediately without restarting your terminal, execute:
   ```powershell
   . $PROFILE
   ```
   *(Note: If you get a script execution error, run `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser` once to authorize local profile scripts).*

---

## PowerShell Function Code

```powershell
function caffeinate {
    [CmdletBinding(DefaultParameterSetName="Default")]
    param (
        [Parameter(Mandatory=$false, Position=0)]
        [int]$Timeout,

        [Parameter(Mandatory=$false)]
        [switch]$s,  # System sleep prevention

        [Parameter(Mandatory=$false)]
        [switch]$i,  # Idle sleep prevention

        [Parameter(Mandatory=$false)]
        [switch]$d,  # Display sleep prevention

        [Parameter(Mandatory=$false, ValueFromRemainingArguments=$true)]
        [string[]]$Command  # Command or process to run and wrap
    )

    # Base flag required for all continuous states (ES_CONTINUOUS = 0x80000000)
    [uint32]$flags = 0x80000000

    # Map flags to Windows API equivalents
    if (-not ($s -or $i -or $d)) {
        $flags += 0x00000001 # ES_SYSTEM_REQUIRED
        $flags += 0x00000002 # ES_DISPLAY_REQUIRED
        $modeText = "System + Display"
    } else {
        $modes = @()
        if ($s) { $flags += 0x00000001; $modes += "System" }
        if ($i) { $flags += 0x00000001; $modes += "Idle" } 
        if ($d) { $flags += 0x00000002; $modes += "Display" }
        $modeText = $modes -join " + "
    }

    # Load Windows API
    $signature = '[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint esFlags);'
    $PInvoke = Add-Type -MemberDefinition $signature -Name "Win32SleepApi_$([Guid]::NewGuid().ToString().Replace('-',''))" -Namespace "Power" -PassThru
    
    # Apply the wake state
    $null = $PInvoke::SetThreadExecutionState($flags)

    # Case 1: Process Wrapper Execution Mode
    if ($Command) {
        $commandString = $Command -join " "
        Write-Host "☕ Caffeinated ($modeText)! Executing command: $commandString" -ForegroundColor Cyan
        try {
            # Execute the command in the current environment
            Invoke-Expression $commandString
        } finally {
            # Ensure sleep state resets even if the executed command fails or crashes
            $null = $PInvoke::SetThreadExecutionState(0x80000000)
            Write-Host "💤 Command finished. Sleep behavior restored." -ForegroundColor Gray
        }
    }
    # Case 2: Fixed Timeout Mode
    elif ($Timeout -gt 0) {
        Write-Host "☕ Caffeinated ($modeText)! Keeping awake for $Timeout seconds. Press Ctrl+C to cancel." -ForegroundColor Cyan
        Start-Sleep -Seconds $Timeout
        $null = $PInvoke::SetThreadExecutionState(0x80000000)
        Write-Host "💤 Sleep behavior restored." -ForegroundColor Gray
    } 
    # Case 3: Indefinite / Manual Stop Mode
    else {
        Write-Host "☕ Caffeinated ($modeText)! Keeping awake indefinitely. Press Ctrl+C to stop." -ForegroundColor Cyan
        try {
            while ($true) { Start-Sleep -Seconds 1 }
        } finally {
            $null = $PInvoke::SetThreadExecutionState(0x80000000)
            Write-Host "`n💤 Sleep behavior restored." -ForegroundColor Gray
        }
    }
}
```

---

## Usage Guide & Examples

### 1. Indefinite Wake
Keeps both your computer system and your active display from turning off or going into idle standby until manually exited.
```powershell
caffeinate
```
*(Press `Ctrl + C` at any point to break out of the loop and re-enable Windows power-saving mechanisms).*

### 2. Flag Stacking (Mac Parity)
Control precisely what components remain active using concatenated sub-flags:
* **Keep only display awake:** `caffeinate -d`
* **Keep system/CPU calculations running but allow display sleep:** `caffeinate -s`
* **Stack them together:** 
  ```powershell
  caffeinate -sid
  ```

### 3. Custom Timeout Duration
Pass an integer representing time in seconds to keep your workstation alert for a specific window.
```powershell
caffeinate 3600
```
*(Keeps the computer awake for 1 hour before automatically timing out and reverting to default power configurations).*

### 4. Process-Wrapping Mode
Automatically locks the sleep cycles out for the **exact duration** of a script, binary, or compilation cycle, releasing the sleep blocks once the command terminates.
```powershell
caffeinate -sid python data_migration_script.py
```
```powershell
caffeinate -i npm run deployment-build
```
