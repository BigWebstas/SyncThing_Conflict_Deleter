<#
.SYNOPSIS
    Resolve Syncthing "sync-conflict" files by keeping one version per file.

.DESCRIPTION
    For each file "name.ext" that has copies named
    "name.sync-conflict-YYYYMMDD-HHMMSS-DEVICE.ext", the candidates are the original plus every
    conflict copy. One candidate is kept (see -Prefer) and ends up at the original path; the rest
    are deleted, or moved to -TrashDir.

    Dry-run by default: nothing changes unless you pass -Apply.

.PARAMETER Path
    Folder(s) to scan recursively. Defaults to the current directory.

.PARAMETER Prefer
    Original (default): keep the original file; if only conflict copies exist, keep the best of them.
    Largest : keep the largest file, ties go to the newest.
              A heuristic: it can discard real edits to text/config files and revive stale copies.
    Newest  : keep the most recently modified file, ties go to the largest.

.PARAMETER Extension
    Only handle these extensions, e.g. -Extension .ogg,.jpg

.PARAMETER TrashDir
    Move losers here instead of deleting them. Keep it outside the synced folder.

.PARAMETER Apply
    Actually change files. Without it the script only prints what it would do.

.EXAMPLE
    .\Conflict.ps1                                     # dry run in the current folder
    .\Conflict.ps1 D:\Sync -Apply -TrashDir D:\Trash   # keep originals, move conflicts to the trash
    .\Conflict.ps1 D:\Sync\Photos -Prefer Largest -Extension .jpg -Apply
#>
[CmdletBinding()]
param(
    [string[]]$Path = @('.'),
    [ValidateSet('Original', 'Largest', 'Newest')]
    [string]$Prefer = 'Original',
    [string[]]$Extension = @(),
    [string]$TrashDir,
    [switch]$Apply
)

$conflictRe = '^(?<stem>.+)\.sync-conflict-\d{8}-\d{6}(?:-[A-Z0-9]+)?(?<ext>\.[^.]*)?$'
$skipDirs = @('.stfolder', '.stversions', '.git')
$exts = @($Extension | ForEach-Object { $e = $_.ToLower(); if ($e.StartsWith('.')) { $e } else { ".$e" } })

function Format-Size([long]$n) {
    if ($n -lt 1KB) { return "$n B" }
    if ($n -lt 1MB) { return ('{0:N1} KB' -f ($n / 1KB)) }
    if ($n -lt 1GB) { return ('{0:N1} MB' -f ($n / 1MB)) }
    return ('{0:N1} GB' -f ($n / 1GB))
}

function Select-Winner($files, [string]$mode, [string]$original) {
    $orig = $files | Where-Object { $_.FullName -eq $original }
    if ($mode -eq 'Original' -and $orig) { return $orig }
    if ($mode -eq 'Newest') {
        return $files | Sort-Object LastWriteTimeUtc, Length -Descending | Select-Object -First 1
    }
    # Largest, and Original when the original is missing: size first, then newest
    return $files | Sort-Object Length, LastWriteTimeUtc -Descending | Select-Object -First 1
}

# Grab the current PowerShell process and save its original priority
$currentProcess = [System.Diagnostics.Process]::GetCurrentProcess()
$originalPriority = $currentProcess.PriorityClass

try {
    # Elevate CPU priority for big trees
    Write-Host "Elevating PowerShell CPU priority to HIGH..." -ForegroundColor Cyan
    try { $currentProcess.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::High }
    catch { Write-Host "Could not raise priority (continuing): $($_.Exception.Message)" -ForegroundColor DarkYellow }

    $mode = if ($Apply) { 'APPLY' } else { 'DRY RUN (pass -Apply to change anything)' }
    Write-Host "Mode: $mode   Prefer: $Prefer" -ForegroundColor Yellow
    if ($Prefer -eq 'Largest') {
        Write-Host "Note: 'Largest' can keep stale copies and drop real edits; review the dry run first." -ForegroundColor DarkYellow
    }
    if ($TrashDir -and $Apply) { New-Item -ItemType Directory -Force -Path $TrashDir | Out-Null }

    # Find conflict files and group them by their original path
    $groups = @{}
    foreach ($root in $Path) {
        Get-ChildItem -Path $root -Filter '*sync-conflict*' -Recurse -File -Force -ErrorAction SilentlyContinue |
            Where-Object {
                $rel = $_.FullName
                -not ($skipDirs | Where-Object { $rel -match [regex]::Escape([IO.Path]::DirectorySeparatorChar + $_ + [IO.Path]::DirectorySeparatorChar) })
            } |
            ForEach-Object {
                $m = [regex]::Match($_.Name, $conflictRe)
                if (-not $m.Success) { return }
                $ext = $m.Groups['ext'].Value
                if ($exts.Count -gt 0 -and $exts -notcontains $ext.ToLower()) { return }
                $original = Join-Path $_.DirectoryName ($m.Groups['stem'].Value + $ext)
                if (-not $groups.ContainsKey($original)) { $groups[$original] = @() }
                $groups[$original] += $_
            }
    }

    if ($groups.Count -eq 0) {
        Write-Host "No conflict files found." -ForegroundColor Green
        return
    }

    $resolved = 0
    $removed = 0
    foreach ($original in ($groups.Keys | Sort-Object)) {
        $files = @($groups[$original])
        if (Test-Path -LiteralPath $original -PathType Leaf) { $files = @(Get-Item -LiteralPath $original -Force) + $files }
        $winner = Select-Winner $files $Prefer $original
        $losers = @($files | Where-Object { $_.FullName -ne $winner.FullName })

        Write-Host "`n$original" -ForegroundColor White
        foreach ($f in $files) {
            $tag = if ($f.FullName -eq $winner.FullName) { 'KEEP  ' } else { 'REMOVE' }
            $color = if ($tag -eq 'KEEP  ') { 'Green' } else { 'DarkGray' }
            Write-Host ("  {0} {1,9}  {2:yyyy-MM-dd HH:mm}  {3}" -f $tag, (Format-Size $f.Length), $f.LastWriteTime, $f.Name) -ForegroundColor $color
        }

        if ($Apply) {
            foreach ($l in $losers) {
                if ($TrashDir) {
                    $dest = Join-Path $TrashDir $l.Name
                    $n = 1
                    while (Test-Path -LiteralPath $dest) { $dest = Join-Path $TrashDir ("{0}.{1}" -f $l.Name, $n); $n++ }
                    Move-Item -LiteralPath $l.FullName -Destination $dest -Force -Verbose
                } else {
                    Remove-Item -LiteralPath $l.FullName -Force -Verbose
                }
            }
            if ($winner.FullName -ne $original) {
                Move-Item -LiteralPath $winner.FullName -Destination $original -Force   # winner takes the original name
            }
        }
        $resolved++
        $removed += $losers.Count
    }

    Write-Host "`n$resolved file(s) resolved, $removed copy/copies removed; $(if ($Apply) { 'applied' } else { 'dry run, nothing changed' })" -ForegroundColor Cyan

} finally {
    # Restore the original CPU priority even if the script is interrupted
    Write-Host "`nRestoring CPU priority back to $originalPriority..." -ForegroundColor Cyan
    try { $currentProcess.PriorityClass = $originalPriority } catch { }
}
