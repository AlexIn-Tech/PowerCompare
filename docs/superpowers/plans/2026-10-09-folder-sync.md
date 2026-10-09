# Folder operations, synchronization and merge implementation plan

> **For agentic workers:** Use superpowers:executing-plans for native execution. Pester RED→GREEN is required for every behavior.

**Goal:** Implement the folder operations, synchronization and merge portion of the approved full BC5 Pro Windows parity scope.
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

### Task 1: Operation journals

**Files:** Create `src/PowerCompare.Core/OperationJournal.ps1` and `tests/Core/folder-sync-1.Tests.ps1`; add the corresponding `src/PowerCompare.UI/` view/controller when applicable.
**Interfaces:** New-PCOperationJournal(Plan) -> immutable journal; Resume-PCOperationJournal(Journal) -> results; Restore-PCOperationBackup(Record) -> result.
**Acceptance fixtures:** Per-operation backup/recovery, interruption, stale resumes, explicit destructive previews and disposal.

- [ ] Write concrete Pester fixture assertions for each acceptance behavior and observe their expected failures before implementation.
- [ ] Implement the named contract and its supported format/provider policy; keep failures explicit.
- [ ] Run the fixture tests, the complete suite, and PSScriptAnalyzer.
- [ ] Exercise the Windows UI and live providers where applicable; record unavailable prerequisites as unverified.
- [ ] Commit only verified implementation and link row-level evidence in docs/parity-matrix.csv.

### Task 2: Synchronization and merge

**Files:** Create `src/PowerCompare.Core/FolderSync.ps1` and `tests/Core/folder-sync-2.Tests.ps1`; add the corresponding `src/PowerCompare.UI/` view/controller when applicable.
**Interfaces:** New-PCSyncPlan(LeftRoot, RightRoot, Mode, Baseline) -> operations/conflicts; New-PCFolderMergePlan(BaseRoot, LeftRoot, RightRoot, OutputRoot) -> merge plan.
**Acceptance fixtures:** Bidirectional updates and mirror deletion; unreadable or missing roots never trigger deletion. Independent changes and delete-versus-modify conflict; text merge links to text engine.

- [ ] Write concrete Pester fixture assertions for each acceptance behavior and observe their expected failures before implementation.
- [ ] Implement the named contract and its supported format/provider policy; keep failures explicit.
- [ ] Run the fixture tests, the complete suite, and PSScriptAnalyzer.
- [ ] Exercise the Windows UI and live providers where applicable; record unavailable prerequisites as unverified.
- [ ] Commit only verified implementation and link row-level evidence in docs/parity-matrix.csv.

### Task 3: Advanced folder criteria

**Files:** Create `src/PowerCompare.Core/FolderRules.ps1` and `tests/Core/folder-sync-3.Tests.ps1`; add the corresponding `src/PowerCompare.UI/` view/controller when applicable.
**Interfaces:** Resolve-PCFolderAlignment(Entries, Rules) -> matched groups/errors; Test-PCFolderFilter(Entry, Rules) -> boolean.
**Acceptance fixtures:** Flat matching, extension/mask overrides, normalization collisions, size/date/content/attributes, link traversal with cycle detection, ACL/short-name preservation and pause/resume.

- [ ] Write concrete Pester fixture assertions for each acceptance behavior and observe their expected failures before implementation.
- [ ] Implement the named contract and its supported format/provider policy; keep failures explicit.
- [ ] Run the fixture tests, the complete suite, and PSScriptAnalyzer.
- [ ] Exercise the Windows UI and live providers where applicable; record unavailable prerequisites as unverified.
- [ ] Commit only verified implementation and link row-level evidence in docs/parity-matrix.csv.

## Execution readiness

This subsystem plan preserves scope and contracts. Before its first task, refine each acceptance family into exact fixtures, format/protocol versions and UI command behavior; resolve optional adapter policy for affected work. It is not an implementation or parity claim.
