#!/usr/bin/env bash
# Resolve Syncthing "sync-conflict" files by keeping one version per file.
# Pure bash + GNU coreutils/findutils, so it runs on Unraid with no Python or PowerShell.
#
# For "name.ext" with copies "name.sync-conflict-YYYYMMDD-HHMMSS-DEVICE.ext", the candidates are the
# original plus every conflict copy. One is kept (see --prefer) and ends up at the original path; the
# others are deleted, or moved to --trash DIR. DRY RUN by default: nothing changes without --apply.
#
# Usage: syncthing_conflict_cleanup.sh [options] DIR [DIR...]
#   --prefer original|largest|newest   original (default): keep the original; if only conflict copies
#                                      exist, keep the largest (then newest).
#                                      largest: largest wins, ties to newest. A heuristic that can keep
#                                      stale copies and drop real edits to text/config files.
#                                      newest: newest mtime wins, ties to largest.
#   --ext .xml [--ext .ogg ...]        only handle these extensions
#   --trash DIR                        move losers here instead of deleting (keep it outside the synced folder)
#   --apply                            actually change files
#   -h, --help
set -u

prefer=original
trash=
apply=0
declare -a exts=() roots=()

usage() { sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --prefer) prefer=${2:-}; shift 2 ;;
    --ext)    e=${2:-}; e=${e,,}; [ "${e:0:1}" = . ] || e=".$e"; exts+=("$e"); shift 2 ;;
    --trash)  trash=${2:-}; shift 2 ;;
    --apply)  apply=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    *) roots+=("$1"); shift ;;
  esac
done
case "$prefer" in original|largest|newest) ;; *) echo "--prefer must be original, largest or newest" >&2; exit 2 ;; esac
[ ${#roots[@]} -gt 0 ] || { echo "give at least one directory" >&2; usage >&2; exit 2; }

re='^(.+)\.sync-conflict-[0-9]{8}-[0-9]{6}(-[A-Z0-9]+)?(\.[^.]*)?$'
sep=$'\x01'
declare -A groups=()

for root in "${roots[@]}"; do
  [ -d "$root" ] || { echo "not a directory: $root" >&2; continue; }
  while IFS= read -r -d '' f; do
    name=${f##*/}; dir=${f%/*}
    [[ $name =~ $re ]] || continue
    stem=${BASH_REMATCH[1]}; ext=${BASH_REMATCH[3]}
    if [ ${#exts[@]} -gt 0 ]; then
      ok=0; for e in "${exts[@]}"; do [ "${ext,,}" = "$e" ] && ok=1; done
      [ $ok -eq 1 ] || continue
    fi
    orig="$dir/$stem$ext"
    groups["$orig"]+="$f$sep"
  done < <(find "$root" \( -name .stfolder -o -name .stversions -o -name .git \) -prune -o -type f -name '*sync-conflict*' -print0)
done

if [ ${#groups[@]} -eq 0 ]; then echo "No conflict files found."; exit 0; fi

human() { numfmt --to=iec --suffix=B "$1" 2>/dev/null || echo "${1}B"; }

# is $1 (size mtime) better than $2 (size mtime) under the current mode?  args: s1 m1 s2 m2 mode
better() {
  local s1=$1 m1=$2 s2=$3 m2=$4 mode=$5
  if [ "$mode" = newest ]; then
    [ "$m1" -gt "$m2" ] && return 0; [ "$m1" -lt "$m2" ] && return 1
    [ "$s1" -gt "$s2" ]; return
  fi
  [ "$s1" -gt "$s2" ] && return 0; [ "$s1" -lt "$s2" ] && return 1
  [ "$m1" -gt "$m2" ]
}

[ $apply -eq 1 ] && [ -n "$trash" ] && mkdir -p "$trash"
[ $apply -eq 1 ] && echo "Mode: APPLY   prefer: $prefer" || echo "Mode: DRY RUN (pass --apply to change anything)   prefer: $prefer"
[ "$prefer" = largest ] && echo "Note: 'largest' can keep stale copies and drop real edits; review the dry run first."

resolved=0; removed=0
while IFS= read -r -d '' orig; do
  # build the candidate list: original first (if present), then the conflict copies
  cands=()
  [ -f "$orig" ] && cands+=("$orig")
  IFS="$sep" read -r -a conf <<<"${groups[$orig]}"
  for c in "${conf[@]}"; do [ -n "$c" ] && cands+=("$c"); done

  winner=""; ws=0; wm=0
  if [ "$prefer" = original ] && [ -f "$orig" ]; then
    winner=$orig
  else
    mode=$prefer; [ "$prefer" = original ] && mode=largest
    for c in "${cands[@]}"; do
      s=$(stat -c %s "$c"); m=$(stat -c %Y "$c")
      if [ -z "$winner" ] || better "$s" "$m" "$ws" "$wm" "$mode"; then winner=$c; ws=$s; wm=$m; fi
    done
  fi

  echo; echo "$orig"
  losers=()
  for c in "${cands[@]}"; do
    s=$(stat -c %s "$c"); m=$(stat -c %Y "$c")
    if [ "$c" = "$winner" ]; then tag="KEEP  "; else tag="REMOVE"; losers+=("$c"); fi
    printf '  %s %9s  %s  %s\n' "$tag" "$(human "$s")" "$(date -d "@$m" '+%Y-%m-%d %H:%M')" "${c##*/}"
  done

  if [ $apply -eq 1 ]; then
    for l in "${losers[@]}"; do
      if [ -n "$trash" ]; then
        dest="$trash/${l##*/}"; n=1
        while [ -e "$dest" ]; do dest="$trash/${l##*/}.$n"; n=$((n+1)); done
        mv -- "$l" "$dest"
      else
        rm -f -- "$l"
      fi
    done
    [ "$winner" != "$orig" ] && mv -f -- "$winner" "$orig"   # winner takes the original name
  fi
  resolved=$((resolved+1)); removed=$((removed+${#losers[@]}))
done < <(printf '%s\0' "${!groups[@]}" | sort -z)

echo
if [ $apply -eq 1 ]; then st=applied; else st="dry run, nothing changed"; fi
echo "$resolved file(s) resolved, $removed copy/copies removed; $st"
