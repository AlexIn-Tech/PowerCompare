# PowerCompare WPF refactor and full feature parity

Status: owner approved the refactor on 2026-10-09, selected WPF/XAML, and expanded the objective to full feature parity. The implementation plan requires review before execution.

## Objective and constraints

Evolve the existing PowerCompare repository into a reliable Windows desktop file and folder comparison application inspired by Beyond Compare. Keep application logic, UI event handlers, and automation in PowerShell, using WPF/XAML for the Windows desktop interface. Preserve the MIT license and the PowerCompare.ps1 launch command.

The owner requested a production-grade Beyond Compare equivalent in full PowerShell and explicitly requires TDD with Pester. The parity baseline is Beyond Compare 5 Pro on Windows. Windows PowerShell 5.1 and PowerShell 7 compatibility are retained as proposed runtime targets. Delivery is incremental, but the objective is not complete until the full parity acceptance matrix passes. WPF does not support macOS or Linux; engine portability does not imply desktop portability.

## Existing application assessment

The repository contains a single approximately 6 KB WinForms script, a README, and a license. The script imports a WindowsForms module, enumerates only immediate children, and passes FileInfo objects to Compare-Object without an explicit relative-path or content comparison contract. Comparison runs on the UI thread. Each click adds another results control. There are no tests, CI workflows, input validation, text comparison, synchronization, or recoverable error handling.

## Selected approach

The owner selected option 2: replace WinForms with WPF and XAML. Use a tabbed workspace, reusable comparison views, virtualized result lists, keyboard commands, and dispatcher-marshaled updates. Keep state, algorithms, controllers, and automation in PowerShell; XAML is declarative presentation. No embedded C# application implementation.

## Foundation delivery scope

- Recursive folder comparison matched by relative path, showing equal, different, left-only, right-only, type-conflict, and error results.
- Fast size/timestamp comparison and an explicit content mode using streamed SHA-256 hashes. Fast results must not be labeled content-verified.
- Side-by-side text comparison with aligned inserted, deleted, and changed lines, line numbers, and next/previous difference navigation. Detect binary input and enforce documented preview limits.
- Include/exclude filters and a differences-only display.
- Selected-file copy in either direction through a preview containing exact source, destination, and overwrite actions. Require explicit confirmation in the application, revalidate files before execution, preserve overwritten files in a backup location, and report individual failures.
- Saved local comparison sessions and CSV/JSON comparison reports.
- Background comparison through PowerShell runspaces, cancellation, progress, and UI updates marshaled to the UI thread.
- A script launcher, documented installation and limitations, automated engine tests, static analysis, and Windows CI.

The foundation is an intermediate delivery, not the completion criterion. Deletion-based mirroring, three-way merge, remote protocols, archive browsing, image comparison, and table comparison remain required in subsequent deliveries. Track all capabilities in the parity matrix; a missing capability must remain open rather than being silently excluded.

## Architecture and contracts

PowerCompare.ps1 validates the Windows desktop runtime and STA mode, imports the application modules, and launches the UI. UI code owns presentation and user decisions. Engine modules do not load WPF and expose comparison, text alignment, report, session, and copy-plan functions usable from PowerShell directly.

Each comparison row contains RelativePath, EntryType, LeftPath, RightPath, left/right size and timestamp, Status, ComparisonMode, and Error. Relative paths are matched case-insensitively on Windows; ambiguous collisions and file/directory conflicts produce explicit errors or conflicts. Missing and inaccessible roots fail validation rather than being treated as empty directories. Inaccessible descendants remain visible as errors. Reparse points are reported and excluded from traversal and copy in the foundation delivery.

The synchronization planner produces immutable operation records with source and destination identities and expected metadata. The executor rejects path escape, overlapping roots, type conflicts, reparse-point traversal, and changed inputs. It copies to a temporary sibling file before replacing a destination, retains an overwrite backup, and records the result. The foundation has no automatic delete operation. The full synchronization subsystem adds previewed mirror deletions and recoverable operation journals; deletion is never inferred from an unreadable source.

Session files store paths, filters, and comparison preferences, never credentials. Invalid or unsupported session data produces a clear recoverable error. Reports describe observed results and do not execute operations.

## Text comparison and performance

Use a PowerShell line-diff algorithm with deterministic alignment and bounded resource use. Preserve input encoding and newline information for display; the foundation milestone is a comparison viewer, so it does not silently rewrite either file. Large or binary files show an explanatory fallback and folder-level content status. Preview size limits are documented and configurable within safe bounds.

Directory traversal and hashing stream data. Cancellation is checked between entries and within long reads. Hashing avoids loading entire files into memory. The UI keeps a single reusable results view and remains responsive while workers run. Worker failures are surfaced without losing the user's selected roots.

## Validation and release criteria

Use Pester 5 for test-driven development throughout the refactor. For each behavior, add and run a meaningful failing test first, implement the smallest working change, then refactor with the suite passing. Add characterization tests for useful existing behavior before extracting it; known defects receive regression tests expressing the corrected behavior. Keep test dependencies separate from application runtime dependencies: users do not need Pester to launch the app.

Place engine and orchestration tests under tests/ and provide a PowerShell test runner that exits unsuccessfully on failures. Mock external interactions where needed, but use actual temporary files for content comparison and copy safety tests. Extract UI orchestration into functions testable without an interactive desktop; retain Windows UI smoke checks for actual controls, threading, and event behavior.

