# Resource providers and archives implementation plan

> **For agentic workers:** Use superpowers:executing-plans for native execution. Pester RED→GREEN is required for every behavior.

**Goal:** Implement the resource providers and archives portion of the approved full BC5 Pro Windows parity scope.
**Architecture:** Focused PowerShell engines and adapter contracts feed WPF views; write operations reuse identity validation, staging, backups and journals.
**Tech Stack:** PowerShell, WPF/XAML, Pester 5 and Windows CI.
**Spec:** ../specs/2026-10-09-powercompare-design.md

## Global constraints

- All application code remains PowerShell.
- Planned capabilities are never represented as implemented.
- Keep application dependencies separate from development dependencies.
- Live account/provider evidence and Windows interaction evidence are required for acceptance.
- External adapter dependency policy is pending owner clarification; unaffected built-in work can proceed.

## Review focus

- Concurrent resource changes invalidate pending writes.
- Cancellation and faults dispose handles and preserve recoverable originals.
- Unreadable input never becomes equality or a deletion instruction.
- Culture, encoding and case collisions never silently lose user data.
- Persisted/exported settings never contain credentials.

### Task 1: Provider contract suite

**Files:** Create `src/PowerCompare.Core/ProviderRegistry.ps1` and `tests/Core/providers-archives-1.Tests.ps1`; add the corresponding `src/PowerCompare.UI/` view/controller when applicable.
**Interfaces:** Register-PCProvider(Scheme, Adapter) -> registry entry; Resolve-PCProvider(Uri) -> adapter with capabilities.
**Acceptance fixtures:** Unknown schemes rejected. Read/write/delete/metadata/resume contracts, case rules, concurrent changes, reconnect, cancellation, credential omission from reports and sessions.

- [ ] Write concrete Pester fixture assertions for each acceptance behavior and observe their expected failures before implementation.
- [ ] Implement the named contract and its supported format/provider policy; keep failures explicit.
- [ ] Run the fixture tests, the complete suite, and PSScriptAnalyzer.
- [ ] Exercise the Windows UI and live providers where applicable; record unavailable prerequisites as unverified.
- [ ] Commit only verified implementation and link row-level evidence in docs/parity-matrix.csv.

### Task 2: Transfer and service adapters

**Files:** Create `src/PowerCompare.Core/Providers/*.ps1` and `tests/Core/providers-archives-2.Tests.ps1`; add the corresponding `src/PowerCompare.UI/` view/controller when applicable.
**Interfaces:** Each adapter implements Get-PCResourceCapabilities/Get-PCResourceEntries/Open-PCResourceRead/New-PCResourceWritePlan.
**Acceptance fixtures:** FTP/FTPS/SFTP/WebDAV, S3/Dropbox/OneDrive, Subversion and Windows portable devices. Test via disposable servers/test accounts; account-dependent acceptance stays unverified without live evidence. Optional dependency policy must be resolved before affected adapters.

- [ ] Write concrete Pester fixture assertions for each acceptance behavior and observe their expected failures before implementation.
- [ ] Implement the named contract and its supported format/provider policy; keep failures explicit.
- [ ] Run the fixture tests, the complete suite, and PSScriptAnalyzer.
- [ ] Exercise the Windows UI and live providers where applicable; record unavailable prerequisites as unverified.
- [ ] Commit only verified implementation and link row-level evidence in docs/parity-matrix.csv.

### Task 3: Archives and snapshots

**Files:** Create `src/PowerCompare.Core/Archives.ps1` and `tests/Core/providers-archives-3.Tests.ps1`; add the corresponding `src/PowerCompare.UI/` view/controller when applicable.
**Interfaces:** Get-PCArchiveEntries(Uri) -> entries; New-PCArchiveWritePlan(Uri, Changes) -> plan; Export-PCSnapshot(Root, Path) -> manifest.
**Acceptance fixtures:** Read/edit/nested navigation, metadata-only snapshots, traversal and decompression limits, duplicates, corrupt archives, cancellation, replacement backup and multiple archive formats.

- [ ] Write concrete Pester fixture assertions for each acceptance behavior and observe their expected failures before implementation.
- [ ] Implement the named contract and its supported format/provider policy; keep failures explicit.
- [ ] Run the fixture tests, the complete suite, and PSScriptAnalyzer.
- [ ] Exercise the Windows UI and live providers where applicable; record unavailable prerequisites as unverified.
- [ ] Commit only verified implementation and link row-level evidence in docs/parity-matrix.csv.

## Execution readiness

This subsystem plan preserves scope and contracts. Before its first task, refine each acceptance family into exact fixtures, format/protocol versions and UI command behavior; resolve optional adapter policy for affected work. It is not an implementation or parity claim.
