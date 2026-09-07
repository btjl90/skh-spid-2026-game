# syntax=docker/dockerfile:1.7
# loom dev-container distribution source (py) — generated INTO consumer templates by /sync-to-use; do not hand-edit the consumer copy. Registry host/org are ecosystem-relative, substituted at /sync-to-use distribution.
# Kailash COC multi-CLI development environment.
# Template-owned, regenerated on /sync — do not hand-edit downstream.
# Implements workspaces/dev-container/specs/dev-container-image.md (S1, I1–I8).
#
# Pins (H1 — resolved 2026-05-27): base/node/uv by @sha256 digest; CLIs + gh + yq +
# frameworks by exact version. Build-for-host arch (M4): arm64 OR amd64 per the
# building host — arch is part of the reproducibility envelope, not cross-arch.

# ---- node stage (scoped copy source — NOT a blanket /usr/local copy, N-L) ----
FROM node:22-bookworm-slim@sha256:7af03b14a13c8cdd38e45058fd957bf00a72bbe17feac43b1c15a689c029c732 AS node

# ---- uv stage (pinned installer source) ----
FROM ghcr.io/astral-sh/uv:0.11.16@sha256:440fd6477af86a2f1b38080c539f1672cd22acb1b1a47e321dba5158ab08864d AS uvbin

# ---- final ----
FROM python:3.12-slim-bookworm@sha256:93ab4b7fa528b25124c97bcc755415e60eb671a86b4dbe0328df2fe2d1c1193d

ARG USER_UID=1000
ARG USER_GID=1000
ARG GH_VERSION=2.92.0
ARG YQ_VERSION=4.53.2
# Per-arch sha256 of the release artifacts (H1 supply-chain pin; resolved 2026-05-27).
# gh from cli/cli checksums.txt; yq computed from the published binaries.
ARG GH_SHA256_amd64=8f8212b1a9cec261a8839e0893168f50d3fc70f095da257feef4229234cefdf8
ARG GH_SHA256_arm64=34d620b7c884774ed86236541535170889fda0b99aafbdab8b69c7d458b5ca6b
ARG YQ_SHA256_amd64=d56bf5c6819e8e696340c312bd70f849dc1678a7cda9c2ad63eebd906371d56b
ARG YQ_SHA256_arm64=03061b2a50c7a498de2bbb92d7cb078ce433011f085a4994117c2726be4106ea

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    VIRTUAL_ENV=/opt/venv \
    PATH=/opt/venv/bin:/usr/local/bin:$PATH

# 1. OS tooling (one layer). tini/jq/ripgrep/gnupg/openssh-client all in bookworm apt.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      git gnupg openssh-client curl ca-certificates build-essential jq ripgrep tini \
 && rm -rf /var/lib/apt/lists/*

# 2. gh (pinned .deb) + yq (pinned binary) — arch-correct via dpkg, sha256-verified
#    BEFORE install/exec (H1 supply-chain: TLS authenticates transport, not the artifact).
RUN arch="$(dpkg --print-architecture)" \
 && case "$arch" in \
      amd64) gh_sha="${GH_SHA256_amd64}"; yq_sha="${YQ_SHA256_amd64}" ;; \
      arm64) gh_sha="${GH_SHA256_arm64}"; yq_sha="${YQ_SHA256_arm64}" ;; \
      *) echo "unsupported arch: $arch" >&2; exit 1 ;; \
    esac \
 && curl -fsSL -o /tmp/gh.deb \
      "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${arch}.deb" \
 && echo "${gh_sha}  /tmp/gh.deb" | sha256sum -c - \
 && dpkg -i /tmp/gh.deb && rm /tmp/gh.deb \
 && curl -fsSL -o /usr/local/bin/yq \
      "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_${arch}" \
 && echo "${yq_sha}  /usr/local/bin/yq" | sha256sum -c - \
 && chmod 0755 /usr/local/bin/yq

# 3. Node 22 — SCOPED copy (N-L: do NOT clobber the base python at /usr/local/bin).
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
 && ln -s /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
 && node --version && npm --version \
 && python --version   # N-L: base python MUST survive the node copy

# 4. uv (pinned) from its image — binaries live at the ROOT of the distroless uv image.
COPY --from=uvbin /uv /uvx /usr/local/bin/

# 5. Shared venv + baked frameworks (H2: ONE venv, no --system; base + overlay share it).
# UV_LINK_MODE=copy: the BuildKit cache mount and the venv layer are on different
# filesystems, so uv cannot hardlink across them — copy is the canonical, warning-free
# mode for cache-mounted uv installs in Docker (zero-tolerance: no build-log warnings).
ENV UV_LINK_MODE=copy
RUN uv venv /opt/venv
COPY requirements-coc.txt /tmp/requirements-coc.txt
RUN --mount=type=cache,target=/root/.cache/uv \
    uv pip install -r /tmp/requirements-coc.txt

# 6. The three CLIs (pinned), installed as root → global bins.
RUN npm install -g --no-fund --no-audit \
      @anthropic-ai/claude-code@2.1.152 \
      @openai/codex@0.134.0 \
      @google/gemini-cli@0.43.0

# 7. Non-root dev user; own the venv so the postCreate overlay install can write it
#    (N-M1: chown BEFORE USER dev). git safe.directory (M3). NO sudo grant (H3).
RUN groupadd --gid "${USER_GID}" dev \
 && useradd --uid "${USER_UID}" --gid "${USER_GID}" -m -s /bin/bash dev \
 && chown -R dev:dev /opt/venv \
 && git config --system --add safe.directory /workspace
USER dev
WORKDIR /workspace

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["bash"]
