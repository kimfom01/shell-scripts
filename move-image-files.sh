#!/usr/bin/env bash
#
# move-image-files.sh — Move image files into a subfolder (e.g. "images" or "pics").
#
# Scans a source path AND all subdirectories by default, moves matching
# image files into a subfolder underneath that path.
#
# Usage:
#   ./move-image-files.sh [PATH] [DESTNAME] [OPTIONS]
#
# Examples:
#   ./move-image-files.sh                        # . -> ./images/ (recursive)
#   ./move-image-files.sh ~/Photos pics          # ~/Photos -> ~/Photos/pics/
#   ./move-image-files.sh ./Downloads images --no-recurse
#   ./move-image-files.sh ./Downloads --dry-run --verbose
#
# Options:
#   --no-recurse   Only scan the top-level folder (default: recursive)
#   --force        Overwrite existing files instead of renaming (photo_1.jpg)
#   -n, --dry-run  Preview what would be moved without moving anything
#   -v, --verbose  Detailed output
#   -h, --help     Show this help
#
set -euo pipefail

SRC="."
DESTNAME="images"
NO_RECURSE=0
FORCE=0
DRY_RUN=0
VERBOSE=0

# Default image extensions (lowercase, without dot)
EXTENSIONS="jpg jpeg png gif bmp tiff tif webp heic heif svg ico avif raw cr2 cr3 nef arw dng orf rw2 psd ai eps"

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
  echo "Extensions: $EXTENSIONS"
}

# --- Parse args (positional + flags in any order) ---
POSITIONAL=()
for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
    --no-recurse) NO_RECURSE=1 ;;
    --force) FORCE=1 ;;
    -n|--dry-run) DRY_RUN=1 ;;
    -v|--verbose) VERBOSE=1 ;;
    -*) echo "Unknown option: $arg" >&2; usage >&2; exit 1 ;;
    *) POSITIONAL+=("$arg") ;;
  esac
done
if [[ ${#POSITIONAL[@]} -ge 1 ]]; then SRC="${POSITIONAL[0]}"; fi
if [[ ${#POSITIONAL[@]} -ge 2 ]]; then DESTNAME="${POSITIONAL[1]}"; fi
if [[ ${#POSITIONAL[@]} -gt 2 ]]; then
  echo "Too many positional arguments." >&2; usage >&2; exit 1
fi

log_verbose() { [[ "$VERBOSE" -eq 1 ]] && echo "$@" || true; }

# --- Validate source ---
if [[ ! -d "$SRC" ]]; then
  echo "Error: source path not found or not a folder: $SRC" >&2
  exit 1
fi
# Canonicalize paths (no realpath dependency issues: fall back to readlink -f)
SRC_DIR="$(readlink -f "$SRC")"
DEST_DIR="$SRC_DIR/$DESTNAME"

if [[ "$DRY_RUN" -eq 0 ]]; then
  mkdir -p -- "$DEST_DIR"
  log_verbose "Destination folder: $DEST_DIR"
else
  echo "[dry-run] Would use destination: $DEST_DIR"
fi
DEST_DIR_CANONICAL="$(realpath -m "$DEST_DIR")"

is_image() {
  local filename="$1"
  local ext="${filename##*.}"
  # Files without extension or dotfiles without ext
  if [[ "$filename" == "$ext" ]]; then return 1; fi
  ext="$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')"
  case " $EXTENSIONS " in
    *" $ext "*) return 0 ;;
    *) return 1 ;;
  esac
}

# --- Collect candidate files ---
# Build find command: recursive by default, maxdepth 1 with --no-recurse.
# Always prune the destination dir so we never re-move moved files.
FIND_ARGS=("$SRC_DIR" -path "$DEST_DIR_CANONICAL" -prune -o -type f)
if [[ "$NO_RECURSE" -eq 1 ]]; then
  # -maxdepth applies globally; destination is a direct child so prune still works
  FIND_ARGS=("$SRC_DIR" -maxdepth 1 -path "$DEST_DIR_CANONICAL" -prune -o -maxdepth 1 -type f)
fi

moved=0
renamed=0
skipped=0
scanned=0

while IFS= read -r -d '' file; do
  scanned=$((scanned + 1))
  base="$(basename -- "$file")"
  if ! is_image "$base"; then
    continue
  fi

  target="$DEST_DIR_CANONICAL/$base"

  # Collision handling: photo.jpg -> photo_1.jpg, photo_2.jpg ... unless --force
  if [[ "$FORCE" -eq 0 && -e "$target" ]]; then
    name="${base%.*}"
    # Handle files like ".photo" or extensionless (already filtered, but be safe)
    if [[ "$base" == *.* ]]; then
      ext=".${base##*.}"
    else
      name="$base"; ext=""
    fi
    i=1
    while [[ -e "$DEST_DIR_CANONICAL/${name}_${i}${ext}" ]]; do
      i=$((i + 1))
    done
    target="$DEST_DIR_CANONICAL/${name}_${i}${ext}"
    renamed=$((renamed + 1))
    log_verbose "$base -> $(basename -- "$target") (renamed to avoid collision)"
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] Would move: $file -> $target"
    moved=$((moved + 1))
  else
    if [[ "$FORCE" -eq 1 ]]; then
      if mv -f -- "$file" "$target"; then
        moved=$((moved + 1))
        log_verbose "Moved: $base -> $target"
      else
        skipped=$((skipped + 1))
        echo "Warning: skipped '$file'" >&2
      fi
    else
      if mv -n -- "$file" "$target"; then
        moved=$((moved + 1))
        log_verbose "Moved: $base -> $target"
      else
        skipped=$((skipped + 1))
        echo "Warning: skipped '$file'" >&2
      fi
    fi
  fi
done < <(find "${FIND_ARGS[@]}" -print0)

if [[ "$scanned" -eq 0 && "$moved" -eq 0 ]]; then
  echo "No image files found in '$SRC_DIR'."
else
  echo "Done. Moved: $moved | Renamed (collision): $renamed | Skipped/errors: $skipped | Destination: $DEST_DIR_CANONICAL"
fi
