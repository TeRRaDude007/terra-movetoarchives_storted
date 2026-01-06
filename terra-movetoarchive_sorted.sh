#!/bin/bash
# ============================================================
# TeRRaDude MoveToArchive Script v1.16 (Sorted)
# Supports flexible GLROOT + SITEROOT, sandbox, live moves
# Alphabet directories configurable (_A or A)
# VA releases follow ALPHABET_SUBFOLDER_STYLE
# Skipped releases moved to already_in_archive
# Tracks total size of moved releases
# Debian 12+ compatible
#
# Note:
# Please take note that these scripts come without instructions on how to set
# them up, it is sole responsibility of the end user to understand the scripts
# function before executing them. If you do not know how to execute them, then
# please don't use them. They come with no warranty should any damage happen due
# to the improper settings and execution of these scripts (missing data, etc).
#
# Changelog:
# 2026-01-04 v1.0   - Initial version
# 2026-01-04 v1.13  - Unified all log entries with ARCHDIRLOG:
# 2026-01-04 v1.15  - Added GLROOT + SITEROOT for flexible paths
# 2026-01-04 v1.16  - Added exit 0 at end of script
# ============================================================

########################
# CONFIGURATION SETTINGS
########################

# -----------------------------------------------------------
# GLROOT
# -----------------------------------------------------------
# Root of your glftpd installation
# Example: GLROOT="/glftpd" or GLROOT="/jail/glftpd/"
GLROOT="/glftpd"

# -----------------------------------------------------------
# SITEROOT
# -----------------------------------------------------------
# Site-specific folder inside glftpd
# Example: SITEROOT="/site"
SITEROOT="/site"

# -----------------------------------------------------------
# SANDBOX MODE
# -----------------------------------------------------------
# true  = dry-run; no actual moves, logs actions to SANDBOX_LOG
# false = live moves; logs to gllog
SANDBOX=true

# SANDBOX log (dry-run testing)
SANDBOX_LOG="$GLROOT/ftp-data/logs/movetoarchive_sandbox.log"

# -----------------------------------------------------------
# LOGGING
# -----------------------------------------------------------
# LIVE log (for Eggdrop monitoring) or gllog="" for off
# For theme file setup us in pzs-ng = ARCHDIRLOG
gllog="$GLROOT/ftp-data/logs/glftpd.log"

# -----------------------------------------------------------
# BASE PATHS
# -----------------------------------------------------------
# Root directory for unsorted releases
UNSORTED_BASE="$GLROOT$SITEROOT/_ARCHiVE/MUSiC/Unsorted"

# SECTION_MAP maps the Unsorted folder name to the final archive path
# Key = Unsorted subfolder
# Value = Final archive base folder
declare -A SECTION_MAP=(
  ["VINYL"]="$GLROOT$SITEROOT/_ARCHiVE/MUSiC/ViNYL"
  ["CDM"]="$GLROOT$SITEROOT/_ARCHiVE/MUSiC/CDM"
  ["CD"]="$GLROOT$SITEROOT/_ARCHiVE/MUSiC/ALBUMS"
)

# -----------------------------------------------------------
# EXCLUDED PATHS
# -----------------------------------------------------------
# Paths that should never be scanned or moved
# Only PRE folders are excluded; Unsorted directories are included
EXCLUDE_PATHS=(
  "/PRE"
  "/GROUPS"
)

# -----------------------------------------------------------
# ALREADY_IN_ARCHIVE
# -----------------------------------------------------------
# Folder to collect releases that already exist in archive
ALREADY_ARCHIVE_DIR="$UNSORTED_BASE/already_in_archive"

# -----------------------------------------------------------
# ALPHABET SUBFOLDER STYLE
# -----------------------------------------------------------
# "_A" = scene-style folders with underscore (default)
# "A"  = plain letter folders without underscore
# VA releases and digits follow this style too
ALPHABET_SUBFOLDER_STYLE="A"

