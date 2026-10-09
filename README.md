# PowerCompare

PowerCompare is being refactored into a Windows WPF comparison application with all application logic in PowerShell. The original single-file WinForms prototype has been replaced by a reusable UI and independently testable engine.

![PowerCompare screenshot](img/Screenshot%202026-10-09%20150901.png)

**Current status: development preview.** PowerCompare is an independent PowerShell application for comparing files and folders. Implemented capabilities and planned improvements are tracked in [the feature roadmap](docs/parity-matrix.csv).

## Implemented in this branch

- Recursive local folder comparison with relative-path alignment, content hashing, metadata comparison, name filters, and explicit error/type-conflict rows.
- Background runspaces, cancellation, reusable virtualized results, and protection against stale worker results.
- Side-by-side text comparison with line numbers, inserted/deleted/changed lines, inline highlighting, and difference navigation.
- Selected-file copy in either direction, explicit preview/confirmation, immutable plans, stale-file rejection, streamed staged writes, and overwrite backups.
- Editable text with undo/redo, literal search/replace, wrapping, significance controls, and background recomparison.
- Encoding-preserving text saves with backups and stale-edit rejection; bounded three-way merge with explicit conflict choices.
- Saved local sessions and JSON, CSV, and escaped HTML reports.
- A headless JSON comparison command and a Pester TDD suite.

The foundation passed Windows CI on Windows PowerShell 5.1 and PowerShell 7, including WPF loading and repeated Compare events. Editor and merge validation is tracked in [PR #3](https://github.com/AlexIn-Tech/PowerCompare/pull/3). Interactive desktop acceptance remains open; see [validation evidence](docs/validation.md). Advanced text features, folder synchronization, remote/cloud protocols, archives, specialized viewers, and other planned features are tracked as outstanding.

## Run on Windows

Requirements: Windows PowerShell 5.1 or PowerShell 7 with Windows desktop support. Download/clone the **whole repository**, not just the launcher. No application dependencies need to be installed.

```powershell
.\PowerCompare.ps1
# Or prefill the roots:
.\PowerCompare.ps1 -LeftPath C:\Left -RightPath C:\Right
```

The launcher relaunches itself in STA when needed. It does not change your execution policy. Select the folders and click **Compare**. Content mode verifies SHA-256 hashes; metadata matches do not verify content. Include/exclude masks are separated by semicolons and match relative paths using `/` separators. Blank includes select all entries.

Select a file present on both sides and choose **Open text comparison**, or double-click its row. Select source files and choose the desired copy direction to review every source/destination before executing. Folder selection does not recursively copy children: select the files to copy. File operations record per-file results and backup paths in the **File operations** tab. Compare again after copying to refresh folder results.

Save/load sessions stores local roots, mode, and masks. Export reports after a completed comparison. A session never starts file operations automatically.

## Automation

The engine supports local folder comparison without loading WPF, including on PowerShell 7 on Linux:

```powershell
.\PowerCompare.ps1 -NoGui -LeftPath C:\Left -RightPath C:\Right -Mode Content
# Output is always a JSON array, including zero or one result.

Import-Module .\src\PowerCompare.Core\PowerCompare.Core.psd1
Compare-PCFolder -LeftPath C:\Left -RightPath C:\Right -Mode Content
Compare-PCTextFile -LeftPath C:\Left\file.txt -RightPath C:\Right\file.txt
$session = New-PCSession -LeftPath C:\Left -RightPath C:\Right
Save-PCSession $session .\session.json
```

For guarded scripted copies:

```powershell
$plan = New-PCCopyPlan -SourceRoot C:\Left -DestinationRoot C:\Right -RelativePath @('nested/file.txt')
$plan.Operations # Review actual paths and Create/Overwrite actions first.
Invoke-PCCopyPlan $plan -WhatIf
Invoke-PCCopyPlan $plan -Confirm
```

## Limits and recovery

- Links and junctions are reported without traversal; copy roots must not overlap. OneDrive/cloud placeholder reparse points are supported as local files and folders, subject to provider availability. Copy operations are for local files.
- Text previews default to 2 MiB per file and 20,000 lines. Exact alignment is bounded to 4,000,000 cells; the viewer explicitly labels coarse fallback alignment. Binary and malformed Unicode data are not silently decoded. The viewer does not edit files yet.
- Files changed after preview invalidate the relevant copy operation. A failed file does not abandon other valid files. Cancellation preserves already completed copies and removes staged files where possible; review each result.
- Overwritten files are backed up beside their destination with a `.powercompare-backup-<id>` suffix. Retain or remove backups deliberately after verifying results. Session/report overwrites also retain backups.
- Atomic replacement depends on the destination filesystem. Unsupported replacements fail instead of falling back to a delete-then-copy overwrite. This is not a transactional multi-file synchronization tool yet.

## Development and verification

Development dependencies are Pester 5.7.1 and PSScriptAnalyzer 1.24.0. The launcher does not install or load them. `Validate.ps1` also discovers repository-local copies under the ignored `TestResults/modules` directory.

```powershell
.\scripts\Install-DevDependencies.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Validate.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\Validate.ps1
```

All validation runs locally. `Validate.ps1` runs the full Pester suite with coverage and checks analyzer errors using the selected runtime. It returns nonzero on failure and saves test, coverage, and analyzer reports under `TestResults/PowerShell-5` or `TestResults/PowerShell-7`. Unsupported test prerequisites are reported as skipped. For focused tests, use `scripts/Test.ps1 -Path <test-file>`.

To include a read-only check of an existing OneDrive/cloud comparison root, set `$env:PC_CLOUD_TEST_ROOT` to its path before validation. The test does not modify that folder.

See [the design](docs/superpowers/specs/2026-10-09-powercompare-design.md) and [the foundation plan](docs/superpowers/plans/2026-10-09-wpf-foundation.md).

## License

MIT. See [LICENSE](LICENSE).

## Text editing and merge

Open a file present on both sides with **Open text**, then choose **Edit left** or **Edit right**. Saves require confirmation, preserve detected UTF-8/16/32 encoding and BOM, retain an adjacent backup, and reject external file changes. The editable document limit is 2 MiB. Uniform line endings are preserved; mixed line endings require an explicit LF, CRLF or CR choice because the desktop text control normalizes them.

Choose **Three-way merge** and select the common base file. Independent changes merge automatically. Resolve every conflict with Left, Right, Base or Both, then preview the result and open the editor to save to the right file. Both concatenates left then right exactly. Saving revalidates all input identities. Exact alignment has a four-million-cell limit; larger merges fail explicitly rather than approximating conflict decisions. Advanced search, syntax coloring, manual alignment, bookmarks, patch input and format conversions remain open.

The GitHub Actions workflow has been removed to avoid hosted runner costs.
