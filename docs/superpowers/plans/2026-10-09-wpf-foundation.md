# PowerCompare WPF Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans for native execution, or superpowers:subagent-driven-development if the owner chooses delegation. Steps use checkbox syntax for tracking.

**Goal:** Deliver the tested local comparison engine and responsive WPF workspace that underpin full Beyond Compare 5 Pro Windows feature parity.

**Architecture:** A PowerShell module owns comparison and resource contracts. PowerShell UI controllers load declarative XAML and communicate with background runspaces through a bounded queue. Subsequent subsystems consume these contracts; this foundation alone does not satisfy full parity.

**Tech Stack:** PowerShell, WPF/XAML, built-in .NET, Pester 5, PSScriptAnalyzer, GitHub Actions.

**Spec:** ../specs/2026-10-09-powercompare-design.md

## Global Constraints

- Application logic, UI event handlers, and automation remain PowerShell; no embedded C# application implementation.
- Preserve the MIT license and the PowerCompare.ps1 launch command.
- Windows PowerShell 5.1 and PowerShell 7 compatibility are proposed runtime targets.
- Pester 5 is a development dependency, not a launcher requirement.
- Every behavior uses a failing test, minimal implementation, and passing refactor cycle.
- No parity or Windows UI readiness claim without the corresponding acceptance evidence.
- Optional external protocol/format dependencies await owner clarification; this plan uses only built-in APIs.

## Review Focus

- Literal wildcard and Unicode paths must identify actual files, not patterns: Task 2.
- Equal timestamps and lengths must not hide differing bytes in content mode: Task 3.
- A source becoming unreadable must not be presented as an empty or equal tree: Tasks 2 and 3.
- A canceled or obsolete comparison must not replace newer UI results: Task 4.
- Closing the window during hashing must release workers and file handles: Task 5.

## File Responsibilities

- PowerCompare.ps1: validated Windows/STA launcher.
- src/PowerCompare.Core/PowerCompare.Core.psd1 and .psm1: public engine module and focused function imports.
- src/PowerCompare.Core/Resources.ps1: local resource enumeration and capability records.
- src/PowerCompare.Core/FolderCompare.ps1: matching and comparison criteria.
- src/PowerCompare.UI/MainWindow.xaml: resizable tabbed WPF workspace.
- src/PowerCompare.UI/Controller.ps1: state changes and dispatcher updates.
- src/PowerCompare.UI/Workers.ps1: runspace lifecycle and cancellation.
- tests/Core, tests/UI: Pester unit/integration fixtures.
- scripts/Test.ps1: reproducible failing-exit test runner.
- .github/workflows/test.yml: Windows runtime matrix and artifacts.
- docs/parity-matrix.csv: row-level feature acceptance ledger.

### Task 1: Test harness and parity ledger

**Files:** Create scripts/Test.ps1, tests/Harness.Tests.ps1, docs/parity-matrix.csv, and .github/workflows/test.yml; update README.md.

**Interfaces:** Test.ps1 accepts [string] Path='tests' and [switch] Coverage; exits 0 only when all selected tests pass. Ledger columns: Id, Workstream, Capability, Status, Plan, Test, WindowsEvidence, Notes.

- [ ] Write harness fixtures asserting that a deliberately failing child suite causes a nonzero exit, and a passing suite exits 0; use a subprocess rather than calling exit in the parent test process.
- [ ] Run Invoke-Pester ./tests/Harness.Tests.ps1 -Output Detailed and confirm failure because the runner is absent.
- [ ] Implement the runner using Pester 5 configuration and Run.PassThru; check FailedCount and discovery errors. Keep dependency installation in development setup and CI.
- [ ] Populate the ledger with individually identifiable BC5 Windows software features from the official reference; mark every row Planned, and link foundation rows to Tasks 2–5. Record platform-only nonapplicable entries explicitly.
- [ ] Configure Windows PowerShell 5.1 and pwsh CI jobs with pinned compatible development dependencies, NUnit results, coverage artifacts, and PSScriptAnalyzer errors as failures.
- [ ] Verify harness tests pass, inspect ledger coverage against each reference category, and commit this task.

### Task 2: Local resource contracts and enumeration

**Files:** Create module manifest/loader, Resources.ps1, and tests/Core/Resources.Tests.ps1.

**Interfaces:** Get-PCResourceCapabilities([uri] Uri) returns Scheme, CanRead, CanWrite, CanDelete, SupportsResume, SupportsAtomicReplace. Get-PCResourceEntries([uri] Uri, [System.Threading.CancellationToken] CancellationToken) returns RelativePath, EntryType, Uri, Length, LastWriteTimeUtc, Attributes, Error. Open-PCResourceRead([uri] Uri) returns a FileStream that the caller must dispose. Local file URIs only in this task; unknown schemes throw NotSupportedException.

- [ ] Write tests using TestDrive for nested/empty roots, Unicode names, a literal '[draft].txt', missing/file roots, inaccessible descendants, reparse points, and canceled enumeration. Assert relative paths and explicit error rows; root validation throws, descendant failures do not disappear.
- [ ] Run Invoke-Pester ./tests/Core/Resources.Tests.ps1 -Output Detailed and verify missing-command failures.
- [ ] Implement literal-path enumeration with a directory stack, root normalization, no reparse traversal, cancellation checks, and deterministic output; export exact contracts from the module.
- [ ] Run the resource tests and static analysis on the module. Exercise supported reparse/access-denied fixtures on Windows, marking unsupported fixture prerequisites explicitly rather than passing them silently.
- [ ] Commit the verified resource contract.

### Task 3: Recursive comparison engine

**Files:** Create FolderCompare.ps1 and tests/Core/FolderCompare.Tests.ps1; update module exports.

