#!/usr/bin/env python3
"""
summarize_ai.py
Summarize git activity text using OpenAI or Gemini via their Python SDKs.
"""

import os
import sys
import argparse
from dotenv import load_dotenv


def read_stdin() -> str:
    return sys.stdin.read()


def get_summary_prompt(text: str) -> str:
    """Get the prompt for summarization, checking SUMMARY_PROMPT_FILE or SUMMARY_PROMPT env vars."""
    # First, check if a prompt file is specified (allows multi-line prompts easily)
    prompt_file = os.getenv("SUMMARY_PROMPT_FILE", "").strip()
    if prompt_file:
        script_dir = os.path.dirname(os.path.abspath(__file__))
        # Support both absolute and relative paths
        if not os.path.isabs(prompt_file):
            prompt_file = os.path.join(script_dir, prompt_file)
        if os.path.exists(prompt_file):
            try:
                with open(prompt_file, "r", encoding="utf-8") as f:
                    custom_prompt = f.read().strip()
                if custom_prompt:
                    return f"{custom_prompt}\n\n{text}"
            except Exception as e:
                print(f"Warning: Could not read SUMMARY_PROMPT_FILE '{prompt_file}': {e}", file=sys.stderr)
    
    # Check for SUMMARY_PROMPT env var (supports quoted multi-line values via python-dotenv)
    custom_prompt = os.getenv("SUMMARY_PROMPT", "").strip()
    if custom_prompt:
        # If custom prompt is provided, append the git activity text
        return f"{custom_prompt}\n\n{text}"
    
    # Default prompt
    default_prompt = (
        "Summarize the following git activity for a concise daily report. "
        "Group by repository, highlight meaningful changes, and skip noise.\n\n"
    )
    return default_prompt + text


def summarize_with_openai(text: str, model: str) -> str:
    try:
        from openai import OpenAI
    except ImportError as e:
        raise RuntimeError("OpenAI SDK not installed. Add it to requirements.txt") from e

    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        raise RuntimeError("OPENAI_API_KEY is required for provider=openai")

    client = OpenAI(api_key=api_key)
    prompt = get_summary_prompt(text)
    
    # For OpenAI, we can use system message if SUMMARY_PROMPT is not set
    system_message = "You are an expert at concise software progress summaries."
    user_message = prompt
    
    # If custom prompt is used, it might contain system instructions, so use it as user message
    # Otherwise, split into system and user messages
    if os.getenv("SUMMARY_PROMPT", "").strip():
        # Custom prompt: use as single user message
        messages = [{"role": "user", "content": user_message}]
    else:
        # Default: use system + user messages
        messages = [
            {"role": "system", "content": system_message},
            {"role": "user", "content": user_message},
        ]
    
    completion = client.chat.completions.create(
        model=model,
        messages=messages,
        temperature=0.2,
    )
    return completion.choices[0].message.content.strip()


def summarize_with_gemini(text: str, model: str) -> str:
    try:
        import google.generativeai as genai
    except ImportError as e:
        raise RuntimeError("google-generativeai not installed. Add it to requirements.txt") from e

    api_key = os.getenv("GEMINI_API_KEY") or os.getenv("GOOGLE_API_KEY")
    if not api_key:
        raise RuntimeError("GEMINI_API_KEY (or GOOGLE_API_KEY) is required for provider=gemini")

    genai.configure(api_key=api_key)
    model_name = model or "gemini-1.5-flash"

    prompt = get_summary_prompt(text)
    # Use model name as-is for the current SDK (v1beta expects plain IDs like "gemini-1.5-flash-latest")
    model_obj = genai.GenerativeModel(model_name)

    response = model_obj.generate_content(prompt)

    if not response or not getattr(response, "text", None):
        raise RuntimeError("Gemini returned empty response")

    return response.text.strip()


def main() -> int:
    # Load .env if available
    script_dir = os.path.dirname(os.path.abspath(__file__))
    env_file = os.getenv("ENV_FILE", os.path.join(script_dir, ".env"))
    if os.path.exists(env_file):
        load_dotenv(env_file)

    parser = argparse.ArgumentParser(description="Summarize git activity with AI (OpenAI or Gemini)")
    parser.add_argument("--provider", default=os.getenv("AI_PROVIDER", "gemini"), help="AI provider: openai|gemini|none")
    parser.add_argument("--model", default=os.getenv("AI_MODEL", ""), help="Model name for the chosen provider")
    args = parser.parse_args()

    text = read_stdin()
    provider = (args.provider or "").lower()
    model = args.model

    if provider in ("none", "off", "disabled"):
        print(text)
        return 0

    if provider == "openai":
        model = model or "gpt-4o-mini"
        print(summarize_with_openai(text, model))
        return 0

    if provider == "gemini":
        model = model or "gemini-1.5-flash-latest"
        print(summarize_with_gemini(text, model))
        return 0

    raise SystemExit(f"Unknown provider: {provider}. Use openai|gemini|none")


if __name__ == "__main__":
    raise SystemExit(main())