# -----------------------------------------------------------
# COUNTERS
# -----------------------------------------------------------
MOVED_COUNT=0           # Counts releases successfully moved to archive
ALREADY_COUNT=0         # Counts releases moved to already_in_archive
TOTAL_MOVED_SIZE=0      # Total size of moved releases in bytes

########################
# LOCKFILE SETUP
########################
LOCKFILE="$GLROOT/tmp/movetoarchive.lock"
if [ -e "$LOCKFILE" ]; then
    echo "Another instance is running. Exiting."
    [ "$SANDBOX" = false ] && echo "$(date "+%a %b %e %T %Y") ARCHDIRLOG: Another instance detected. Exiting." >> "$gllog"
    exit 1
fi
touch "$LOCKFILE"
trap 'rm -f "$LOCKFILE"' EXIT

########################
# FUNCTIONS
########################

# Check if path is excluded
is_excluded() {
  local path="$1"
  for ex in "${EXCLUDE_PATHS[@]}"; do
    [[ "$path" == "$ex"* ]] && return 0
  done
  return 1
}

# Determine alphabet directory for a release
get_alpha_dir() {
  local name="$1"

  # Check for Various Artists (VA)
  if [[ "$name" =~ ^(VA[-_]|VA--|VA_-_|V\.A\.|V\.A-) ]]; then
      if [[ "$ALPHABET_SUBFOLDER_STYLE" == "_"* ]]; then
          echo "_VA"
      else
          echo "VA"
      fi
      return
  fi

  local first_char="${name:0:1}"
  local alpha

  if [[ "$first_char" =~ [0-9] ]]; then
      alpha="0-9"
      [[ "$ALPHABET_SUBFOLDER_STYLE" == "_"* ]] && alpha="_0-9"
  elif [[ "$first_char" =~ [A-Za-z] ]]; then
      alpha="${first_char^^}"
      [[ "$ALPHABET_SUBFOLDER_STYLE" == "_"* ]] && alpha="_$alpha"
  else
      alpha="0-9"
      [[ "$ALPHABET_SUBFOLDER_STYLE" == "_"* ]] && alpha="_0-9"
  fi

  echo "$alpha"
}

# Move a single release
move_release() {
  local src="$1"
  local section="$2"
  local dirname
  dirname="$(basename "$src")"

  local target_base="${SECTION_MAP[$section]}"
  local alpha_dir
  alpha_dir="$(get_alpha_dir "$dirname")"
  local dest="$target_base/$alpha_dir/$dirname"

  # Calculate size for tracking
  dir_size=$(du -sb "$src" | cut -f1)

  # Skip if destination already exists
  if [ -d "$dest" ]; then
      echo "[SKIP] Destination already exists: $dest"

      # Ensure already_in_archive folder exists
      mkdir -p "$ALREADY_ARCHIVE_DIR"
      chmod 777 "$ALREADY_ARCHIVE_DIR"
      local archive_dest="$ALREADY_ARCHIVE_DIR/$dirname"

      TOTAL_MOVED_SIZE=$((TOTAL_MOVED_SIZE + dir_size))
      ALREADY_COUNT=$((ALREADY_COUNT + 1))

      if [ "$SANDBOX" = true ]; then
          touch "$SANDBOX_LOG"
          chmod 666 "$SANDBOX_LOG"
          echo "[SANDBOX] ARCHDIRLOG: Skipping $dirname (already exists)" | tee -a "$SANDBOX_LOG"
          echo "[SANDBOX] ARCHDIRLOG: Would move $dirname to already_in_archive: $archive_dest" | tee -a "$SANDBOX_LOG"
          echo "[SANDBOX] ARCHDIRLOG: Size: $((dir_size / 1024 / 1024)) MB" | tee -a "$SANDBOX_LOG"
      else
          echo "$(date "+%a %b %e %T %Y") ARCHDIRLOG: \"$section\" \"$dirname\" already exists, moved to already_in_archive" >> "$gllog"
          mv "$src" "$archive_dest"
      fi
      return
  fi

  # Normal move
  if [ "$SANDBOX" = true ]; then
      touch "$SANDBOX_LOG"
      chmod 666 "$SANDBOX_LOG"
      echo "[SANDBOX] ARCHDIRLOG: mkdir -p \"$target_base/$alpha_dir\" && chmod 777 \"$target_base/$alpha_dir\"" | tee -a "$SANDBOX_LOG"
      echo "[SANDBOX] ARCHDIRLOG: mv \"$src\" \"$dest\"" | tee -a "$SANDBOX_LOG"
      echo "[SANDBOX] ARCHDIRLOG: Size: $((dir_size / 1024 / 1024)) MB" | tee -a "$SANDBOX_LOG"
  else
      mkdir -p "$target_base/$alpha_dir"
      chmod 777 "$target_base/$alpha_dir"
      echo "$(date "+%a %b %e %T %Y") ARCHDIRLOG: \"$section\" \"$dirname\" moved to archive" >> "$gllog"
      mv "$src" "$dest"
  fi

  TOTAL_MOVED_SIZE=$((TOTAL_MOVED_SIZE + dir_size))
  ((MOVED_COUNT++))
}

