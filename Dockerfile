FROM python:3.11-slim

RUN apt-get update && apt-get install -y git curl && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt /app/
RUN pip install -r requirements.txt
RUN pip install -U google-generativeai

COPY . /app

# Install a real gemini CLI wrapper that calls our Python CLI
RUN printf '#!/usr/bin/env bash\nexec python3 /app/gemini_cli.py "$@"\n' > /usr/local/bin/gemini \
  && chmod +x /usr/local/bin/gemini

CMD ["bash", "summarize_git_activity_gemini.sh"]
