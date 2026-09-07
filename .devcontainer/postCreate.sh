#!/usr/bin/env bash
# loom dev-container distribution source (py) — generated INTO consumer templates by /sync-to-use; do not hand-edit the consumer copy. Registry host/org are ecosystem-relative, substituted at /sync-to-use distribution.
# Kailash COC dev container — postCreate orchestrator (template-owned, regenerated on /sync).
#
# Idempotent + re-runnable on demand:  docker compose exec dev .devcontainer/postCreate.sh
# Each overlay step is presence-guarded, so a fresh project with empty/absent *-user.* files
# produces a clean run with no errors (O2). Running twice yields the same end state (O3).
# Overlay installs target the SAME shared /opt/venv the base image used for the frameworks
# (O1, $VIRTUAL_ENV is set in the image) — NO --system, no second target.
#
# Implements: specs/dependency-overlay.md (postCreate contract O1-O5) +
#             specs/secrets-and-auth.md (§Signing-key passthrough, C2/N-H2).
#
# Flags:
#   --ml   also install the opt-in ML/Align overlay (requirements-coc-ml.txt) into /opt/venv.
set -euo pipefail

WORKSPACE="${WORKSPACE:-/workspace}"
cd "$WORKSPACE"

WITH_ML=0
for arg in "$@"; do
  case "$arg" in
    --ml) WITH_ML=1 ;;
    *) echo ">> postCreate: ignoring unknown arg '$arg'" ;;
  esac
done

log() { echo ">> postCreate: $*"; }

# ---------------------------------------------------------------------------
# Step 0 — signing-key staging (T11 / specs/secrets-and-auth.md §Signing-key passthrough)
# The host key is mounted READ-ONLY (see devcontainer.json opt-in mounts). A strictly
# read-only ~/.ssh / ~/.gnupg breaks `git commit -S` (it needs a writable known_hosts /
# allowed_signers / lockfile dir) even though the coordination-log append succeeds against a
# read-only key. So copy the read-only mount into a WRITABLE home location and fix perms.
# Both paths are no-ops when the corresponding opt-in mount is absent (the common case).
# ---------------------------------------------------------------------------
if [ -d "$HOME/.host-ssh" ]; then
  log "SSH signing key detected (read-only mount) — staging a writable ~/.ssh"
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  # Copy keys + config from the read-only mount into the writable home. A copy FAILURE must
  # surface, not be swallowed (a partial/failed stage that still prints "staged" hides the
  # exact cryptic `git commit -S` key-not-found failure the staging exists to prevent).
  if cp -a "$HOME"/.host-ssh/. "$HOME/.ssh/" 2>/dev/null; then
    chmod 700 "$HOME/.ssh"
    # known_hosts / allowed_signers MUST exist + be owner-writable for signed commits.
    touch "$HOME/.ssh/known_hosts" "$HOME/.ssh/allowed_signers" 2>/dev/null || true
    # Tighten EVERY non-.pub regular file to 600 — ssh rejects group/other-readable private
    # keys regardless of name (signing_ed25519, github, <host>…), so a name filter is the
    # wrong axis; 600 on config/known_hosts/allowed_signers is also correct + owner-writable.
    find "$HOME/.ssh" -type f ! -name '*.pub' -exec chmod 600 {} + 2>/dev/null || true
    log "SSH signing staged. (git config gpg.format ssh is your host-side setup.)"
  else
    log "WARNING: failed to stage SSH key material from the read-only mount — git commit -S will not work."
  fi
fi

if [ -d "$HOME/.host-gnupg" ]; then
  log "GPG signing key detected (read-only mount) — staging a writable GNUPGHOME"
  # gpg writes lockfiles/random_seed into GNUPGHOME, so a read-only mount must be copied.
  mkdir -p "$HOME/.gnupg"
  if cp -a "$HOME"/.host-gnupg/. "$HOME/.gnupg/" 2>/dev/null; then
    chmod 700 "$HOME/.gnupg"
    find "$HOME/.gnupg" -type f -exec chmod 600 {} + 2>/dev/null || true
    find "$HOME/.gnupg" -type d -exec chmod 700 {} + 2>/dev/null || true
    # Non-interactive signing for a passphrase-protected key (tini reaps gpg-agent at PID 1).
    if ! grep -q '^pinentry-mode loopback' "$HOME/.gnupg/gpg.conf" 2>/dev/null; then
      echo 'pinentry-mode loopback' >> "$HOME/.gnupg/gpg.conf"
    fi
    if ! grep -q '^allow-loopback-pinentry' "$HOME/.gnupg/gpg-agent.conf" 2>/dev/null; then
      echo 'allow-loopback-pinentry' >> "$HOME/.gnupg/gpg-agent.conf"
    fi
    # chmod the conf files AFTER the appends — `echo >>` creates them with the umask (644),
    # not 600; gpg warns "unsafe permissions on homedir" on a group/other-readable conf.
    chmod 600 "$HOME/.gnupg/gpg.conf" "$HOME/.gnupg/gpg-agent.conf" 2>/dev/null || true
    log "GPG signing staged. Export GPG_TTY=\$(tty) in your shell for interactive sessions."
  else
    log "WARNING: failed to stage GPG key material from the read-only mount — gpg signing will not work."
  fi