Engine tests use temporary directory fixtures covering empty roots, nested changes, same-size different content, Unicode and literal wildcard paths, inaccessible or missing paths, type conflicts, filters, and reparse points where the runner supports them. Text tests cover repeated lines, insertions, deletions, empty files, newline differences, and preview limits. Copy tests cover preview-only behavior, overwrite backup, stale plans, path containment, cancellation, and partial failures.

Windows CI runs the Pester suite and PSScriptAnalyzer on Windows PowerShell 5.1 and PowerShell 7, publishes test results and coverage, and fails on failed tests or analyzer errors. Coverage is used to identify untested branches, especially file-operation failure paths, rather than substituting for behavioral assertions. Windows UI smoke validation covers launching, resizing, repeated comparisons, cancellation, text navigation, and copy confirmation. A Linux engine test pass alone is insufficient to claim Windows desktop readiness.

Production readiness requires passing supported-runtime checks, successful Windows UI validation, documented failure behavior, and a versioned release artifact. Signing requires an owner-provided signing identity and is a later release decision.

## Proposed delivery sequence

1. Extract and verify the folder comparison engine and command-line API.
2. Replace the existing form with a responsive reusable comparison UI.
3. Add the text comparison viewer and navigation.
4. Add guarded copy planning, execution, and backups.
5. Add sessions, reports, compatibility CI, and release documentation.

Each milestone must be usable and validated before progressing. Implementation plans are split by subsystem. Review the foundation plan before execution; later plans must preserve the full parity matrix and define acceptance tests for their own capabilities.


## Full parity workstreams

The reference is the official BC5 feature chart and Pro edition description, checked on 2026-10-09:
- https://www.scootersoftware.com/kb/feature_compare
- https://www.scootersoftware.com/kb/editions
- https://www.scootersoftware.com/v5help/index.html

The matrix groups the source capabilities; detailed task plans must decompose them into individual testable rows before implementation. All rows initially have status Planned. Implemented, tested, and accepted are separate states. A parity claim requires the accepted state for every applicable Windows software capability. Vendor staffing and Apple-specific support are not Windows application functionality.

| Workstream | Required capability families | Acceptance evidence |
| --- | --- | --- |
| Workspace | Tabs, saved state, shell entry points, customization, help, updates | Windows interaction fixtures and restoration tests |
| Text | Editable comparison, configurable significance/alignment, merge, search, conversions | Golden alignment/merge fixtures and encoding-safe save tests |
| Structured data | Tables, column mappings, keyed alignment, tolerances, worksheet selection | Format fixtures and deterministic matching tests |
| Binary | Hex comparison/editing, byte alignment, search | Byte-level fixtures and lossless saves |
| Registry | Live/export comparison and editing | Disposable-key integration tests and export round trips |
| Images | Visual difference modes, transforms, tolerances | Generated pixel fixtures and Windows rendering checks |
| Metadata | Executable and media metadata, external format handlers | Format fixtures and adapter contract tests |
| Folders | Flexible criteria/filters/alignment, operations, synchronization, folder merge, link policies | Real filesystem tests and stale-operation rejection |
| Providers | Local/SMB, transfer protocols, cloud services, repository and device access | Provider contracts plus live integration in dedicated fixtures |
| Archives | Browse/edit archive trees and filesystem snapshots | Archive round trips, traversal defense, snapshot fixtures |
| Integration | Automation, reports, patch views, editor, source-control hooks | CLI exit-code tests and Windows integration checks |

## Provider and format architecture

Use a common resource contract: Get-PCResourceCapabilities(Uri), Get-PCResourceEntries(Uri), Open-PCResourceRead(Uri), and New-PCResourceWritePlan(SourceUri, DestinationUri). Capabilities advertise read, write, delete, metadata, resume, and atomic replacement support. UI actions are disabled when the provider cannot fulfill their contract; this remains a recorded parity gap until implemented. Local filesystem semantics must not be assumed for remote resources.

Each format adapter returns a typed comparison model and exposes supported edit/save operations. A conversion records its tool, version, source identity, and options; lossy conversion must not overwrite the original document as if it were a native edit. External processes run without shell interpolation, with bounded output, cancellation, timeouts, and explicit executable selection.

Application code remains PowerShell. Whether optional third-party libraries or installed tools are allowed for formats and protocols absent from built-in .NET is pending owner clarification. No unsupported provider is to be represented as implemented. Foundation work does not depend on this decision.

## Full parity validation

Maintain a row-level acceptance inventory linked to implementation tasks, Pester fixtures, supported format/protocol versions, and Windows UI checks. Include credential handling, reconnect/resume, provider-specific case sensitivity, concurrent remote changes, archive path containment, merge conflicts, and encoding preservation. Use disposable resources for destructive integration tests. Keep credentials out of saved sessions and reports; live-service tests require configured test accounts and are explicitly marked unverified when unavailable.

Performance acceptance must include documented measurements for large directory trees and large files on identified hardware. No numerical claim is made before a reproducible benchmark exists. Full parity and production readiness are separate gates: feature coverage cannot replace fault recovery, responsiveness, packaging, or supported-runtime verification.
