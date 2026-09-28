# orca-recipes' own dev image: what `task test` needs besides Docker (uv for copier + shellcheck,
# jq, rsync). The Orca recipe layers its infra on top; see template/dev.Dockerfile for the rules.
FROM python:3.13-slim-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends jq rsync \
    && rm -rf /var/lib/apt/lists/* \
    && pip install --no-cache-dir uv
# Use the image's Python for uvx tools instead of downloading one.
ENV UV_PYTHON_DOWNLOADS=never