########################
# MAIN LOOP
########################

for section in "${!SECTION_MAP[@]}"; do
  SRC_DIR="$UNSORTED_BASE/$section"
  DEST_BASE="${SECTION_MAP[$section]}"

  echo "DEBUG: Checking section '$section'"
  echo "DEBUG: Source directory '$SRC_DIR'"

  [ ! -d "$SRC_DIR" ] && { echo "DEBUG: $SRC_DIR does not exist"; continue; }
  [ ! -d "$DEST_BASE" ] && { echo "DEBUG: Destination $DEST_BASE does not exist"; continue; }
  is_excluded "$SRC_DIR" && { echo "DEBUG: $SRC_DIR is excluded"; continue; }

  subdirs=$(find "$SRC_DIR" -mindepth 1 -maxdepth 1 -type d)
  echo "DEBUG: Found subdirectories:"
  echo "$subdirs"

  while read -r dir; do
    [ -z "$dir" ] && continue
    is_excluded "$dir" && { echo "DEBUG: $dir is excluded"; continue; }
    move_release "$dir" "$section"
  done <<< "$subdirs"
done

########################
# FINISH
########################

if [ "$SANDBOX" = true ]; then
    echo "[SANDBOX] ARCHDIRLOG: Total simulated moves: $MOVED_COUNT" | tee -a "$SANDBOX_LOG"
    echo "[SANDBOX] ARCHDIRLOG: Total releases moved to already_in_archive: $ALREADY_COUNT" | tee -a "$SANDBOX_LOG"
    echo "[SANDBOX] ARCHDIRLOG: Total size of moved releases: $((TOTAL_MOVED_SIZE / 1024 / 1024)) MB" | tee -a "$SANDBOX_LOG"
else
    echo "$(date "+%a %b %e %T %Y") ARCHDIRLOG: Total moved: $MOVED_COUNT" >> "$gllog"
    echo "$(date "+%a %b %e %T %Y") ARCHDIRLOG: Total already_in_archive: $ALREADY_COUNT" >> "$gllog"
    echo "$(date "+%a %b %e %T %Y") ARCHDIRLOG: Total Size: $((TOTAL_MOVED_SIZE / 1024 / 1024)) MB" >> "$gllog"
fi

echo "Done. Total moved (or simulated in sandbox): $MOVED_COUNT"
echo "Total moved to already_in_archive: $ALREADY_COUNT"
echo "Total size of moved releases: $((TOTAL_MOVED_SIZE / 1024 / 1024)) MB"

exit 0
#eof
