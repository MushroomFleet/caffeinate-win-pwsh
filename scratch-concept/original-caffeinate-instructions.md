Here is how you can create a reusable function so you can simply type caffeinate in your PowerShell terminal, just like on a Mac.

## Step 1: Open your PowerShell Profile

Run this command in PowerShell to open your profile script in Notepad (it will create the file if it doesn't exist yet):

> if (!(Test-Path $PROFILE)) { New-Item -Type File -Path $PROFILE -Force }; notepad $PROFILE


## Step 2: Paste the Code

Paste the following block into the Notepad window that pops up, then save and close the file:

---
function caffeinate {
    param (
        [Parameter(Mandatory=$false)]
        [int]$Timeout
    )

    # Set up the Windows API flags
    $signature = '[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint esFlags);'
    $PInvoke = Add-Type -MemberDefinition $signature -Name "Win32SleepApi_$([Guid]::NewGuid().ToString().Replace('-',''))" -Namespace "Power" -PassThru
    
    # 0x80000003 = Continuous + System Required + Display Required
    $null = $PInvoke::SetThreadExecutionState(0x80000003)

    if ($Timeout) {
        Write-Host "☕ Caffeinated! Keeping Windows awake for $Timeout seconds. Press Ctrl+C to cancel early." -ForegroundColor Cyan
        Start-Sleep -Seconds $Timeout
        # Restore normal sleep behavior
        $null = $PInvoke::SetThreadExecutionState(0x80000000)
        Write-Host "💤 Sleep behavior restored." -ForegroundColor Gray
    } else {
        Write-Host "☕ Caffeinated! Keeping Windows awake indefinitely. Press Ctrl+C to stop." -ForegroundColor Cyan
        try {
            while ($true) { Start-Sleep -Seconds 1 }
        } finally {
            # Restore normal sleep behavior when user hits Ctrl+C
            $null = $PInvoke::SetThreadExecutionState(0x80000000)
            Write-Host "`n💤 Sleep behavior restored." -ForegroundColor Gray
        }
    }
}
---

## Step 3: Refresh Your Terminal

To apply the changes immediately without restarting PowerShell, run:

> . $PROFILE


(If you get a script execution error, run Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser once to allow personal scripts to run).

## How to use it:

- Keep awake indefinitely:

> caffeinate

(Press Ctrl + C when you are done to let the computer sleep normally again).


- Keep awake for a specific time (e.g., 1 hour / 3600 seconds):

> caffeinate -Timeout 3600

## ADVANCED -sid OPERATION

On macOS, combining flags like caffeinate -sid alters what exactly is kept awake:

- -s: Keeps the System awake (only on AC power).
- -i: Prevents Idle sleep (the core CPU/OS).
- -d: Keeps the Display (screen) turned on.

In the Windows API, these distinct behaviors are controlled via the exact same Hexadecimal flags passed to SetThreadExecutionState.

## The Refined PowerShell Function

We can rewrite the function to support -System, -Idle, and -Display switch parameters, mapping perfectly to -s, -i, and -d.

Replace the previous script in your PowerShell profile (notepad $PROFILE) with this complete, feature-rich version:

---
function caffeinate {
    [CmdletBinding(DefaultParameterSetName="Default")]
    param (
        [Parameter(Mandatory=$false)]
        [int]$Timeout,

        [Parameter(Mandatory=$false)]
        [switch]$s,  # System sleep prevention

        [Parameter(Mandatory=$false)]
        [switch]$i,  # Idle sleep prevention

        [Parameter(Mandatory=$false)]
        [switch]$d   # Display sleep prevention
    )

    # Base flag required for all continuous states
    # ES_CONTINUOUS = 0x80000000
    [uint32]$flags = 0x80000000

    # Map flags to Windows API equivalents
    # If no flags are provided, we default to keeping BOTH system and display awake (-id equivalent)
    if (-not ($s -or $i -or $d)) {
        $flags += 0x00000001 # ES_SYSTEM_REQUIRED
        $flags += 0x00000002 # ES_DISPLAY_REQUIRED
        $modeText = "System + Display"
    } else {
        $modes = @()
        if ($s) { $flags += 0x00000001; $modes += "System" }
        if ($i) { $flags += 0x00000001; $modes += "Idle" } # Windows merges Idle/System requests
        if ($d) { $flags += 0x00000002; $modes += "Display" }
        $modeText = $modes -join " + "
    }

    # Load Windows API
    $signature = '[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint esFlags);'
    $PInvoke = Add-Type -MemberDefinition $signature -Name "Win32SleepApi_$([Guid]::NewGuid().ToString().Replace('-',''))" -Namespace "Power" -PassThru
    
    # Apply the wake state
    $null = $PInvoke::SetThreadExecutionState($flags)

    if ($Timeout) {
        Write-Host "☕ Caffeinated ($modeText)! Keeping awake for $Timeout seconds. Press Ctrl+C to cancel." -ForegroundColor Cyan
        Start-Sleep -Seconds $Timeout
        $null = $PInvoke::SetThreadExecutionState(0x80000000)
        Write-Host "💤 Sleep behavior restored." -ForegroundColor Gray
    } else {
        Write-Host "☕ Caffeinated ($modeText)! Keeping awake indefinitely. Press Ctrl+C to stop." -ForegroundColor Cyan
        try {
            while ($true) { Start-Sleep -Seconds 1 }
        } finally {
            $null = $PInvoke::SetThreadExecutionState(0x80000000)
            Write-Host "`n💤 Sleep behavior restored." -ForegroundColor Gray
        }
    }
}
---

Reload your profile with . $PROFILE to apply it.


## How to use the Mac-Equivalent Flags:

Keep only the screen/display from turning off (caffeinate -d):

> caffeinate -d

Keep system/CPU running, but let the monitor go dark (caffeinate -s or -i):

> caffeinate -s

Replicate your exact custom stack (caffeinate -sid):
PowerShell allows you to stack switch arguments right next to each other seamlessly:

> caffeinate -sid


Combine with a timer (caffeinate -sid -Timeout 1800):

> caffeinate -sid 1800


## PROCESS WRAPPING (Super-Advanced)

Here is the fully upgraded caffeinate function. This addition mimics the macOS behavior where you can pass an executable or command at the end (e.g., caffeinate -sid python script.py), keeping the PC awake only for the exact duration of that process.

## Step 1: Replace Your Profile Code

Open your profile (notepad $PROFILE) and replace the old function entirely with this complete script:

---
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

---

Remember to save, close, and refresh your current shell using:

> . $PROFILE

## How to use Process-Wrapping Mode:

The function dynamically senses whether you're typing a command or a time limit. If anything text-based follows your flags, it wraps it.

- Prevent idle sleep while running a python script:

> caffeinate -i python download_data.py


- Keep the display and system awake while compiling or downloading over a long command sequence:

> caffeinate -sid npm run build


- Keep it awake while executing an independent executable program (.exe):

> caffeinate -d C:\Tools\BackupUtility.exe --all

(Once the script, command, or executable completes its task, the terminal will cleanly exit the API loop and restore Windows' native power-saving settings automatically).


