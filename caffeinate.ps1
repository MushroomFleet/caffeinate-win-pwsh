# caffeinate for Windows PowerShell - macOS parity
# Works on Windows PowerShell 5.1 and PowerShell 7+

if (-not ('Power.Caffeinate' -as [type])) {
    Add-Type -Namespace 'Power' -Name 'Caffeinate' -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true)]
public static extern uint SetThreadExecutionState(uint esFlags);
'@
}

function caffeinate {
    # NOTE: deliberately NOT an advanced function. [CmdletBinding()] would add the
    # common parameters, and -i would then be ambiguous with -InformationAction.
    # The automatic $args collects every token verbatim, which is what a Unix-style
    # CLI needs.
    $Argv = @($args)

    # ES_* constants. NOTE: 0x80000000 parses as a negative Int32 in PowerShell,
    # so it must be written as a decimal uint32 cast to stay portable.
    $ES_CONTINUOUS       = [uint32]2147483648  # 0x80000000
    $ES_SYSTEM_REQUIRED  = [uint32]1           # 0x00000001
    $ES_DISPLAY_REQUIRED = [uint32]2           # 0x00000002

    [uint32]$assert = 0
    $modes    = New-Object System.Collections.Generic.List[string]
    $timeout  = 0
    $waitPid  = 0
    $command  = @()
    $seenFlag = $false

    # --- Manual argv parse: PowerShell cannot bind Unix-style stacked flags (-sid) ---
    for ($n = 0; $n -lt $Argv.Count; $n++) {
        $a = $Argv[$n]

        if ($a -match '^-([dimsu]+)$') {
            $seenFlag = $true
            foreach ($ch in $Matches[1].ToCharArray()) {
                switch ($ch) {
                    'd' { $assert = $assert -bor $ES_DISPLAY_REQUIRED; if ($modes -notcontains 'Display') { $modes.Add('Display') } }
                    'i' { $assert = $assert -bor $ES_SYSTEM_REQUIRED;  if ($modes -notcontains 'Idle')    { $modes.Add('Idle') } }
                    's' { $assert = $assert -bor $ES_SYSTEM_REQUIRED;  if ($modes -notcontains 'System')  { $modes.Add('System') } }
                    'u' { $assert = $assert -bor $ES_DISPLAY_REQUIRED; if ($modes -notcontains 'User')    { $modes.Add('User') } }
                    'm' { if ($modes -notcontains 'Disk(n/a)') { $modes.Add('Disk(n/a)') } }  # no Windows equivalent
                }
            }
            continue
        }
        if ($a -eq '-t') { $timeout = [int]$Argv[++$n]; continue }
        if ($a -eq '-w') { $waitPid = [int]$Argv[++$n]; continue }

        # First non-flag token: everything from here on is the wrapped command.
        $command = $Argv[$n..($Argv.Count - 1)]
        break
    }

    # macOS default with no assertion flags is -i (idle sleep only; display may still sleep).
    if (-not $seenFlag) { $assert = $ES_SYSTEM_REQUIRED; $modes.Add('Idle') }

    $flags = $ES_CONTINUOUS -bor $assert
    if ([Power.Caffeinate]::SetThreadExecutionState($flags) -eq 0) {
        Write-Error "SetThreadExecutionState failed (flags=0x$('{0:X8}' -f $flags))."
        return
    }

    $modeText = $modes -join ' + '
    try {
        if ($command.Count -gt 0) {
            Write-Host "[caffeinate] ($modeText) running: $($command -join ' ')" -ForegroundColor Cyan
            $exe = $command[0]
            $rest = if ($command.Count -gt 1) { $command[1..($command.Count - 1)] } else { @() }
            & $exe @rest
        }
        elseif ($waitPid -gt 0) {
            Write-Host "[caffeinate] ($modeText) waiting on PID $waitPid. Ctrl+C to stop." -ForegroundColor Cyan
            try { (Get-Process -Id $waitPid -ErrorAction Stop).WaitForExit() }
            catch { Write-Warning "PID $waitPid not found." }
        }
        elseif ($timeout -gt 0) {
            Write-Host "[caffeinate] ($modeText) awake for $timeout s. Ctrl+C to stop." -ForegroundColor Cyan
            Start-Sleep -Seconds $timeout
        }
        else {
            Write-Host "[caffeinate] ($modeText) awake indefinitely. Ctrl+C to stop." -ForegroundColor Cyan
            while ($true) { Start-Sleep -Seconds 1 }
        }
    }
    finally {
        $null = [Power.Caffeinate]::SetThreadExecutionState($ES_CONTINUOUS)
        Write-Host "[caffeinate] sleep behaviour restored." -ForegroundColor DarkGray
    }
}

function decaffeinate {
    # Escape hatch if a caffeinate call was killed before its finally block ran.
    $null = [Power.Caffeinate]::SetThreadExecutionState([uint32]2147483648)
    Write-Host "[caffeinate] sleep behaviour restored." -ForegroundColor DarkGray
}
