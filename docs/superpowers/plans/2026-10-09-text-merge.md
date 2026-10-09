# Editable text and merge implementation plan

> **For agentic workers:** Use superpowers:executing-plans for native execution. Pester RED→GREEN is required for every behavior.

**Goal:** Implement the editable text and merge portion of the approved full BC5 Pro Windows parity scope.
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

### Task 1: Editing and significance

**Files:** Create `src/PowerCompare.Core/TextEditing.ps1` and `tests/Core/text-merge-1.Tests.ps1`; add the corresponding `src/PowerCompare.UI/` view/controller when applicable.
**Interfaces:** Get-PCTextEditPlan(Path, Text, ExpectedIdentity, Encoding, Newline) -> immutable save plan; Invoke-PCTextEditPlan(Plan) -> backup/result.
**Acceptance fixtures:** Encoding and newline preservation, stale edits, lossless supported encodings, backups, undo/redo and dynamic recomparison.

- [ ] Write concrete Pester fixture assertions for each acceptance behavior and observe their expected failures before implementation.
- [ ] Implement the named contract and its supported format/provider policy; keep failures explicit.
- [ ] Run the fixture tests, the complete suite, and PSScriptAnalyzer.
- [ ] Exercise the Windows UI and live providers where applicable; record unavailable prerequisites as unverified.
- [ ] Commit only verified implementation and link row-level evidence in docs/parity-matrix.csv.

### Task 2: Two/three-way merge

**Files:** Create `src/PowerCompare.Core/TextMerge.ps1` and `tests/Core/text-merge-2.Tests.ps1`; add the corresponding `src/PowerCompare.UI/` view/controller when applicable.
**Interfaces:** Merge-PCText(BaseText, LeftText, RightText) -> segments with Base/Left/Right ranges, AutoMergedText, Conflicts; Resolve-PCTextMerge(Segments, Choices) -> output.
**Acceptance fixtures:** Independent edits merge; overlapping edits conflict; deletion versus modification, repeated lines, insertions at the same boundary and final newline changes.

- [ ] Write concrete Pester fixture assertions for each acceptance behavior and observe their expected failures before implementation.
- [ ] Implement the named contract and its supported format/provider policy; keep failures explicit.
- [ ] Run the fixture tests, the complete suite, and PSScriptAnalyzer.
- [ ] Exercise the Windows UI and live providers where applicable; record unavailable prerequisites as unverified.
- [ ] Commit only verified implementation and link row-level evidence in docs/parity-matrix.csv.

### Task 3: Advanced text views

**Files:** Create `src/PowerCompare.Core/TextEditor.xaml` and `tests/Core/text-merge-3.Tests.ps1`; add the corresponding `src/PowerCompare.UI/` view/controller when applicable.
**Interfaces:** Show-PCTextEditor(Session) -> WPF workspace; Get-PCSyntaxSpans(Text, Grammar) -> category ranges.
**Acceptance fixtures:** Search/replace, wrapping, bookmarks, syntax/significance, replacement rules, manual alignment, clipboard and patch input. Document conversions are adapters, not native document edits.

- [ ] Write concrete Pester fixture assertions for each acceptance behavior and observe their expected failures before implementation.
- [ ] Implement the named contract and its supported format/provider policy; keep failures explicit.
- [ ] Run the fixture tests, the complete suite, and PSScriptAnalyzer.
- [ ] Exercise the Windows UI and live providers where applicable; record unavailable prerequisites as unverified.
- [ ] Commit only verified implementation and link row-level evidence in docs/parity-matrix.csv.

## Execution readiness

This subsystem plan preserves scope and contracts. Before its first task, refine each acceptance family into exact fixtures, format/protocol versions and UI command behavior; resolve optional adapter policy for affected work. It is not an implementation or parity claim.
