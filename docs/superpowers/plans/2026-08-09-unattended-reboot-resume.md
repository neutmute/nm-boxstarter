# Unattended Reboot-Resume Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Make `base-box.ps1` apply saved concerns unattended on every run after the first (including Boxstarter reboot-resume), instead of re-prompting.

**Architecture:** `Get-Concerns` becomes config-presence-gated: first run (no JSON) prompts and saves; any run where the JSON exists loads it silently with no `Read-Host`. Reconfiguration is done by deleting the JSON file. The concern-summary print is extracted to `Show-ConcernSummary` (DRY, used by both paths).

**Tech Stack:** PowerShell 5.1, Boxstarter, Chocolatey.

## Global Constraints

- Config file: `[Environment]::GetFolderPath('MyDocuments')\neutmute-boxstarter.json` (unchanged).
- When the config file exists, `Get-Concerns` MUST NOT call `Read-Host` — zero prompts (this is what makes reboot-resume unattended).
- First run (no config file) still prompts per concern, default N (`[y/N]`, Enter = No), then saves.
- Missing keys in a saved config default to `$false`.
- Reconfiguration mechanism: delete the JSON file (documented, printed hint at load time).
- AST parse of `base-box.ps1` must report no errors after the change.

---

### Task 1: Config-gated unattended `Get-Concerns` + doc updates

**Files:**
- Modify: `C:\CodeMine\nm-boxstarter\base-box.ps1` (replace `Get-Concerns`, add `Show-ConcernSummary`)
- Modify: `C:\CodeMine\nm-boxstarter\CLAUDE.md` (Concerns section + Important Notes line)
- Modify: `C:\CodeMine\nm-boxstarter\docs\superpowers\specs\2026-08-09-concern-based-provisioning-design.md` (Interactive Prompt Flow section)

**Interfaces:**
- Consumes: `$script:ConcernDefinitions`, `Get-SavedConcerns`, `Save-Concerns` (all unchanged).
- Produces: `Get-Concerns` → `[hashtable]` of 9 bool concern keys (unchanged signature); new `Show-ConcernSummary($concerns)` prints the `[X]/[ ]` table.

- [ ] **Step 1: In `base-box.ps1`, replace the entire `Get-Concerns` function** (currently lines 111-140, from `function Get-Concerns()` through its closing `}`) with the following two functions:

```powershell
function Show-ConcernSummary($concerns)
{
    Write-Host ""
    Write-Host "--- Selected concerns ---"
    foreach ($def in $script:ConcernDefinitions) {
        $mark = if ($concerns[$def.Key]) { '[X]' } else { '[ ]' }
        Write-Host ("  {0} {1}" -f $mark, $def.Key)
    }
    Write-Host ""
}

function Get-Concerns()
{
    $saved = Get-SavedConcerns

    # Saved config present: run unattended (also covers Boxstarter reboot-resume).
    # Delete the config file to force interactive reconfiguration.
    if ($saved) {
        Write-Host "Loaded saved concerns from $script:ConfigPath (delete this file to reconfigure)"

        $concerns = @{}
        foreach ($def in $script:ConcernDefinitions) {
            $key = $def.Key
            $value = $false
            if ($saved.PSObject.Properties.Name -contains $key) {
                $value = [bool]$saved.$key
            }
            $concerns[$key] = $value
        }

        Show-ConcernSummary $concerns
        return $concerns
    }

    # First run (no saved config): prompt interactively, default No.
    $concerns = @{}
    foreach ($def in $script:ConcernDefinitions) {
        $answer = Read-Host "$($def.Prompt)? [y/N]"
        $concerns[$def.Key] = ($answer -match '^(y|yes)$')
    }

    Save-Concerns $concerns
    Show-ConcernSummary $concerns
    return $concerns
}
```

- [ ] **Step 2: Verify the unattended path has no `Read-Host` and parses**

Run (Bash, from repo root) — confirm exactly ONE `Read-Host` remains in the file (the first-run path):
```bash
grep -c "Read-Host" base-box.ps1
```
Expected: `1`

