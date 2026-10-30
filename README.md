
# NMG Identity Automation with PowerShell

**Walkthrough video:** [Watch the 5-minute project breakdown](https://www.loom.com/share/66d6e15db1c145ba81572b71c376e5dc)


**What happens when employees leave, but their Active Directory accounts don't?**

At Northstar Medical Group, a fictional healthcare organization, an offboarding process depended on one HR employee emailing IT whenever someone left. When she retired, those notifications stopped. For over 100 days, nobody realized the process had broken down.

The result? **23 former employees with lingering accounts, an 11-hour manual investigation, and an identity security problem that needed more than another spreadsheet.**

This project documents how I used PowerShell to build an identity offboarding workflow that identifies stale accounts, validates separation records, automates access removal, and preserves evidence for auditing and recovery.


## The Problem

Northstar's offboarding process had a single point of failure: one person was responsible for notifying IT about employee departures.

When that process stopped, former employees could retain access long after their employment ended.

A manual investigation eventually identified 23 stale accounts, but it took 11 hours across four days. Worse, the investigation relied on HR records that could be incomplete.

That meant several types of accounts could still slip through:

- Former employees whose departures were never recorded.
- Contractors who were never listed in payroll.
- Service accounts that were never associated with employees.

**The bigger issue wasn't just forgotten accounts. It was the lack of a reliable process to identify, review, and remove access.**

## The Solution

Rather than relying exclusively on HR records, I built PowerShell tools that query Active Directory directly to identify accounts with no recent authentication activity.

But identifying stale accounts was only the beginning.

The workflow needed to answer several questions:

1. Which accounts appear inactive but are still enabled?
2. Which accounts are actually approved for offboarding?
3. How do we prevent the wrong account from being modified?
4. What happens if an offboarding operation fails halfway through?
5. Can we prove what access was removed, when, and under which authorization?

The result is a five-tool workflow covering discovery, individual offboarding, status reporting, bulk validation, and bulk execution.

## The Tools

### 1. Find-StaleAccounts.ps1

**Find the accounts nobody is checking.**

This script queries Active Directory for enabled accounts that haven't authenticated within a configurable timeframe. It also catches accounts with no recorded logon history, which a date-only filter could miss.

Instead of manually reviewing accounts one by one, it produces a report that can be investigated and reproduced.

**Example usage:**

```powershell
.\Find-StaleAccounts.ps1
.\Find-StaleAccounts.ps1 -Days 30
.\Find-StaleAccounts.ps1 -Days 180 -IncludeDisabled
```

| Parameter | Type | Default | Purpose |
|---|---|---|---|
| `-Days` | int | 90 | Inactivity threshold |
| `-ReportPath` | string | `C:\Reports` | Report destination |
| `-IncludeDisabled` | switch | Off | Include disabled accounts |

**Evidence generated:** A timestamped CSV containing the findings and a summary documenting the query used.

### 2. Offboard-NMGUser.ps1

**Remove access without losing the evidence.**

Finding a stale account doesn't automatically mean it should be disabled. Before taking action, the script checks that the account exists, is enabled, appears to belong to a person, and has a correctly formatted authorization ticket.

Once those checks pass, it follows SOP-IAM-001 to document the account and its group memberships, verify the evidence was saved, disable the account, record the ticket, remove group memberships, and move the account into the Disabled Users OU.

The sequence matters. **You need to know what access existed before removing it, especially if something goes wrong.**

**Example usage:**

```powershell
.\Offboard-NMGUser.ps1 -Username "jdoe" -Ticket "NMG-0214" -WhatIf

.\Offboard-NMGUser.ps1 -Username "jdoe" -Ticket "NMG-0214"
```

| Parameter | Type | Default | Purpose |
|---|---|---|---|
| `-Username` | string | Required | Account's SamAccountName |
| `-Ticket` | string | Required | Authorization ticket in NMG-0000 format |
| `-ReportPath` | string | `C:\Reports\Offboarding` | Evidence destination |
| `-LogPath` | string | `Logs\` | Transcript destination |
| `-WhatIf` | switch | Off | Perform checks without making changes |

**Evidence generated:** Two timestamped CSV files documenting the account and its group memberships, plus an execution transcript.

### 3. Get-NMGOffboardingStatus.ps1

**Answer the question without changing anything.**

Not everyone reviewing the offboarding process needs permission to modify accounts.

This read-only script reports how many accounts have been offboarded and quarantined, how many are offboarded but still awaiting relocation, and how many remain outstanding.

```powershell
.\Get-NMGOffboardingStatus.ps1
```

**Output:** Three counts and two named lists displayed in the console. No files are written, and no account changes are made.

### 4. Invoke-BulkValidation.ps1

**Check the list before trusting the list.**

During the challenge, I tested a bulk offboarding process against a 40-row HR separations file. The initial unvalidated run reported zero failures, yet seven accounts belonging to people who weren't leavers were modified.

The problem wasn't execution speed. It was allowing unverified input to drive account changes.

This script separates validation from execution. It reads the original HR file, cleans a copy, checks each row against Active Directory, and generates findings for human review.

**It contains no commands that modify user accounts.**

```powershell
.\Invoke-BulkValidation.ps1 -InputFile ".\Evidence\<the file>.csv"
```

| Parameter | Type | Default | Purpose |
|---|---|---|---|
| `-InputFile` | string | Required | Original separations file, never modified |
| `-OutputPath` | string | `C:\Reports\Separations` | Validation output destination |

**Output files:**

- `Separations_dropped.csv` — cleaned separation records.
- `Validation-Report.txt` — findings for human review.
- `Approved.csv` — validated candidate list for the bulk workflow.

The validation results still require authorization before execution. A correctly formatted account can still belong to someone who is actively employed.

### 5. Invoke-BulkOffboarding.ps1

**Offboard approved accounts without losing control of the process.**

Once the separation list has been reviewed and approved, this script executes the offboarding workflow against each account.

Each account is handled as an individual transaction. If a step fails, the script attempts to roll back the account to its previous state.

It also writes results as they occur, rather than waiting until the entire batch finishes. After three consecutive failures, execution stops.

```powershell
.\Invoke-BulkOffboarding.ps1 -ApprovedList ".\Evidence\Approved.csv" -Ticket "NMG-0000" -WhatIf

.\Invoke-BulkOffboarding.ps1 -ApprovedList ".\Evidence\Approved.csv" -Ticket "NMG-0000"
```

| Parameter | Type | Default | Purpose |
|---|---|---|---|
| `-ApprovedList` | string | Required | Approved list from validation |
| `-Ticket` | string | `NMG-0215` | Authorization ticket |
| `-OutputPath` | string | `C:\Reports\Offboarding` | Evidence and results destination |
| `-BreakOn` | string | Empty | Simulates matching-account failures for testing |
| `-WhatIf` | switch | Off | Checks execution without making changes |

**Evidence generated:** Two CSV files per completed account, a `BulkRun_*.csv` results file, a summary identifying incomplete operations, and an execution transcript.

## Why the Safeguards Matter

One of the biggest lessons from this project was that **a script can execute successfully and still produce the wrong business outcome.**

These controls exist for specific reasons:

| Safeguard | Why it matters |
|---|---|
| Account existence check | Prevents attempts to modify nonexistent accounts |
| Already-disabled check | Avoids repeating completed offboarding actions |
| Service account check | Reduces the risk of treating nonhuman accounts as departing employees |
| Ticket validation | Requires an authorization reference |
| Evidence before removal | Preserves account state and group memberships for audit and rollback |
| `-WhatIf` | Allows execution behavior to be checked before making changes |
| Separate bulk validation | Prevents unreviewed HR data from directly triggering account changes |
| Human approval | Catches employment-status errors automated checks may miss |
| Rollback handling | Attempts to restore an account if offboarding fails partway through |
| Failure threshold | Stops bulk execution after three consecutive failures |

### When the Scripts Refuse

A refusal isn't necessarily an error. Sometimes it's the control doing exactly what it was designed to do.

| Message | Meaning | Next action |
|---|---|---|
| `no account named X` | Account not found | Verify the username in AD |
| `already disabled` | Account has already been disabled | Check its description and ticket |
| `looks like a service account` | Possible nonhuman identity | Identify the owner and use the appropriate process |
| `ticket should look like NMG-0000` | Invalid ticket format | Supply the four-digit ticket |
| `export file is empty` | Evidence could not be written | Verify the reports folder and permissions |
| `Disabled Users OU not found` | Quarantine destination unavailable | Steps 1–4 completed; relocate manually |
| `not a username` | Invalid username field | Correct or remove the source row |
| `duplicate of row N` | Duplicate entry | Refer to the original row |
| `STILL EMPLOYED` | Recent activity suggests the account may still be needed | Hold for Privacy Officer review |
| `STRANDED` | Operation and rollback both failed | Investigate the named account manually |

## Audit Evidence and Recovery

An offboarding operation shouldn't end with a success message. It should leave enough evidence for someone else to understand what happened.

The workflow preserves:

- **Account evidence:** Timestamped CSV files documenting the account before offboarding.
- **Access evidence:** Group membership records captured before removal.
- **Execution evidence:** Transcripts identifying the operations performed.
- **Authorization evidence:** Ticket numbers recorded in the account description.
- **Bulk results:** Account-level outcomes identifying completed, rolled-back, and stranded operations.

Preserving group memberships before removal is especially important. Without that snapshot, the workflow cannot reliably reconstruct the account's previous access from its current state alone.

This is what makes the evidence useful for both audit review and rollback.

## Getting Started

### Prerequisites

- Windows Server with Active Directory Domain Services.
- ActiveDirectory PowerShell module.
- Appropriate permissions to modify user objects.
- An authorization ticket in `NMG-0000` format.
- A Disabled Users OU at the domain root.
- A writable reports directory.

Import the Active Directory module:

```powershell
Import-Module ActiveDirectory
```

Create the offboarding reports directory if needed:

```powershell
New-Item -Path "C:\Reports\Offboarding" -ItemType Directory -Force
```

Start with the read-only discovery tool:

```powershell
.\Find-StaleAccounts.ps1
```

Review the findings and follow the documented approval process before running any account-modifying scripts.

**Important:** These tools were developed and tested in a simulated Active Directory environment. Review and adapt their safeguards, permissions, logging, and recovery procedures before considering use in a production environment.

## Known Limitations

There are a few things this project doesn't fully address yet.

- **Earlier offboarding records:** Three accounts were processed before the fifth step was implemented. They were subsequently moved into the Disabled Users OU manually, so their original execution logs don't record that relocation.
- **Service account detection:** The check relies on a naming prefix and department information. An unusually named service account could pass the filter.
- **Employment status:** The `STILL EMPLOYED` flag is inferred from recent authentication activity. It's a reason to investigate, not definitive proof that someone remains employed.

These limitations matter because automated checks are only as reliable as the data and assumptions behind them.

## Repository Structure

```text
nmg-identity-automation/
│
├── Scripts/
│   └── PowerShell automation tools
│
├── Documentation/
│   └── SOPs, runbooks, and process documentation
│
├── Evidence/
│   └── Sample reports and verification screenshots
│
├── Logs/
│   └── Execution transcripts
│
└── README.md
```

## Final Takeaway

I started this challenge learning how to query Active Directory with PowerShell. By the end, I had built an offboarding workflow that could identify inactive accounts, validate separation records, process approved removals, handle failures, and produce supporting evidence.

The most valuable lesson wasn't how quickly PowerShell could disable accounts.

**It was learning that identity automation needs to be safe, explainable, recoverable, and verifiable.**

A successful script run isn't the same thing as a successful security process.

---

**Author:** Kyle Davis

**Project:** TotalThreat 30-Day IAM Challenge

**Environment:** Simulated healthcare organization, Northstar Medical Group
