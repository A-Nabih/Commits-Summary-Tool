#!/bin/bash

# Resolve script directory and load environment variables if present
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE_PATH="${ENV_FILE:-"$SCRIPT_DIR/.env"}"
if [ -f "$ENV_FILE_PATH" ]; then
  # Load .env but do not override variables already set in the environment
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|\#*) continue ;;
      *)
        if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
          key="${BASH_REMATCH[1]}"
          val="${BASH_REMATCH[2]}"
          if [ -z "${!key}" ]; then
            eval "export $key=$val"
          fi
        fi
      ;;
    esac
  done < "$ENV_FILE_PATH"
fi

# Optional timezone to align with your locale (affects "midnight" and git since parsing)
if [ -n "$TIMEZONE" ]; then
  export TZ="$TIMEZONE"
fi

# Disable interactive git credential prompts in non-interactive environments
export GIT_TERMINAL_PROMPT=0

# Config from .env (with sensible defaults)
# REPO_DIRS: optional comma-separated list of absolute repo paths
# REPOS_ROOTS: optional comma-separated root directories to auto-discover git repos
# REPO_URLS: optional comma-separated list of git URLs to clone into a temp folder
# PROJECT_NAME: optional filter by repo basename (case-insensitive contains)
# DAYS: number of days to include (1 = today only)
# TIME_WINDOW_MODE: midnight | rolling (rolling = last N*24h)
# AUTHOR_FILTER: optional author filter (e.g., email or name) for git log
REPO_DIRS_ENV="${REPO_DIRS:-}" 
REPOS_ROOTS_ENV="${REPOS_ROOTS:-}"
REPO_URLS_ENV="${REPO_URLS:-}"
PROJECT_NAME_FILTER="${PROJECT_NAME:-}"
DAYS_WINDOW="${DAYS:-1}"
TIME_WINDOW_MODE="${TIME_WINDOW_MODE:-rolling}"
AUTHOR_FILTER="${AUTHOR_FILTER:-}"

# Build repo list: prefer env REPO_DIRS, else fallback to hardcoded defaults
# --- robust repo discovery (replace prior REPOS discovery block) ---
REPOS=()
# If REPO_DIRS was explicitly provided use it
if [ -n "$REPO_DIRS_ENV" ]; then
  IFS=',' read -r -a REPOS <<< "$REPO_DIRS_ENV"