Run (PowerShell) AST parse:
```powershell
$errors = $null; [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path .\base-box.ps1).Path, [ref]$null, [ref]$errors); if ($errors) { $errors | Format-List; 'PARSE FAILED' } else { 'PARSE OK' }
```
Expected: `PARSE OK`

- [ ] **Step 3: Update `CLAUDE.md` Concerns section**

Find:
```markdown
base-box.ps1 prompts interactively for each "concern" (install area) at runtime. Answers are saved to `neutmute-boxstarter.json` in the user's Documents folder and shown as hints on subsequent runs. The prompt default is No; type `y` to opt in.
```
Replace with:
```markdown
On the first run (when no `neutmute-boxstarter.json` exists), base-box.ps1 prompts interactively for each "concern" (install area); the prompt default is No, type `y` to opt in. Answers are saved to `neutmute-boxstarter.json` in the user's Documents folder. On every subsequent run — including Boxstarter reboot-resume cycles — the saved config is applied automatically with no prompting (fully unattended). Delete `neutmute-boxstarter.json` to reconfigure.
```

- [ ] **Step 4: Update `CLAUDE.md` Important Notes line**

Find:
```markdown
- Install choices ("concerns") are prompted once and persisted to `neutmute-boxstarter.json` in Documents; the script is idempotent across re-runs
```
Replace with:
```markdown
- Install choices ("concerns") are prompted on the first run and persisted to `neutmute-boxstarter.json` in Documents; subsequent runs (including Boxstarter reboot-resume) apply the saved config unattended with no prompts. Delete the file to reconfigure. The script is idempotent across re-runs.
```

- [ ] **Step 5: Update the spec's "Interactive Prompt Flow" section**

In `docs\superpowers\specs\2026-08-09-concern-based-provisioning-design.md`, find:
```markdown
Runs at the very top of `base-box.ps1` before any installation work:

1. Check for `neutmute-boxstarter.json` in Documents
2. For each concern (fixed order matching execution order):
   - No saved config: `Install Core apps? [y/N]: `
   - Saved config exists: `Install Core apps? (saved: Yes) [y/N]: `
3. Build `$concerns` hashtable from responses
4. Save `$concerns` back to JSON (overwrite)
5. Return `$concerns`

**Default is N** (Enter = No). User must type `y` to opt in. This prevents accidental installs on unfamiliar concerns during re-runs.
```
Replace with:
```markdown
Runs at the very top of `base-box.ps1` before any installation work:

1. Check for `neutmute-boxstarter.json` in Documents.
2. **If the config file exists** (subsequent runs, including Boxstarter reboot-resume): load it and apply the saved concerns with NO prompting — fully unattended. Missing keys default to No. Print the selected-concern summary and return.
3. **If the config file does not exist** (first run): prompt for each concern (fixed order) with `Install Core apps? [y/N]:`. Default is N (Enter = No); the user types `y` to opt in. Save `$concerns` to JSON, print the summary, and return.

To reconfigure after the first run, delete `neutmute-boxstarter.json` and run again.
```

- [ ] **Step 6: Final grep sanity + commit**

Run (Bash):
```bash
grep -c "Read-Host" base-box.ps1   # expect 1
```

Commit:
```bash
git add base-box.ps1 CLAUDE.md docs/superpowers/specs/2026-08-09-concern-based-provisioning-design.md
git commit -m "Apply saved concerns unattended on reboot-resume"
```
Append this trailer to the commit message:
```
Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
```

---

## Self-Review

- Unattended path calls no `Read-Host` (Step 2 grep = 1, only first-run path). ✓
- First run still prompts default N and saves. ✓
- Missing keys default `$false`. ✓
- Reconfigure = delete file, printed + documented in CLAUDE.md and spec. ✓
- `Show-ConcernSummary` used by both paths (DRY); no duplicate summary block left in `Get-Concerns`. ✓
- No placeholders; all code/edits literal. ✓
