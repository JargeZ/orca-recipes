# check=skip=InvalidDefaultArgInFrom
# Orca infra layered on top of the project's dev image (built from the project's dev.Dockerfile):
# sshd + the `dev` user Orca logs in as, Node for Orca's SSH relay, git/gh, task, Claude Code, Cursor Agent, OpenCode.
# Last, the repo checkout (the `repo` build context from docker-base-image.sh) and its deps.
ARG DEV_IMAGE
FROM ${DEV_IMAGE}
ARG GIT_HOST

USER root
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]
RUN test -f /etc/debian_version || { echo "dev image must be Debian/Ubuntu-based (apt)" >&2; exit 1; }

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        openssh-server sudo git curl ca-certificates \
        # Orca's SSH relay needs Node 18+ with npm; it builds node-pty from source.
        nodejs npm make g++ \
    # Current gh from the upstream repo (distro packages lag years behind).
    && curl -fsSL --create-dirs -o /etc/apt/keyrings/githubcli-archive-keyring.gpg https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    # glab for GitLab repos, from upstream releases (distro packages lag or are missing).
    && if [ "$GIT_HOST" != github.com ]; then \
        v="$(curl -fsSL https://gitlab.com/api/v4/projects/gitlab-org%2Fcli/releases/permalink/latest | sed -E 's/.*"tag_name":"v([^"]+)".*/\1/')" \
        && curl -fsSL -o /tmp/glab.deb "https://gitlab.com/gitlab-org/cli/-/releases/v$v/downloads/glab_${v}_linux_$(dpkg --print-architecture).deb" \
        && apt-get install -y --no-install-recommends /tmp/glab.deb && rm /tmp/glab.deb; \
    fi \
    && rm -rf /var/lib/apt/lists/* \
    && sh -c "$(curl --location https://taskfile.dev/install.sh)" -- -d -b /usr/local/bin \
    # uid 1000 is taken in some bases (ubuntu:24.04 ships `ubuntu`); dev.Dockerfiles chown to 1000.
    && if old="$(getent passwd 1000 | cut -d: -f1)" && [ -n "$old" ]; then userdel -r "$old" 2>/dev/null || userdel "$old"; fi \
    && useradd -m -u 1000 -s /bin/bash dev \
    && echo 'dev ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/dev \
    && mkdir -p /run/sshd && rm -f /etc/ssh/ssh_host_* \
    && printf 'PasswordAuthentication no\nPermitRootLogin no\n' > /etc/ssh/sshd_config.d/orca.conf

# git over HTTPS to the repo's host answers from the token env var set per container.
COPY git-credential-orca /usr/local/bin/git-credential-orca
RUN git config --system "credential.https://${GIT_HOST}.helper" /usr/local/bin/git-credential-orca

USER dev
RUN curl -fsSL https://claude.ai/install.sh | bash \
    # The shared login volume is mounted here (docker-create.sh); a new volume starts as a copy of this
    # dir, so the first-run wizard stays skipped.
    && mkdir -p /home/dev/.claude && echo '{"hasCompletedOnboarding": true}' > /home/dev/.claude/.claude.json \
    # Cursor Agent CLI; login volume mounts at CURSOR_CONFIG_DIR (AGENT_CLI_CREDENTIAL_STORE=file).
    && curl -fsSL https://cursor.com/install | bash \
    && mkdir -p /home/dev/.config/cursor \
    # OpenCode v2 (installs to ~/.opencode/bin); login volume mounts at its data dir (SQLite db).
    && curl -fsSL https://opencode.ai/v2/install | bash \
    && mkdir -p /home/dev/.local/share/opencode
USER root

ENV PATH=/home/dev/.local/bin:/home/dev/.opencode/bin:$PATH \
    CLAUDE_CONFIG_DIR=/home/dev/.claude \
    CURSOR_CONFIG_DIR=/home/dev/.config/cursor \
    # Default keychain store is unavailable in containers; file store writes auth.json under CURSOR_CONFIG_DIR.
    AGENT_CLI_CREDENTIAL_STORE=file \
    # Debian's node-gyp imports the distro `gyp` module, absent from non-distro python3s.
    npm_config_python=/usr/bin/python3
# SSH sessions don't inherit image ENV (including the dev image's): pam_env reads /etc/environment,
# and login shells read profile.d after /etc/profile resets PATH.
RUN env | grep -vE '^(HOSTNAME|HOME|PWD|SHLVL|TERM|USER|GIT_HOST|_)=' | sort > /etc/environment \
    && while IFS= read -r kv; do printf 'export %q\n' "$kv"; done < /etc/environment > /etc/profile.d/orca-env.sh

COPY docker-entrypoint.sh /usr/local/bin/orca-docker-ssh-entrypoint
ENTRYPOINT ["/usr/local/bin/orca-docker-ssh-entrypoint"]
CMD []

# Declared here, not at the top: changing them must not rebuild the infra layers above.
ARG REPO_URL PROJECT_ROOT SYNC_COMMAND
COPY --from=repo --chown=dev:dev . ${PROJECT_ROOT}
USER dev
WORKDIR ${PROJECT_ROOT}
RUN git remote set-url origin "$REPO_URL" && bash -lc "$SYNC_COMMAND"
USER root