else
  # Prefer explicit REPOS_ROOTS_ENV. If not set try /workspace (container mount)
  if [ -z "$REPOS_ROOTS_ENV" ] && [ -d "/workspace" ]; then
    REPOS_ROOTS_ENV="/workspace"
  fi

  if [ -n "$REPOS_ROOTS_ENV" ]; then
    IFS=',' read -r -a ROOTS <<< "$REPOS_ROOTS_ENV"
    for ROOT in "${ROOTS[@]}"; do
      [ -d "$ROOT" ] || { [ -n "$DEBUG_MODE" ] && echo "[debug] root not found: $ROOT" >&2; continue; }
      # look for .git up to 6 levels deep to be more permissive in container layouts
      while IFS= read -r -d '' GITDIR; do
        REPOS+=("$(dirname "$GITDIR")")
      done < <(find "$ROOT" -maxdepth 6 -type d -name .git -print0 2>/dev/null)
    done
  fi

  # fallback hard-coded defaults (useful if nothing else provided)
  if [ ${#REPOS[@]} -eq 0 ]; then
    REPOS=(
      "$HOME/TJM Labs/pioneer-bot-template/pioneer-bot-template"
      "$HOME/TJM Labs/deliverit-bot/deliverit-bot"
      "$HOME/TJM Labs/mooresrx-bot/Moores-rx-bot"
      "$HOME/TJM Labs/tjm-package"
    )
  fi
fi

# Show discovered roots when debugging
if [ -n "$DEBUG_MODE" ]; then
  echo "[debug] REPOS_ROOTS_ENV='$REPOS_ROOTS_ENV'  REPO_DIRS_ENV='$REPO_DIRS_ENV'  HOST_REPOS_ROOT='$HOST_REPOS_ROOT'" >&2
  echo "[debug] Discovered ${#REPOS[@]} repo(s):" >&2
  for r in "${REPOS[@]}"; do echo " - $r" >&2; done
fi
# Compute git --since window
if [ -z "$DAYS_WINDOW" ] || ! [[ "$DAYS_WINDOW" =~ ^[0-9]+$ ]] || [ "$DAYS_WINDOW" -lt 1 ]; then
  DAYS_WINDOW=1
fi
if [ "$TIME_WINDOW_MODE" = "rolling" ]; then
  HOURS=$((DAYS_WINDOW * 24))
  SINCE_ARG="$HOURS hours ago"
else
  if [ "$DAYS_WINDOW" -le 1 ]; then
    SINCE_ARG="midnight"
  else
    DAYS_BEFORE=$((DAYS_WINDOW - 1))
    SINCE_ARG="$DAYS_BEFORE days ago 00:00"
  fi
fi

TODAY=$(date +"%Y-%m-%d")
SUMMARY=""
DEBUG_MODE="${DEBUG:-}" 

# If REPO_URLS were provided, clone/update them into a temp workspace and append to REPOS
if [ -n "$REPO_URLS_ENV" ]; then
  IFS=',' read -r -a URLS <<< "$REPO_URLS_ENV"
  TMP_BASE="${TMPDIR:-/tmp}/git-summary-${USER:-runner}"
  mkdir -p "$TMP_BASE"
  for URL in "${URLS[@]}"; do
    [ -n "$URL" ] || continue
    BASENAME=$(basename "$URL")
    BASENAME="${BASENAME%.git}"
    TARGET_DIR="$TMP_BASE/$BASENAME"
    if [ -n "$DEBUG_MODE" ]; then
      echo "[debug] REPO_URLS: $URL -> $TARGET_DIR" >&2
    fi
    if [ -d "$TARGET_DIR/.git" ]; then
      git -C "$TARGET_DIR" fetch --all --prune >/dev/null 2>&1 || { [ -n "$DEBUG_MODE" ] && echo "[debug] fetch failed: $TARGET_DIR" >&2; true; }
      git -C "$TARGET_DIR" pull --ff-only >/dev/null 2>&1 || { [ -n "$DEBUG_MODE" ] && echo "[debug] pull failed: $TARGET_DIR" >&2; true; }
    else
      git clone --depth 200 "$URL" "$TARGET_DIR" >/dev/null 2>&1 || { [ -n "$DEBUG_MODE" ] && echo "[debug] clone failed: $URL" >&2; true; }
    fi
    if [ -d "$TARGET_DIR/.git" ]; then
      REPOS+=("$TARGET_DIR")
      if [ -n "$DEBUG_MODE" ]; then
        echo "[debug] Added cloned repo: $TARGET_DIR" >&2
      fi
    fi
  done
fi

if [ -n "$DEBUG_MODE" ]; then
  echo "[debug] Since: $SINCE_ARG  | Timezone: ${TZ:-system}" >&2
  echo "[debug] Scanning repos (${#REPOS[@]}):" >&2
  for r in "${REPOS[@]}"; do echo " - $r" >&2; done
fi

for REPO_DIR in "${REPOS[@]}"; do
  [ -d "$REPO_DIR" ] || continue
  [ -d "$REPO_DIR/.git" ] || continue
  
  cd "$REPO_DIR" || continue
  
  NAME=$(basename "$REPO_DIR")
  if [ -n "$PROJECT_NAME_FILTER" ]; then
    shopt -s nocasematch
    if [[ ! "$NAME" =~ ${PROJECT_NAME_FILTER} ]]; then
      shopt -u nocasematch
      continue
    fi
    shopt -u nocasematch
  fi

    AUTHOR_ARG=()
    if [ -n "$AUTHOR_FILTER" ]; then
      AUTHOR_ARG=(--author="$AUTHOR_FILTER")
    fi
    [ -n "$DEBUG_MODE" ] && echo "[debug] Running git log in: $REPO_DIR" >&2
    COMMITS=$(git log --all --since="$SINCE_ARG" "${AUTHOR_ARG[@]}" --oneline 2>/dev/null)
    if [ -n "$DEBUG_MODE" ]; then
      COUNT=$(printf "%s\n" "$COMMITS" | sed '/^\s*$/d' | wc -l | tr -d ' ')
      echo "[debug] $NAME commits found: $COUNT  (author=${AUTHOR_FILTER:-ALL})" >&2
      echo "[debug] Sample git log (top 3):" >&2
      printf "%s\n" "$COMMITS" | sed -n '1,3p' >&2
      if [ "$COUNT" -eq 0 ]; then
        echo "[debug] No commits in window. Last commit overall:" >&2
        git log --all -1 --pretty=format:'%h %ad %s (%an)' --date=iso 2>/dev/null >&2 || true
        echo "[debug] Now: $(date +"%Y-%m-%dT%H:%M:%S%z") TZ=${TZ:-system}" >&2
      fi
    fi
    UNCOMMITTED=$(git status --porcelain | wc -l | tr -d ' ')
    if [ -n "$DEBUG_MODE" ]; then
      echo "[debug] $NAME uncommitted count: $UNCOMMITTED" >&2
      if [ "$UNCOMMITTED" -gt 0 ]; then
        echo "[debug] Sample git status (top 5):" >&2
        git status --porcelain | sed -n '1,5p' >&2
      fi
    fi

    if [ -n "$COMMITS" ] || [ "$UNCOMMITTED" -gt 0 ]; then
      SUMMARY+="📁 $NAME\n"

      # --- Commits in window ---
      if [ -n "$COMMITS" ]; then
        if [ "$DAYS_WINDOW" -le 1 ]; then
          SUMMARY+="✅ Commits today:\n$COMMITS\n"
        else
          SUMMARY+="✅ Commits in last $DAYS_WINDOW day(s):\n$COMMITS\n"
        fi
      else
        SUMMARY+="⚠️ No commits today.\n"
      fi

      # --- Uncommitted changes ---
      if [ "$UNCOMMITTED" -gt 0 ]; then
        SUMMARY+="📝 Uncommitted changes: $UNCOMMITTED file(s)\n"

        # Process each file individually to avoid subshell issues
        while IFS= read -r line; do
          if [ -n "$line" ]; then
            STATUS="${line:0:2}"
            FILE="${line:3}"
            SUMMARY+="   • $FILE ($STATUS)\n"

            # Get line numbers where changes happened
            if [[ "$STATUS" =~ [MAD] ]]; then  # Modified, Added, or Deleted files
              DIFF_OUTPUT=$(git diff --unified=0 HEAD -- "$FILE" 2>/dev/null | grep -E '^@@')
              if [ -n "$DIFF_OUTPUT" ]; then
                while IFS= read -r diff_line; do
                  if [[ "$diff_line" =~ @@\ -([0-9]+)(,([0-9]+))?\ \+([0-9]+)(,([0-9]+))?\ @@ ]]; then
                    OLD_START="${BASH_REMATCH[1]}"
                    OLD_COUNT="${BASH_REMATCH[3]:-1}"
                    NEW_START="${BASH_REMATCH[4]}"
                    NEW_COUNT="${BASH_REMATCH[6]:-1}"
                    
                    if [ "$NEW_COUNT" -eq 0 ]; then
                      SUMMARY+="      → deleted lines: $OLD_START-$((OLD_START + OLD_COUNT - 1))\n"
                    elif [ "$OLD_COUNT" -eq 0 ]; then
                      SUMMARY+="      → added lines: $NEW_START-$((NEW_START + NEW_COUNT - 1))\n"
                    else
                      SUMMARY+="      → modified lines: $NEW_START-$((NEW_START + NEW_COUNT - 1))\n"
                    fi
                  fi
                done <<< "$DIFF_OUTPUT"
              else
                # For new files or files with no diff info
                if [[ "$STATUS" =~ A ]]; then
                  LINE_COUNT=$(wc -l < "$FILE" 2>/dev/null || echo "0")
                  SUMMARY+="      → new file: 1-$LINE_COUNT lines\n"
                fi
              fi
            fi
          fi
        done <<< "$(git status --porcelain)"
      fi

      SUMMARY+="\n"
    fi
  done

if [ -z "$SUMMARY" ]; then
  SUMMARY="No activity found today."
fi

SUMMARY="ℹ️ Tracking the last $DAYS_WINDOW day(s) (window: $SINCE_ARG)\n\n$SUMMARY"

echo -e "$SUMMARY"

# Optional macOS notification if no commits (only if osascript is available)
if [[ "$SUMMARY" == *"No commits today."* ]]; then
  if command -v osascript >/dev/null 2>&1; then
    osascript -e 'display notification "You haven’t committed anything today!" with title "Git Reminder"' || true
  fi
fi