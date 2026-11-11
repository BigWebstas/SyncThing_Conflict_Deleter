# SyncThing Conflict Deleter

Resolves Syncthing `*.sync-conflict-*` files by keeping one version of each file.
Works on any folder you give it. **Dry run by default.**

Two versions with the same behavior:
- `Conflict.ps1` for Windows / PowerShell (`-Path`, `-Prefer`, ...)
- `conflict.sh` for Linux and Unraid: plain bash + coreutils, no Python or PowerShell needed

```bash
./conflict.sh DIR                                  # dry run
./conflict.sh --apply --trash /mnt/user/trash DIR  # keep originals, move conflicts to the trash
./conflict.sh --prefer largest --ext .jpg DIR      # also: --prefer newest
```

The options below are written for `Conflict.ps1`; `conflict.sh` uses the lowercase flag form (`--prefer`, `--ext`, `--trash`, `--apply`).

```powershell
.\Conflict.ps1                                      # dry run: shows KEEP / REMOVE per file
.\Conflict.ps1 -Apply                               # keep originals, delete the conflict copies
.\Conflict.ps1 D:\Sync -Apply -TrashDir D:\Trash    # move losers to a trash folder instead of deleting
.\Conflict.ps1 D:\Photos -Prefer Largest -Extension .jpg -Apply
```

| Option | Meaning |
|---|---|
| `-Path` | Folder(s) to scan recursively (default: current folder) |
| `-Prefer Original` | Default. Keep the original; if only conflict copies exist, keep the best of them (largest, then newest) |
| `-Prefer Largest` | Keep the largest file, ties go to the newest. Can keep stale copies and drop real edits to text/config files, so review the dry run |
| `-Prefer Newest` | Keep the most recently modified file, ties go to the largest |
| `-Extension` | Only handle these extensions, e.g. `.ogg,.jpg` |
| `-TrashDir` | Move losers here instead of deleting (keep it outside the synced folder) |
| `-Apply` | Actually change files |

The winner always ends up at the original filename. `.stfolder`, `.stversions` and `.git` are skipped.

**Behavior change:** the first version deleted every conflict file immediately, including conflicts
with no original. It now previews first, and never deletes the only copy of a file.
