markdown
# User Account Offboarding

**Document:** SOP-IAM-001
**Author:** Kyle Davis
**Raised under:** Ticket NMG-0203
**Approved by:** R. Ito, Privacy Office

## Purpose

Defines the complete sequence for offboarding a user account at
Northstar Medical Group. Before this document, no written
offboarding standard existed.

## Before you begin

- There is a ticket from a named requester.
- Username, display name and department all match.
- No legal hold prevents action on this account.
- The account belongs to a person, not a service.

## Procedure

### 1. Document the current state
Export every attribute and group membership to a timestamped file.
Removed memberships cannot be recovered, so the record is taken
before anything changes.

### 2. Disable the account
Blocks authentication. This is the step that reduces risk, so it
happens as early as the record allows. Stamp the description with
the ticket number.

### 3. Reset the password
A random value nobody holds. If the account is ever re-enabled by
mistake, the old credential must not still work.

### 4. Remove group memberships
Disabling removes no access. Stripping the groups means a
re-enabled account can reach nothing. Domain Users is the primary
group and is skipped.

### 5. Move to the Disabled Users OU
Quarantine, so the account is never mistaken for active staff.
Last, because moving changes the object path and invalidates
earlier references.

## Retention and disposal

Retained in the Disabled Users OU for the period the retention
policy defines, then deleted on a documented schedule. Where a
legal hold is in place the clock stops and nothing is deleted
until Counsel releases it in writing.

Disabled accounts are evidence. You disable a leaver.
You do not delete them.

## Tooling

All five steps of this procedure are implemented in
`Scripts/Offboard-NMGUser.ps1`.

    .\Scripts\Offboard-NMGUser.ps1 -Username "jdoe" -Ticket "NMG-0214"

Both parameters are mandatory. The script will not run without
an authorising ticket number.

Operating instructions, including every refusal the script can
produce and what to do about each one, are in the repository
README rather than here. This document describes what should
happen. The README describes how to make it happen.

### Why step 4 has a gate in front of it

Removing group memberships is the only step in this procedure
that cannot be reversed. The CSV written moments earlier is the
only record that will ever exist of what the account could
reach, so the script reads that file back from disk and counts
the rows before the removal is reachable.

### Why step 5 goes last

Moving an object changes its distinguished name. Every earlier
step refers to the account at its original location, so a move
performed first would cause the remaining steps to fail against
a path that no longer exists.

## Reporting

`Scripts/Get-NMGOffboardingStatus.ps1` reports how many accounts
have been offboarded, how many are offboarded but not yet moved,
and how many remain. It takes no parameters and makes no changes
of any kind. It is safe for anybody to run at any time.

## Known exceptions

Two accounts, hgrady and rpace, were offboarded before step 5
was implemented and were moved into the Disabled Users OU
manually afterwards. Their evidence files and logs therefore do
not record the move.

## History

This procedure was tooled between Day 7 and Day 10. Earlier
commits refer to the script as Disable-NMGUser.ps1, which was
accurate when it performed two steps. It was renamed once it
performed all five.

## Reporting

`Scripts/Get-NMGOffboardingStatus.ps1` reports how many accounts
have been offboarded, how many are offboarded but not yet moved,
and how many remain. It takes no parameters and makes no changes
of any kind. It is safe for anybody to run at any time.

## Known exceptions

Two accounts, hgrady and rpace, were offboarded before step 5
was implemented and were moved into the Disabled Users OU
manually afterwards. Their evidence files and logs therefore do
not record the move.

## Bulk requests

This procedure describes offboarding a single account against a
single authorising ticket. Requests sometimes arrive as a list
instead, usually as a spreadsheet from Human Resources.

A list is a request, not an authorisation. It must be validated
before any account on it is actioned.

### The file you were sent is evidence

Store the original unmodified, alongside the offboarding evidence
it produced. Cleaning is performed on a copy. The original proves
what was asked for. The cleaned copy proves what was decided.

### Every row is checked before any row is actioned

For each row, confirm:

- The username exists in the directory.
- The account is not already disabled.
- The account belongs to a person, not a service.
- The person is not a current employee.

That last check is the one a spreadsheet cannot help with, and it
is the one that matters most. A row naming a current employee is
indistinguishable, on the page, from a correct row.

### A person reviews the result

Validation produces a report. The report is read by a person, and
that person decides whether to proceed. Validation that feeds
straight into action is not validation, it is a delay.

### How bulk requests are processed

Bulk offboarding runs in three separate phases. The separation
is the control. Collapsing any two of them removes it.

**Phase 1, read and clean.** Import the file, trim every field,
skip rows with no username, reject anything not shaped like a
username, and remove duplicates on the trimmed username. This
phase uses the file alone and changes nothing.

**Phase 2, check and report.** Look up every remaining row in
the directory and record, for each one, whether the account
exists, whether it is already disabled, whether it is a service
account, and whether the person appears to be a current
employee. This phase produces a report and changes nothing.

**A person reviews the report and approves it.** This step is
not optional and it is not a formality. Deciding that a named
individual should not be offboarded is a judgement rather than
a rule, and judgements require a person.

**Phase 3, act.** Offboard the accounts on the approved list.
This phase reads the approved output of phase 2 and never the
original file.

### Why the phases stay separate

A validation check placed inside the action loop runs at the
same speed as the action, with nobody watching. It will catch
conditions that are rules, such as a service account or an
already disabled account. It cannot catch a row naming a current
employee, because that row is indistinguishable from a correct
one and only a person can decide.

Validation that feeds directly into action provides no
opportunity for review. It is a delay, not a control.

### Tested

An unvalidated bulk run against a real separations file was
simulated on 12 August 2026. It reported complete success while
disabling a current employee, two service accounts, and
overwriting four existing offboarding records, with no evidence
captured for any of the 32 accounts modified.

See `Documentation/Blast-Radius-Findings.md`.

### The validation report

Phase 2 produces a report for human review and a separate
approved list for phase 3. The two files have different
audiences and are not interchangeable.

`Validation-Report.txt` is written to be read by a person.
`Approved.csv` is written to be parsed by phase 3.

### Report format

The report presents findings in three tiers, ordered by what a
wrong decision costs. The format is part of the control. A
future version that flattens it into a single table has removed
the control without changing a single check.

**Tier 1, at the top, alone.** Any row where a wrong decision
would cause a person to lose access they need, or a system to
stop working. Stated as a question, with enough context to
answer it. Nothing appears above it on the page.

**Tier 2.** Rows requiring a decision where nothing is urgent.
Service accounts and previously offboarded records. Grouped and
listed once.

**Tier 3.** Rows dropped mechanically, where the tool is certain
and human review adds nothing. Counted and summarised, never
itemised. Full detail is available in the dropped file.

The report ends with the number of accounts that will be
offboarded if it is approved. That number is what the approver
is signing.

### Who approves

The Privacy Officer, or a delegate named in writing. Approval is
recorded by replying to the report, and the reply is stored with
the evidence for that run.

### Why the tiering matters

A reviewer reads the first few rows of a list carefully and the
remainder progressively less so. This is a description of
everybody rather than a criticism of anybody. A report that
presents forty rows of equal weight therefore spends most of the
reviewer's attention on rows that required none, and a row that
needed a decision can be approved without being read.

A review that is performed but not really done is worse than no
review, because it converts an unchecked action into an approved
one and attaches a name to it.

---

Built during the TotalThreat 30-Day Challenge in a simulated
healthcare environment. Northstar Medical Group is fictional.
