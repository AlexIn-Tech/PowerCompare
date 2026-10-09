# Workspace and external integration implementation plan

> **For agentic workers:** Use superpowers:executing-plans for native execution. Pester RED→GREEN is required for every behavior.

**Goal:** Implement the workspace and external integration portion of the approved full BC5 Pro Windows parity scope.
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

### Task 1: Workspace persistence

**Files:** Create `src/PowerCompare.Core/Workspaces.ps1` and `tests/Core/workspace-integration-1.Tests.ps1`; add the corresponding `src/PowerCompare.UI/` view/controller when applicable.
**Interfaces:** Save-PCWorkspace(State, Path) -> versioned document; Import-PCWorkspace(Path) -> validated state.
**Acceptance fixtures:** Restore multiple tabs/windows and unsaved buffers, autosave recovery, versions, theme/fonts/keyboard settings, drag/drop, overview, help and high-DPI keyboard accessibility.

- [ ] Write concrete Pester fixture assertions for each acceptance behavior and observe their expected failures before implementation.
- [ ] Implement the named contract and its supported format/provider policy; keep failures explicit.
- [ ] Run the fixture tests, the complete suite, and PSScriptAnalyzer.
- [ ] Exercise the Windows UI and live providers where applicable; record unavailable prerequisites as unverified.
- [ ] Commit only verified implementation and link row-level evidence in docs/parity-matrix.csv.

### Task 2: Automation and reports

**Files:** Create `src/PowerCompare.Core/Automation.ps1` and `tests/Core/workspace-integration-2.Tests.ps1`; add the corresponding `src/PowerCompare.UI/` view/controller when applicable.
**Interfaces:** Invoke-PCScriptPlan(Path, Variables) -> operation results; Export-PCWorkspaceReport(Workspace, Format) -> report files.
**Acceptance fixtures:** Noninteractive exit codes, no hidden confirmations, patch viewer/editor hooks, linked HTML reports and print output.

- [ ] Write concrete Pester fixture assertions for each acceptance behavior and observe their expected failures before implementation.
- [ ] Implement the named contract and its supported format/provider policy; keep failures explicit.
- [ ] Run the fixture tests, the complete suite, and PSScriptAnalyzer.
- [ ] Exercise the Windows UI and live providers where applicable; record unavailable prerequisites as unverified.
- [ ] Commit only verified implementation and link row-level evidence in docs/parity-matrix.csv.

### Task 3: Shell, VCS and updates

**Files:** Create `src/PowerCompare.Core/Integration.ps1` and `tests/Core/workspace-integration-3.Tests.ps1`; add the corresponding `src/PowerCompare.UI/` view/controller when applicable.
**Interfaces:** Install-PCShellIntegration(Scope) -> registration plan; Get-PCVcsLaunchArguments(Session) -> argument array; Get-PCUpdateInfo(ManifestUri) -> validated release metadata.
**Acceptance fixtures:** Per-user Windows context entries with reversible uninstall, Git and other VCS hooks/MSSCCI adapters, signature/hash verified update metadata and explicit installation choices.

- [ ] Write concrete Pester fixture assertions for each acceptance behavior and observe their expected failures before implementation.
- [ ] Implement the named contract and its supported format/provider policy; keep failures explicit.
- [ ] Run the fixture tests, the complete suite, and PSScriptAnalyzer.
- [ ] Exercise the Windows UI and live providers where applicable; record unavailable prerequisites as unverified.
- [ ] Commit only verified implementation and link row-level evidence in docs/parity-matrix.csv.

## Execution readiness

This subsystem plan preserves scope and contracts. Before its first task, refine each acceptance family into exact fixtures, format/protocol versions and UI command behavior; resolve optional adapter policy for affected work. It is not an implementation or parity claim.
