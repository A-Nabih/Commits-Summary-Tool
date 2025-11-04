## Git Activity Summary with AI

This project summarizes your git activity for today (or a configurable window) across one or more repositories, and can optionally produce an AI-written summary using OpenAI or Gemini.

### Setup

1) Create an environment file by copying the example:

```bash
cp env.example .env
```

Then edit `.env` to match your environment.

Key variables:
- **REPO_DIRS**: comma-separated absolute paths to repos. If empty, the script uses built-in defaults.
- **PROJECT_NAME**: optional filter (matches repo folder name, case-insensitive substring).
- **DAYS**: time window in days (1 = today only; 3 = today + previous 2 days).
- **TIME_WINDOW_MODE**: `rolling` (last N×24h) or `midnight` (calendar days). Default: rolling.
- **AI_PROVIDER**: `gemini`, `openai`, or `none`.
- You can also use `cli` to call any installed AI CLI. Configure `AI_CLI_CMD` (default: `gemini summarize`).
- **AI_MODEL**: optional; defaults to reasonable models per provider.
- **REPOS_ROOTS**: one or more folders to auto-discover repos (finds `.git` up to 3 levels deep).
- **REPO_URLS**: comma-separated git URLs; script clones/updates them into a temp folder and includes them.
- **AUTHOR_FILTER**: optional `git log --author` filter (e.g., your email) to only include your commits.
- **OUTPUT_FILE**: optional output path. Defaults to `summaries/summary-<timestamp>.md`.
- **OPENAI_API_KEY** or **GEMINI_API_KEY/GOOGLE_API_KEY**: if using AI.

### Run Locally (no Docker)

```bash
# Optionally create a Python venv
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

# Raw summary
bash ./git_summary_script.sh

# AI summarized (writes to file; prints path at the end)
bash ./summarize_git_activity_gemini.sh
```

### Run with Docker

```bash
docker-compose up --build

# The output file path will be printed, and also saved under ./summaries on your host
ls -la ./summaries
```

Notes:
- The compose file mounts `./` to `/app` so any summaries written under `/app/summaries` are visible in `./summaries` on your host.
- Prefer `REPOS_ROOTS` with Docker: mount a single host folder to `/workspace` and set `REPOS_ROOTS=/workspace`.
- You can also set these in `.env` and simply run `docker compose run --rm git-summary`.

### Script Details

- `git_summary_script.sh` reads `.env` if present and supports `REPO_DIRS`, `PROJECT_NAME`, and `DAYS`.
- `summarize_git_activity_gemini.sh` (generic) runs the summary and then calls `summarize_ai.py` using `AI_PROVIDER`/`AI_MODEL`.
- `summarize_ai.py` supports providers: `gemini` and `openai`. Set the appropriate API key env variables.