fi

if [ ! -d "$HOME/.host-ssh" ] && [ ! -d "$HOME/.host-gnupg" ]; then
  log "no signing-key mount detected — signed commits disabled."
  log "  to enable: uncomment the SSH/GPG mount in .devcontainer/devcontainer.json + rebuild."
fi

# ---------------------------------------------------------------------------
# Step 0b — gitconfig staging (security MED-2, post-pivot R3-security audit)
# `git commit -S` needs git config user.signingkey / user.email / user.name to know WHICH
# key to use and HOW to author commits. The SSH/GPG key being staged above is necessary
# but NOT sufficient — without gitconfig, `git commit -S` either fails or uses the wrong
# identity. Symmetric to the .host-ssh / .host-gnupg pattern: opt-in read-only mount,
# copy to writable home, fix perms. No-op when the mount is absent.
# ---------------------------------------------------------------------------
if [ -f "$HOME/.host-gitconfig" ]; then
  log "gitconfig detected (read-only mount) — staging a writable ~/.gitconfig"
  if cp -a "$HOME/.host-gitconfig" "$HOME/.gitconfig" 2>/dev/null; then
    chmod 644 "$HOME/.gitconfig" 2>/dev/null || true
    log "gitconfig staged. (Includes user.signingkey / user.email / user.name from host.)"
  else
    log "WARNING: failed to stage gitconfig from the read-only mount — git commit -S may use the wrong identity or fail."
  fi
elif [ -d "$HOME/.host-ssh" ] || [ -d "$HOME/.host-gnupg" ]; then
  log "signing key staged but no .host-gitconfig mount — git config user.signingkey will not propagate from host."
  log "  to enable: uncomment the .host-gitconfig mount in .devcontainer/devcontainer.json + rebuild."
fi

# ---------------------------------------------------------------------------
# Step 1 — Python overlay: requirements-user.txt -> shared /opt/venv (O1)
# ---------------------------------------------------------------------------
if [ -s requirements-user.txt ]; then
  log "installing requirements-user.txt into the shared venv ($VIRTUAL_ENV)"
  uv pip install -r requirements-user.txt
else
  log "requirements-user.txt absent/empty — no extra Python deps (no-op)."
fi

# Opt-in ML/Align overlay (--ml) — torch-class, multi-GB; same shared venv (no --system).
if [ "$WITH_ML" = "1" ]; then
  if [ -s requirements-coc-ml.txt ]; then
    log "--ml: installing requirements-coc-ml.txt into the shared venv ($VIRTUAL_ENV)"
    uv pip install -r requirements-coc-ml.txt
  else
    log "--ml requested but requirements-coc-ml.txt absent/empty — skipping."
  fi
fi

# ---------------------------------------------------------------------------
# Step 2 — OS packages are NOT installed here (H3). Extra OS packages go through a
# Dockerfile.user FROM base rebuild — the non-root dev user never gets root-equivalent
# `sudo apt-get`. See specs/dependency-overlay.md postCreate step 2.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Step 3 — Node overlay: root package.json -> <pm> install (O5: reuse the detection hook)
# ---------------------------------------------------------------------------
if [ -f package.json ]; then
  PM="npm"
  if [ -f .claude/hooks/detect-package-manager.js ]; then
    DETECTED="$(node .claude/hooks/detect-package-manager.js --cwd "$WORKSPACE" 2>/dev/null | jq -r '.command // "npm"')"
    if [ -n "$DETECTED" ] && [ "$DETECTED" != "null" ]; then
      PM="$DETECTED"
    fi
  fi
  if command -v "$PM" >/dev/null 2>&1; then
    log "installing Node deps with detected package manager: $PM"
    "$PM" install
  else
    log "package.json present but '$PM' not on PATH — install $PM (e.g. corepack enable) and re-run."
  fi
else
  log "no root package.json — no Node deps (no-op)."
fi

# ---------------------------------------------------------------------------
# Step 4 — pre-commit hooks
# ---------------------------------------------------------------------------
if [ -f .pre-commit-config.yaml ]; then
  if command -v pre-commit >/dev/null 2>&1; then
    log "installing pre-commit git hooks"
    pre-commit install
  else
    log ".pre-commit-config.yaml present but pre-commit not on PATH — add it to requirements-user.txt."
  fi
else
  log "no .pre-commit-config.yaml — skipping pre-commit install (no-op)."
fi

# ---------------------------------------------------------------------------
# Step 5 — project escape hatch: source the project-owned overlay script if present
# ---------------------------------------------------------------------------
if [ -f .devcontainer/postCreate.user.sh ]; then
  log "sourcing project escape hatch: .devcontainer/postCreate.user.sh"
  # shellcheck disable=SC1091
  source .devcontainer/postCreate.user.sh
else
  log "no .devcontainer/postCreate.user.sh — skipping project escape hatch (no-op)."
fi

log "done."
