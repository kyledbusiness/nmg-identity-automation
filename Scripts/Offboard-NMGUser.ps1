<#
.SYNOPSIS
    Performs a complete offboarding of a single Active Directory
    account, per SOP-IAM-001.

.DESCRIPTION
    Runs all five steps. Documents the account and its group
    memberships, verifies that record on disk, disables the
    account, stamps the authorising ticket, randomises the
    password, removes all group memberships, and moves the
    account to the Disabled Users OU.

.EXAMPLE
    .\Offboard-NMGUser.ps1 -Username "jdoe" -Ticket "NMG-0214" -WhatIf
    Runs every check and reports what it would do, changing
    nothing. Do this first, every time.

.PARAMETER Username
    The SamAccountName of the account to offboard. Mandatory.

.PARAMETER Ticket
    The authorising ticket, in the form NMG-0000. Mandatory.

.EXAMPLE
    .\Disable-NMGUser.ps1 -Username "hgrady" -Ticket "NMG-0211" -WhatIf
    Runs every check and reports what it would do, changing nothing.

.NOTES
    Author  : Kyle Davis
    Created : 2026-10-24
    Implements steps 1, 2, and 4 of SOP-IAM-001.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$Username,

    [Parameter(Mandatory)]
    [string]$Ticket,

    [string]$ReportPath = "C:\Reports\Offboarding",
    [string]$LogPath    = "C:\nmg-identity-automation\Logs"
)

#--- SETUP --------------------------------------------------

Import-Module ActiveDirectory

$stamp = Get-Date -Format "yyyy-MM-dd_HHmm"

foreach ($p in @($ReportPath, $LogPath)) {
    if (-not (Test-Path $p)) {
        New-Item -Path $p -ItemType Directory -Force | Out-Null
    }
}

# Everything printed from here on ends up in a dated file.
# Never print a credential after this line.
Start-Transcript -Path "$LogPath\Disable-NMGUser_$stamp.log" | Out-Null

Write-Host ""
Write-Host "  DISABLE-NMGUSER" -ForegroundColor Cyan
Write-Host "  Target : $Username"
Write-Host "  Ticket : $Ticket"
Write-Host "  Run by : $env:USERNAME"
Write-Host ""

#--- THE FOUR CHECKS ----------------------------------------
# Every one of these stops the script. A warning that scrolls
# past at 4:50 on a Friday is a decoration, not a guardrail.

# CHECK 1: does the account exist at all?
$user = Get-ADUser -Identity $Username -Properties * -ErrorAction SilentlyContinue

if (-not $user) {
    Write-Host "  STOP: no account named $Username" -ForegroundColor Red
    Stop-Transcript | Out-Null
    return
}

# CHECK 2: has somebody already handled this one?
if ($user.Enabled -eq $false) {
    Write-Host "  STOP: $Username is already disabled." -ForegroundColor Yellow
    Write-Host "        Existing note: $($user.Description)" -ForegroundColor Gray
    Write-Host "        Re-running would overwrite that record." -ForegroundColor Gray
    Stop-Transcript | Out-Null
    return
}

# CHECK 3: is this a person, or is it machinery?
if ($user.SamAccountName -like "svc_*" -or $user.Department -eq "Service Accounts") {
    Write-Host "  STOP: $Username looks like a service account." -ForegroundColor Red
    Write-Host "        Find its owner first. Different procedure." -ForegroundColor Gray
    Stop-Transcript | Out-Null
    return
}

# CHECK 4: is the ticket a real shape?
if ($Ticket -notmatch "^NMG-\d{4}$") {
    Write-Host "  STOP: ticket should look like NMG-0211" -ForegroundColor Red
    Stop-Transcript | Out-Null
    return
}

Write-Host "  All checks passed for $($user.Name)" -ForegroundColor Green

#--- STEP 1: DOCUMENT ---------------------------------------
# Runs on a WhatIf too. Reading changes nothing, and the record
# is worth having either way.

$groups = Get-ADPrincipalGroupMembership -Identity $Username

$user |
  Select-Object Name, SamAccountName, Department, Title,
                LastLogonDate, Enabled, DistinguishedName |
  Export-Csv "$ReportPath\$($Username)_account_$stamp.csv" `
    -NoTypeInformation -Encoding UTF8

$groups |
  Select-Object Name, GroupCategory, DistinguishedName |
  Export-Csv "$ReportPath\$($Username)_groups_$stamp.csv" `
    -NoTypeInformation -Encoding UTF8

Write-Host "  Captured $($groups.Count) memberships" -ForegroundColor Green

