<#
.SYNOPSIS
    Installs caffeinate into your PowerShell profile(s).

.DESCRIPTION
    Writes the caffeinate function into the profile of every PowerShell host
    found on this machine - Windows PowerShell 5.1 and PowerShell 7+ use
    different profile files, so both are handled.

    Safe to re-run: the function is written between marker comments and is
    replaced in place on subsequent runs rather than appended again.

.PARAMETER Uninstall
    Removes the caffeinate block from each profile, leaving the rest intact.

.PARAMETER ProfilePath
    Install into specific profile file(s) instead of auto-discovering hosts.

.EXAMPLE
    .\install.ps1
    Install into every detected PowerShell host.

.EXAMPLE
    .\install.ps1 -Uninstall
    Remove it again.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$Uninstall,
    [string[]]$ProfilePath
)

$ErrorActionPreference = 'Stop'

$BeginMarker = '# >>> caffeinate-win-pwsh >>>'
$EndMarker   = '# <<< caffeinate-win-pwsh <<<'

function Get-HostProfile {
    # Ask each host for its own $PROFILE. This is authoritative, and handles
    # Documents being redirected to OneDrive - guessing the path does not.
    $found = @()
    foreach ($h in @(
        @{ Name = 'Windows PowerShell 5.1'; Exe = 'powershell.exe' },
        @{ Name = 'PowerShell 7+';          Exe = 'pwsh.exe' }
    )) {
        $cmd = Get-Command $h.Exe -ErrorAction SilentlyContinue
        if (-not $cmd) { continue }
        try {
            $p = & $cmd.Source -NoProfile -Command '$PROFILE' 2>$null
            if ($p) { $found += [pscustomobject]@{ Host = $h.Name; Path = $p.Trim() } }
        } catch {
            Write-Warning "Could not query $($h.Name): $_"
        }
    }
    return $found
}

function Set-ProfileBlock {
    param([string]$Path, [string]$Block)

    $dir = Split-Path -Parent $Path
    if (-not (Test-Path $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }

    $existing = if (Test-Path $Path) { [System.IO.File]::ReadAllText($Path) } else { '' }

    # Match an existing managed block, including its trailing newline.
    $pattern = [regex]::Escape($BeginMarker) + '.*?' + [regex]::Escape($EndMarker) + '\r?\n?'
    $rx = [regex]::new($pattern, 'Singleline')

    if ($rx.IsMatch($existing)) {
        $action = if ($Block) { 'updated' } else { 'removed' }
        # MatchEvaluator, not a replacement string: .NET treats $ in a replacement
        # as a substitution token, and the function body contains regex literals
        # ending in $' - which would splice the rest of the profile into itself.
        $literal = [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $Block }
        $updated = $rx.Replace($existing, $literal)
    }
    elseif ($Block) {
        $action = 'installed'
        $sep = if ($existing -and -not $existing.EndsWith("`n")) { "`r`n`r`n" } elseif ($existing) { "`r`n" } else { '' }
        $updated = $existing + $sep + $Block
    }
    else {
        return 'not present'
    }

    if ($PSCmdlet.ShouldProcess($Path, $action)) {
        # UTF-8 with BOM: read correctly by both 5.1 and 7.
        [System.IO.File]::WriteAllText($Path, $updated, [System.Text.UTF8Encoding]::new($true))
    }
    return $action
}

# --- Resolve the source function ---------------------------------------------
$source = Join-Path $PSScriptRoot 'caffeinate.ps1'
if (-not $Uninstall -and -not (Test-Path $source)) {
    throw "Cannot find caffeinate.ps1 next to this installer (expected at $source)."
}

$block = ''
if (-not $Uninstall) {
    $body = [System.IO.File]::ReadAllText($source).TrimEnd()
    $stamp = Get-Date -Format 'yyyy-MM-dd'
    $block = @"
$BeginMarker
# Installed $stamp by install.ps1 - edit caffeinate.ps1 and re-run instead of
# editing here; this block is replaced wholesale on the next install.
$body
$EndMarker
"@ -replace "`r`n", "`n" -replace "`n", "`r`n"
    $block += "`r`n"
}

# --- Work out which profiles to touch -----------------------------------------
if ($ProfilePath) {
    $targets = $ProfilePath | ForEach-Object { [pscustomobject]@{ Host = 'specified'; Path = $_ } }
} else {
    $targets = Get-HostProfile
}

if (-not $targets) {
    throw 'No PowerShell hosts found. Pass -ProfilePath to install somewhere specific.'
}

# --- Apply --------------------------------------------------------------------
$verb = if ($Uninstall) { 'Removing caffeinate from' } else { 'Installing caffeinate into' }
Write-Host "$verb $($targets.Count) profile(s):`n" -ForegroundColor Cyan

$results = foreach ($t in $targets) {
    $status = Set-ProfileBlock -Path $t.Path -Block $block
    [pscustomobject]@{ Host = $t.Host; Status = $status; Profile = $t.Path }
}
$results | Format-Table -AutoSize | Out-String | Write-Host

if ($Uninstall) {
    Write-Host "Done. Open a new shell (or run . `$PROFILE) to drop the command." -ForegroundColor Green
} else {
    Write-Host "Done. Open a new shell, or reload this one with:" -ForegroundColor Green
    Write-Host "    . `$PROFILE`n"
    Write-Host "Then:  caffeinate -sid"
    Write-Host "       caffeinate -sid -t 3600"
    Write-Host "       caffeinate -sid npm run build`n"
    Write-Host "If a profile will not load, authorise local scripts once with:" -ForegroundColor DarkGray
    Write-Host "    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser" -ForegroundColor DarkGray
}
