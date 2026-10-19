# orca-recipes' own dev image: what `task test` needs besides Docker (uv for copier + shellcheck,
# jq, rsync). The Orca recipe layers its infra on top; see template/dev.Dockerfile for the rules.
FROM ubuntu:24.04

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/
RUN apt-get update && apt-get install -y --no-install-recommends jq rsync \
    && rm -rf /var/lib/apt/lists/*