**Interfaces:** Compare-PCFolder([string] LeftPath, [string] RightPath, [ValidateSet('Metadata','Content')][string] Mode='Content', [string[]] Include=@('*'), [string[]] Exclude=@(), [System.Threading.CancellationToken] CancellationToken) returns rows with RelativePath, EntryType, LeftPath, RightPath, LeftLength, RightLength, LeftLastWriteTimeUtc, RightLastWriteTimeUtc, Status, ComparisonMode, Error. Status is Equal, Different, LeftOnly, RightOnly, TypeConflict, Error, or MetadataMatch. Metadata agreement returns MetadataMatch, never content-verified Equal.

- [ ] Write fixtures asserting nested equal/different entries, empty roots, one-sided entries, file/directory conflicts, same-size/same-time differing content, include/exclude behavior, ambiguous case collisions, unreadable files, and cancellation. Assert no wildcard-path expansion and no equal status on read failures.
- [ ] Run Invoke-Pester ./tests/Core/FolderCompare.Tests.ps1 -Output Detailed and confirm failure before implementation.
- [ ] Implement relative-path indexing with Windows ordinal case-insensitive matching, explicit collision detection, streamed SHA-256 content hashing, cancellation during reads, and disposed handles. Combine enumeration failures into comparison error rows.
- [ ] Run all core tests, then verify files can be removed immediately after comparison and cancellation to detect leaked handles.
- [ ] Commit the independently usable engine and document its CLI usage.

### Task 4: Background comparison orchestration

**Files:** Create Workers.ps1 and tests/UI/Workers.Tests.ps1.

**Interfaces:** Start-PCComparisonWorker([hashtable] Request, [long] Generation) returns a worker record with Generation, PowerShell, Handle, CancellationSource, Queue. Receive-PCWorkerMessages([object] Worker) drains typed Progress, Result, Error, Completed, or Canceled records tagged with Generation. Stop-PCComparisonWorker([object] Worker) requests cancellation; Close-PCComparisonWorker([object] Worker) ends and disposes owned resources. Testable controller function Test-PCCurrentGeneration([long] Current, [long] Incoming) returns boolean.

- [ ] Write tests proving cancellation emits Canceled, a worker failure emits Error, old generations are rejected, and worker disposal permits immediate fixture deletion. Assert result ordering and bounded progress publication.
- [ ] Run Invoke-Pester ./tests/UI/Workers.Tests.ps1 -Output Detailed and confirm missing-function failures.
- [ ] Implement isolated runspace imports, a thread-safe message queue, throttled progress, structured errors, and idempotent teardown. Never touch WPF objects from a worker.
- [ ] Run worker and core tests together, including repeated start/cancel/dispose cycles.
- [ ] Commit the verified orchestration layer.

### Task 5: WPF workspace and launcher

**Files:** Replace PowerCompare.ps1; create MainWindow.xaml, Controller.ps1, tests/UI/Controller.Tests.ps1, and tests/UI/Wpf.Smoke.Tests.ps1.

**Interfaces:** Show-PCMainWindow() loads XAML on an STA Windows thread. New-PCWorkspaceState() returns current generation, roots, filters, mode, active worker, and result collection. Invoke-PCCompareRequest([object] State, [hashtable] Request) validates roots and starts Task 4 worker. Update-PCWorkspace([object] State, [object[]] Messages) applies only current-generation records. Close-PCWorkspace([object] State) cancels and disposes owned workers.

- [ ] Write controller tests for invalid roots, repeated requests, late result rejection, errors, and closing while hashing. Write Windows STA smoke assertions that named controls exist, results are reused, and a comparison reaches completion while dispatcher input remains serviceable.
- [ ] Run controller tests and verify they fail before implementing controllers; run smoke tests on Windows and record their initial failure.
- [ ] Implement a resizable tabbed home/folder workspace, left/right root inputs, browse, comparison mode, filters, cancel, status/progress, and virtualized aligned results. Load PresentationFramework using Add-Type -AssemblyName only. Bind controller state and use a dispatcher timer to consume worker messages.
- [ ] Implement launcher checks for supported Windows runtime and STA, relaunching the same script in STA when necessary without losing arguments; never alter execution policy automatically.
- [ ] Run all Pester tests on both Windows runtimes and perform resizing, keyboard, repeated-compare, cancel, and window-close smoke checks. On Linux, report WPF checks as unavailable.
- [ ] Commit the working foundation and update README with verified usage and remaining parity gaps.

### Task 6: Foundation review and next subsystem plans

**Files:** Update docs/parity-matrix.csv and create separate plans for text/merge, safe operations/synchronization, providers/archives, specialized views, and integration/workspace completion.

**Interfaces:** Every ledger row links to a concrete subsystem plan and behavioral acceptance evidence before being marked Accepted.

- [ ] Run scripts/Test.ps1 and PSScriptAnalyzer on the supported Windows runtime matrix; inspect actual CI results before declaring foundation success.
- [ ] Review the parity ledger against the official chart; verify none of the expanded scope was deleted or marked complete by a placeholder UI or capability stub.
- [ ] Produce subsystem plans with exact function contracts and Pester acceptance fixtures, resolving optional-adapter policy before planning its affected formats/protocols.
- [ ] Record Windows evidence, outstanding limitations, and measured performance; commit documentation.
- [ ] Present foundation evidence and next subsystem plan for review. Do not declare the overall objective complete until the full parity ledger is accepted.

## Execution Handoff

This plan is ready for owner review. Native execution is recommended for the foundation because tasks share module contracts and worker state. Delegation remains available if the owner chooses it. Implementation begins after plan review and execution-method selection; full parity remains the overarching goal.
