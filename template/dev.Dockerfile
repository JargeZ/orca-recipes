# Project dev image: toolchain + system deps only. The Orca recipe layers its infra (sshd, the `dev`
# user with uid 1000, Node, gh, task, Claude Code) on top, then clones the repo and runs the sync
# command as `dev`. Requirements:
#   - Debian/Ubuntu base (the infra layer uses apt; Node 18+ from the distro).
#   - Anything the sync command writes outside the checkout must be owned by uid 1000.
#   - ENV set here reaches Orca's SSH sessions too.
FROM python:3.13-slim-bookworm

# One shared venv at /opt/venv: Orca checks out linked worktrees at other paths,
# and `uv run` in any of them must reuse the deps baked into the image.
RUN pip install --no-cache-dir uv && mkdir -p /opt/venv && chown 1000:1000 /opt/venv
ENV VIRTUAL_ENV=/opt/venv \
    UV_PROJECT_ENVIRONMENT=/opt/venv \
    PATH=/opt/venv/bin:$PATH
