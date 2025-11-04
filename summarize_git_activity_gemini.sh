#!/bin/bash
set -euo pipefail

log_debug() {
  if [ -n "${SUMMARY_DEBUG:-}" ]; then
    printf "%s\n" "$*" >&2
  fi
}

# --- Load environment ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE_PATH="${ENV_FILE:-"$SCRIPT_DIR/.env"}"
if [ -f "$ENV_FILE_PATH" ]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE_PATH"
fi

# --- Run git summary script (suppress script debug) ---
RAW_SUMMARY="$(DEBUG= bash "$SCRIPT_DIR/git_summary_script.sh" 2>/dev/null)"

# --- Basic config ---
PROVIDER="${AI_PROVIDER:-none}"
MODEL="${AI_MODEL:-}"
OUTPUT_DIR="$SCRIPT_DIR/summaries"
mkdir -p "$OUTPUT_DIR"

DATE_TAG=$(date +"%Y-%m-%d_%H-%M-%S")
DEFAULT_OUTPUT_FILE="$OUTPUT_DIR/summary-$DATE_TAG.md"
OUTPUT_FILE_PATH="${OUTPUT_FILE:-$DEFAULT_OUTPUT_FILE}"

# --- Handle empty summary ---
if [ -z "$RAW_SUMMARY" ] || [ "$RAW_SUMMARY" = "No activity found today." ]; then
  printf "%s\n" "No activity found today." > "$OUTPUT_FILE_PATH"
  echo "$OUTPUT_FILE_PATH"
  exit 0
fi

# --- Summarize ---
if [ "$PROVIDER" = "none" ] || [ "$PROVIDER" = "off" ]; then
  printf "%s" "$RAW_SUMMARY" > "$OUTPUT_FILE_PATH"
  echo "$OUTPUT_FILE_PATH"
  exit 0
fi

# Prefer Gemini CLI if available and API key is set
if command -v gemini >/dev/null 2>&1 && [ -n "${GEMINI_API_KEY:-}" ]; then
  log_debug "Summarizing with Gemini via CLI"
  MODEL_TO_USE="${AI_MODEL:-gemini-1.5-flash-8b}"
  if GEMINI_API_KEY="$GEMINI_API_KEY" \
     gemini text --model "$MODEL_TO_USE" --input - \
     < <(printf "%s" "$RAW_SUMMARY") | tee "$OUTPUT_FILE_PATH" >/dev/null; then
    echo "$OUTPUT_FILE_PATH"
    exit 0
  else
    log_debug "Gemini CLI failed. Falling back to raw summary."
    printf "%s" "$RAW_SUMMARY" > "$OUTPUT_FILE_PATH"
    echo "$OUTPUT_FILE_PATH"
    exit 0
  fi
fi

if [ "$PROVIDER" = "gemini" ]; then
  log_debug "Summarizing with Gemini via Python SDK"
  if printf "%s" "$RAW_SUMMARY" | python3 "$SCRIPT_DIR/summarize_ai.py" \
      --provider gemini \
      --model gemini-1.5-flash-latest \
      | tee "$OUTPUT_FILE_PATH" >/dev/null; then
    echo "$OUTPUT_FILE_PATH"
    exit 0
  else
    log_debug "Gemini SDK failed. Falling back to raw summary."
    printf "%s" "$RAW_SUMMARY" > "$OUTPUT_FILE_PATH"
    echo "$OUTPUT_FILE_PATH"
    exit 0
  fi
fi

# --- Use CLI if defined ---
if [ -n "${CLI_CMD:-}" ]; then
  # Generic CLI hook: pipe RAW_SUMMARY to CLI_CMD; write output
  log_debug "Summarizing via CLI_CMD=$CLI_CMD"
  printf "%s" "$RAW_SUMMARY" | eval "$CLI_CMD" | tee "$OUTPUT_FILE_PATH" >/dev/null
else
  # --- Fallback: Python SDK ---
  log_debug "Summarizing with provider=$PROVIDER model=$MODEL"
  if ! printf "%s" "$RAW_SUMMARY" | python3 "$SCRIPT_DIR/summarize_ai.py" \
    --provider "$PROVIDER" \
    --model "$MODEL" | tee "$OUTPUT_FILE_PATH" >/dev/null; then
    log_debug "AI summarization failed. Using raw summary."
    printf "%s" "$RAW_SUMMARY" > "$OUTPUT_FILE_PATH"
  fi
fi

echo "$OUTPUT_FILE_PATH"
exit 0
