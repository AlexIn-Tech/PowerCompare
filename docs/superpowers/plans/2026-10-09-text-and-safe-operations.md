# Text comparison and safe operations implementation plan

> **For agentic workers:** Use superpowers:executing-plans. Native execution is already selected by the owner. Preserve Pester RED→GREEN cycles.

**Goal:** Add real side-by-side text comparison and previewed selected-file copy to the WPF workspace.
**Architecture:** Pure PowerShell engines return typed display/operation records. WPF controllers render them and explicitly confirm write plans. Resource limits and file identity checks prevent silent partial or stale operations.
**Tech Stack:** PowerShell 5.1/7, WPF/XAML, Pester 5, built-in .NET.
**Spec:** ../specs/2026-10-09-powercompare-design.md

## Global constraints

- All application code remains PowerShell.
- Pester is development-only.
- Text preview is bounded to 2 MiB per file and 4,000,000 alignment cells; exceeding alignment budget yields an explicitly limited alignment, not a false equality.
- All writes require a preview and explicit execution. Existing destination files get backups. Neither comparison nor planning writes files.
- Remote providers, destructive mirroring, archive edits, and full feature parity are not claimed by these tasks.

## Review focus

- Repeated lines and trailing newlines must remain visible in text alignment.
- Binary and malformed UTF-8 inputs must not be silently decoded and saved.
- Literal path containment must reject sibling-prefix tricks and parent traversal.
- Changed source/destination data must invalidate a copy plan even if length/timestamps are unchanged.
- Failed replacement must leave the original destination recoverable and dispose temporary files.

## Task 1: Text engine

Files: src/PowerCompare.Core/TextCompare.ps1; tests/Core/TextCompare.Tests.ps1; module exports.
Interfaces: Get-PCTextDocument(Path, MaxBytes=2097152) returns Kind, Text, Encoding, HasBom, Newline, Error. Compare-PCText(LeftText, RightText, IgnoreWhitespace, IgnoreCase, MaxAlignmentCells=4000000) returns Rows, Alignment, HasDifferences; rows expose left/right line number/text, status, and inline spans. Compare-PCTextFile(LeftPath, RightPath, MaxBytes, MaxAlignmentCells) combines document detection and comparison.

- [ ] Write Pester fixtures for empty/equal text, repeated lines, insertion/deletion/change, newline-only changes, significance options, bounded alignment, UTF BOM detection, binary content, and large-file rejection.
- [ ] Run the suite and confirm missing APIs fail.
- [ ] Implement deterministic bounded LCS with coarse alignment fallback, preserve raw text/newlines, and expose explicit document/limit statuses.
- [ ] Run all tests and analyzer; commit.

## Task 2: Copy planning and execution

Files: src/PowerCompare.Core/FileOperations.ps1; tests/Core/FileOperations.Tests.ps1; module exports.
Interfaces: New-PCCopyPlan(SourceRoot, DestinationRoot, RelativePath[]) returns read-only plan with operations, roots, identities, and plan ID. Invoke-PCCopyPlan(Plan, CancellationToken) supports ShouldProcess and returns one result per operation. IDs include length, timestamp, and SHA-256. Writes are staged to destination siblings and backed up before replacement.

- [ ] Write real-filesystem Pester fixtures asserting planning/WhatIf writes nothing, explicit copy preserves bytes, overwrite backups retain originals, stale source/destination rejects, nested paths work, overlapping roots/type conflicts/links/escape reject, and partial failures are individually reported.
- [ ] Run RED, then implement immutable plan records and containment checks, streamed identity validation, staged replacement, backup and cleanup.
- [ ] Run GREEN and the complete suite; commit.

## Task 3: WPF integration

Files: src/PowerCompare.UI/TextWindow.xaml, TextView.ps1, Application.ps1, MainWindow.xaml; tests/UI/TextView.Tests.ps1 and Windows smoke tests.
Interfaces: Show-PCTextComparison(LeftPath, RightPath) renders aligned rows with next/previous difference navigation. Selected-file copy buttons build a plan from current roots/selection, show exact paths and overwrite decisions, and execute only after explicit confirmation.

- [ ] Write tests for difference navigation bounds, selected-row eligibility, text-view XML, and Windows STA control/event loading.
- [ ] Run RED, implement views/controllers, integrate text opening and explicit copy previews.
- [ ] Run complete tests and analyzer; record unavailable Windows evidence honestly.

## Remaining subsystem plans

Text editing/three-way merge; folder operations/mirror/merge; provider and archive adapters; table/binary/image/registry/metadata views; sessions/reports/shell/VCS integration require separate plans and acceptance fixtures. Every capability remains tracked in docs/parity-matrix.csv.
