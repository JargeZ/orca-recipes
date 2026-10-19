# Project dev image: toolchain + system deps only. The Orca recipe layers its infra (sshd, the `dev`
# user with uid 1000, gh, task, Claude Code) on top, then clones the repo and runs the sync
# command as `dev`. Requirements:
#   - Debian/Ubuntu base (the infra layer uses apt).
#   - Anything the sync command writes outside the checkout must be owned by uid 1000.
#   - ENV set here reaches Orca's SSH sessions too.
FROM ubuntu:24.04

# uv also installs the Python that the project requires (into dev's home, at sync time).
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/
# One shared venv at /opt/venv: Orca checks out linked worktrees at other paths,
# and `uv run` in any of them must reuse the deps baked into the image.
RUN mkdir -p /opt/venv && chown 1000:1000 /opt/venv
ENV VIRTUAL_ENV=/opt/venv \
    UV_PROJECT_ENVIRONMENT=/opt/venv \
    PATH=/opt/venv/bin:$PATH
