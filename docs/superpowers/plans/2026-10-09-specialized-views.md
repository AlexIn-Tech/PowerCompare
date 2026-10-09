# Specialized comparison views implementation plan

> **For agentic workers:** Use superpowers:executing-plans for native execution. Pester RED→GREEN is required for every behavior.

**Goal:** Implement the specialized comparison views portion of the approved full BC5 Pro Windows parity scope.
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

### Task 1: Tables

**Files:** Create `src/PowerCompare.Core/TableCompare.ps1` and `tests/Core/specialized-views-1.Tests.ps1`; add the corresponding `src/PowerCompare.UI/` view/controller when applicable.
**Interfaces:** Compare-PCTable(LeftRows, RightRows, KeyColumns, ColumnMap, NumericTolerance, DateTolerance) -> aligned cell records.
**Acceptance fixtures:** CSV/TSV/HTML/XLSX imports, multiple sheets/tables, duplicate keys, reordered columns, quoted delimiters, culture-invariant tolerances and significance/sort options.

- [ ] Write concrete Pester fixture assertions for each acceptance behavior and observe their expected failures before implementation.
- [ ] Implement the named contract and its supported format/provider policy; keep failures explicit.
- [ ] Run the fixture tests, the complete suite, and PSScriptAnalyzer.
- [ ] Exercise the Windows UI and live providers where applicable; record unavailable prerequisites as unverified.
- [ ] Commit only verified implementation and link row-level evidence in docs/parity-matrix.csv.

### Task 2: Binary and pictures

**Files:** Create `src/PowerCompare.Core/BinaryCompare.ps1 and ImageCompare.ps1` and `tests/Core/specialized-views-2.Tests.ps1`; add the corresponding `src/PowerCompare.UI/` view/controller when applicable.
**Interfaces:** Compare-PCBinary(LeftStream, RightStream) -> offset ranges; Compare-PCImage(LeftImage, RightImage, Transform, Tolerance) -> pixel model.
**Acceptance fixtures:** Hex alignment/search/editing with backup and large-file limits; pixel modes, zoom, rotations/scaling, color replacement/tolerance, format decoding and cursor inspection.

- [ ] Write concrete Pester fixture assertions for each acceptance behavior and observe their expected failures before implementation.
- [ ] Implement the named contract and its supported format/provider policy; keep failures explicit.
- [ ] Run the fixture tests, the complete suite, and PSScriptAnalyzer.
- [ ] Exercise the Windows UI and live providers where applicable; record unavailable prerequisites as unverified.
- [ ] Commit only verified implementation and link row-level evidence in docs/parity-matrix.csv.

### Task 3: Registry and metadata

**Files:** Create `src/PowerCompare.Core/RegistryCompare.ps1 and MetadataCompare.ps1` and `tests/Core/specialized-views-3.Tests.ps1`; add the corresponding `src/PowerCompare.UI/` view/controller when applicable.
**Interfaces:** Compare-PCRegistry(LeftResource, RightResource) -> key/value rows; Get-PCMediaMetadata(Path) -> typed tags; Get-PCExecutableMetadata(Path) -> version fields.
**Acceptance fixtures:** Local/remote/export registry, type-correct edits, disposable-key cleanup, executable/media fixtures and unknown-format adapters. Conversion/external-handler processes have timeout, bounded output and explicit executable paths.

- [ ] Write concrete Pester fixture assertions for each acceptance behavior and observe their expected failures before implementation.
- [ ] Implement the named contract and its supported format/provider policy; keep failures explicit.
- [ ] Run the fixture tests, the complete suite, and PSScriptAnalyzer.
- [ ] Exercise the Windows UI and live providers where applicable; record unavailable prerequisites as unverified.
- [ ] Commit only verified implementation and link row-level evidence in docs/parity-matrix.csv.

## Execution readiness

This subsystem plan preserves scope and contracts. Before its first task, refine each acceptance family into exact fixtures, format/protocol versions and UI command behavior; resolve optional adapter policy for affected work. It is not an implementation or parity claim.
