#!/usr/bin/env python3
import os
import sys
import argparse
import json
import requests


def ensure_api_key() -> str:
    key = os.getenv("GEMINI_API_KEY") or os.getenv("GOOGLE_API_KEY")
    if not key:
        print("GEMINI_API_KEY (or GOOGLE_API_KEY) is required", file=sys.stderr)
        sys.exit(2)
    return key


def cmd_text(args: argparse.Namespace) -> int:
    api_key = ensure_api_key()
    model_name = args.model or "gemini-1.5-flash"

    # read input text
    if args.input == "-":
        prompt_text = sys.stdin.read()
    else:
        prompt_text = args.input

    style = (os.getenv("PROMPT_STYLE") or os.getenv("SUMMARY_STYLE") or "classic").lower()

    if style == "classic":
        system_preface = (
            "You are an expert technical writer. Produce a clean Markdown report with this exact structure:\n"
            "# Git Activity Report\n\n"
            "For each repository present in the input, include a section in this format:\n"
            "## <RepositoryName>\n\n"
            "### Recent Commits (Last N Days):\n"
            "*   `<short_hash>` <commit_subject>\n"
            "(one bullet per commit, keep subjects as-is; do not add extra commentary)\n\n"
            "### Notable Uncommitted Changes:\n"
            "*   None reported.  (if there are no uncommitted changes)\n"
            "or list a few bullets summarizing real changes only.\n\n"
            "Do not add generic text, disclaimers, or introductions beyond the above headings."
        )
    else:
        system_preface = (
            "Summarize the following git activity into a concise, well-structured Markdown report. "
            "Group by repository, show key commits (bulleted), and note notable uncommitted changes. "
            "Keep it action-focused and avoid boilerplate."
        )

    full_prompt = f"{system_preface}\n\n{prompt_text}"

    def call_model_v1(m: str):
        url = f"https://generativelanguage.googleapis.com/v1/models/{m}:generateContent?key={api_key}"
        payload = {
            "contents": [
                {
                    "role": "user",
                    "parts": [{"text": full_prompt}],
                }
            ]
        }
        r = requests.post(url, json=payload, timeout=60)
        if r.status_code != 200:
            return None, f"HTTP {r.status_code}: {r.text[:200]}"
        data = r.json()
        try:
            parts = data["candidates"][0]["content"]["parts"]
            texts = [p.get("text", "") for p in parts]
            return "".join(texts).strip(), None
        except Exception as e:
            return None, f"Parse error: {e}"

    def call_model_v1beta(full_model_name: str):
        # full_model_name expected like 'models/gemini-1.5-flash'
        url = f"https://generativelanguage.googleapis.com/v1beta/{full_model_name}:generateContent?key={api_key}"
        payload = {
            "contents": [
                {
                    "role": "user",
                    "parts": [{"text": full_prompt}],
                }
            ]
        }
        r = requests.post(url, json=payload, timeout=60)
        if r.status_code != 200:
            return None, f"HTTP {r.status_code}: {r.text[:200]}"
        data = r.json()
        try:
            parts = data["candidates"][0]["content"]["parts"]
            texts = [p.get("text", "") for p in parts]
            return "".join(texts).strip(), None
        except Exception as e:
            return None, f"Parse error: {e}"

    # Try v1 direct call with provided model id
    text, err = call_model_v1(model_name)
    if text is None:
        # Try v1beta list models and pick a supported one
        list_url = f"https://generativelanguage.googleapis.com/v1beta/models?key={api_key}"
        lr = requests.get(list_url, timeout=30)
        if lr.status_code == 200:
            models = lr.json().get("models", [])
            preferred = None
            for m in models:
                name = m.get("name", "")  # e.g., 'models/gemini-1.5-flash'
                methods = m.get("supportedGenerationMethods", [])
                if "generateContent" in methods and ("gemini-1.5" in name or "flash" in name):
                    preferred = name
                    break
            if preferred:
                text, err2 = call_model_v1beta(preferred)
                if text is None:
                    print(f"Gemini REST call failed: {err} | {err2}", file=sys.stderr)
                    return 1
            else:
                print(f"Gemini REST call failed: {err} | no suitable model found", file=sys.stderr)
                return 1
        else:
            print(f"Gemini REST call failed: {err} | list models HTTP {lr.status_code}", file=sys.stderr)
            return 1

    sys.stdout.write(text)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(prog="gemini", description="Minimal Gemini CLI")
    sub = parser.add_subparsers(dest="command", required=True)

    p_text = sub.add_parser("text", help="Generate text from model")
    p_text.add_argument("--model", default=os.getenv("AI_MODEL", "gemini-1.5-flash"))
    p_text.add_argument("--input", default="-", help="'-' for stdin or literal text")
    p_text.set_defaults(func=cmd_text)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())