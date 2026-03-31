#!/usr/bin/env bash
set -euo pipefail

cd /opt/fastapi-llm-chatbot/fastapi-app
source .venv/bin/activate
exec uvicorn main:app --host 0.0.0.0 --port 8000