#--- EDIT 2: THE VERIFICATION GATE --------------------------
# Goes immediately AFTER the two Export-Csv lines in Block 4.
#
# Read the file back from disk. $groups tells you the query
# worked. The file tells you the record actually exists.
#
# Export-Csv does not write on a dry run, so this only checks
# when the run is real. Otherwise every dry run would refuse.

if (-not $WhatIfPreference) {

    $groupFile = "$ReportPath\$($Username)_groups_$stamp.csv"

    if (-not (Test-Path $groupFile)) {
        Write-Host "  STOP: no export file was written." -ForegroundColor Red
        try { Stop-Transcript | Out-Null } catch { }
        return
    }

    $written = @(Import-Csv $groupFile)

    if ($written.Count -eq 0) {
        Write-Host "  STOP: export file is empty." -ForegroundColor Red
        Write-Host "        Refusing to remove unrecorded access." -ForegroundColor Gray
        try { Stop-Transcript | Out-Null } catch { }
        return
    }

    Write-Host "  Verified $($written.Count) memberships on disk" -ForegroundColor Green
}

#--- STEP 2: DISABLE ----------------------------------------
# ShouldProcess is what makes -WhatIf work. Everything inside
# this block is skipped on a WhatIf run, and you write nothing
# extra to make that happen.

if ($PSCmdlet.ShouldProcess($Username, "Disable account and stamp $Ticket")) {

    Disable-ADAccount -Identity $Username

    Set-ADUser -Identity $Username `
      -Description "Offboarded $(Get-Date -Format yyyy-MM-dd) | Ticket $Ticket"

    Write-Host "  Disabled and stamped." -ForegroundColor Green
}

#--- EDIT 3: THE ACTUAL FIX ---------------------------------
# Your script already has a ShouldProcess block. It protects
# the disabled. Leave that one exactly as it is.
#
# This is a SECOND one, and it goes directly after the
# disable block's closing brace.
#
# Delete the loop you pasted at the bottom in Phase 1, then
# paste this in its place.

if ($PSCmdlet.ShouldProcess($Username, "Remove $($written.Count) memberships")) {

    $removed = @()
    $failed  = @()

    foreach ($g in $groups) {

        if ($g.Name -eq "Domain Users") { continue }

        try {
            Remove-ADGroupMember -Identity $g -Members $Username `
                -Confirm:$false -ErrorAction Stop
            $removed += $g.Name
            Write-Host "  Removed: $($g.Name)" -ForegroundColor Yellow
        }
        catch {
            $failed += "$($g.Name)  ($($_.Exception.Message))"
        }
    }

    Write-Host ""
    Write-Host "  Removed : $($removed.Count)" -ForegroundColor Green

    if ($failed.Count -gt 0) {
        Write-Host "  FAILED  : $($failed.Count)" -ForegroundColor Red
        $failed | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
    }

}

#--- EDIT 1: CHECK THE DESTINATION --------------------------
# Goes AFTER the group removal block, BEFORE the move.
#
# A missing OU fails at the very end of an otherwise perfect
# run, leaving the account everywhere except where it belongs.

if (-not (Get-ADOrganizationalUnit -Filter "Name -eq 'Disabled Users'" `
          -ErrorAction SilentlyContinue)) {

    Write-Host "  STOP: Disabled Users OU not found." -ForegroundColor Red
    Write-Host "        Steps 1 to 4 are done. Move by hand." -ForegroundColor Gray
    try { Stop-Transcript | Out-Null } catch { }
    return
}

#--- EDIT 3: THE MOVE ---------------------------------------
# Inside its own ShouldProcess block. A move is reversible,
# but reversible is not the same as harmless, and anything
# that changes a live system gets declared.

if ($PSCmdlet.ShouldProcess($Username, "Move to Disabled Users")) {

    Move-ADObject -Identity $dn -TargetPath $target

    Write-Host "  Moved to quarantine." -ForegroundColor Green
}


#--- EDIT 2: BUILD THE TARGET PATH --------------------------
# Get-ADDomain hands you the root at runtime, so the path is
# never hardcoded and the script works in any domain.

$root   = (Get-ADDomain).DistinguishedName
$target = "OU=Disabled Users,$root"

# Look up where the account is RIGHT NOW. Not earlier.
$dn = (Get-ADUser -Identity $Username).DistinguishedName


#--- SUMMARY ------------------------------------------------

$final = Get-ADUser -Identity $Username -Properties MemberOf

Write-Host ""
Write-Host "  Account  : $($user.Name) ($Username)"
Write-Host "  Ticket   : $Ticket"
Write-Host "  Enabled  : $($final.Enabled)"
Write-Host "  Groups   : $($final.MemberOf.Count)"
Write-Host "  Location : $($final.DistinguishedName)"
Write-Host "  Evidence : $ReportPath"
Write-Host ""

try { Stop-Transcript | Out-Null } catch { }
