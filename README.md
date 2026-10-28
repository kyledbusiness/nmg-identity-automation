# NMG Identity Automation with Powershell

PowerShell tooling for identity lifecycle management, built for a fictional health enterprise named
Northstar Medical Group.

## The Problem

Northstar had no consistent and reliable way to identify user accounts belonging
to people who no longer worked there. The offboarding process was made up of a single employee who notified IT by email when someone left.
When she retired, the notifications stopped, and nobody noticed for over 100 days.

A manual search identified 23 stale accounts and took 11 hours
across 4 days. It could not identify accounts belonging to people whose
separation was never recorded, contractors who were never on payroll,
or service accounts that were never people at all.

## The Approach

Rather than comparing directory records against payroll records, these
tools search the domain controller directly for the last authentication
date of every single account. That value does not depend on paperwork being
filed correctly or names matching between systems.

## Before you start

- Windows Server with the ActiveDirectory PowerShell module

      Import-Module ActiveDirectory

- Rights to modify user objects in the domain
- An authorising ticket number, in the form NMG-0000
- A Disabled Users OU at the root of the domain
- A writable reports folder. Create it if it does not exist:

      New-Item -Path "C:\Reports\Offboarding" -ItemType Directory -Force

## Tools

### Find-StaleAccounts.ps1

This tool identifies enabled accounts that have not authenticated within a given
number of days, including accounts that have never authenticated in the first place.
Exports a timestamped CSV along with a summary recording the exact query used.

    .\Find-StaleAccounts.ps1
    .\Find-StaleAccounts.ps1 -Days 30
    .\Find-StaleAccounts.ps1 -Days 180 -IncludeDisabled

| Parameter | Type | Default | Description |
|---|---|---|---|
| `-Days` | int | 90 | Days without authentication before an account is considered stale |
| `-ReportPath` | string | C:\Reports | Where reports are written |
| `-IncludeDisabled` | switch | off | Include disabled accounts in results |

**Output:** a timestamped CSV of findings, and a summary file recording
the question that produced them so the report can be reproduced.

### Offboard-NMGUser.ps1

Performs all five steps of SOP-IAM-001 against a single account.
Documents the account and its group memberships, verifies that
record on disk, disables the account, stamps the authorising
ticket, removes all group memberships, and moves the account to
the Disabled Users OU.

    .\Offboard-NMGUser.ps1 -Username "jdoe" -Ticket "NMG-0214" -WhatIf
    .\Offboard-NMGUser.ps1 -Username "jdoe" -Ticket "NMG-0214"

| Parameter | Type | Default | Description |
|---|---|---|---|
| `-Username` | string | required | SamAccountName of the account to offboard |
| `-Ticket` | string | required | Authorising ticket, in the form NMG-0000 |
| `-ReportPath` | string | C:\Reports\Offboarding | Where evidence files are written |
| `-LogPath` | string | Logs\ | Where the run transcript is written |
| `-WhatIf` | switch | off | Runs every check and changes nothing |

**Output:** two timestamped CSV files per account recording what
it was and what it could reach, plus a transcript of the run.

### Get-NMGOffboardingStatus.ps1

Reports how many accounts have been offboarded and quarantined,
how many are offboarded but not yet moved, and how many are still
waiting. Takes no parameters and makes no changes of any kind.

    .\Get-NMGOffboardingStatus.ps1

**Output:** three counts and two named lists, printed to the
console. Nothing is written to disk.

### Invoke-BulkValidation.ps1

Reads a separations list, cleans a copy, checks every row against
Active Directory, and writes a report for human review plus an
approved list for the bulk script. Contains no command that can
modify an account.

    .\Invoke-BulkValidation.ps1 -InputFile ".\Evidence\<the file>.csv"

| Parameter | Type | Default | Description |
|---|---|---|---|
| `-InputFile` | string | required | The separations file, as received. Never modified |
| `-OutputPath` | string | C:\Reports\Separations | Where the cleaned copy, report and approved list go |

**Output:** `Separations_dropped.csv`, `Validation-Report.txt`,
and `Approved.csv`. The report is for a person. The approved list
is for the bulk script.

### Invoke-BulkOffboarding.ps1

Runs all five steps of SOP-IAM-001 against every account on an
approved list. Each account is atomic: it completes or is rolled
back. Every outcome is written to disk the moment it is known.
Stops after 3 consecutive failures.

    .\Invoke-BulkOffboarding.ps1 -ApprovedList ".\Evidence\Approved.csv" -Ticket "NMG-0000" -WhatIf
    .\Invoke-BulkOffboarding.ps1 -ApprovedList ".\Evidence\Approved.csv" -Ticket "NMG-0000"

| Parameter | Type | Default | Description |
|---|---|---|---|
| `-ApprovedList` | string | required | The approved list from Invoke-BulkValidation |
| `-Ticket` | string | NMG-0215 | Authorising ticket, stamped on every account |
| `-OutputPath` | string | C:\Reports\Offboarding | Where evidence and results are written |
| `-BreakOn` | string | empty | Test hook. Simulates a failure on matching accounts. Does nothing unless passed |
| `-WhatIf` | switch | off | Runs every step and changes nothing |

**Output:** two CSV files per completed account, a `BulkRun_*.csv`
results file with one line per account, a summary naming every
account that did not complete, and a transcript in `Logs/`.

## When the script refuses

A refusal is the tool working correctly. It stops before making
any change at all, and tells you why.

| Message | What it means | What to do |
|---|---|---|
| no account named X | The username is wrong, or the account is already gone | Check the spelling in Active Directory |
| already disabled | Somebody has handled this one before you | Read the description field for the ticket number |
| looks like a service account | This is not a person | Find the owner. It needs a different procedure |
| ticket should look like NMG-0000 | The ticket format is wrong | Use the full four digit form |
| export file is empty | The record could not be written | Check the reports folder exists and is writable |
| Disabled Users OU not found | The destination is missing | Steps 1 to 4 completed. Move the account by hand |
| not a username | An ID or a display name in the username column | Correct it at source, or drop the row |
| duplicate of row N | Same person listed twice | No action. Handled at row N |
| STILL EMPLOYED | The person appears to still work here | Do not proceed. Ask the Privacy Officer |
| STRANDED | A step failed and the rollback failed too | Manual review. The account is named in the results file |

## What an offboarding leaves behind

- Two timestamped CSV files per account in `Evidence/`. One
  records the account, one records every group it could reach.
- One transcript per run in `Logs/`, naming every membership
  removed.
- The authorising ticket number stamped on the account
  description in Active Directory.

The CSV of group memberships is the only record that will ever
exist of what an account could reach beforehand. Active Directory keeps no
history of a removed memberships.

## Known limitations

- Three accounts were offboarded before step 5 was implemented
  and were moved into the Disabled Users OU manually afterwards.
  Their logs do not record the move.
- The service account check matches on a name prefix and a
  department. An unusually named service account could get past it.
- STILL EMPLOYED is inferred from a recent logon. It is a signal
  for a person to check, not a verdict.

## Repository Structure

    Scripts/        PowerShell tools
    Documentation/  Runbooks and process documentation
    Evidence/       Sample output and verification screenshots
    Logs/           Execution logs

## Environment

Windows Server with Active Directory Domain Services.
Requires the ActiveDirectory PowerShell module.

## About

Built during the TotalThreat 30-Day Challenge in a simulated
healthcare environment.

Author: Kyle Davis
