#!/usr/bin/env bash
#
# init-repo-with-deploy-key.sh
# ----------------------------
# Bootstrap a project directory against a GitHub repo using a passwordless,
# REPO-SCOPED deploy key (least privilege) instead of your account key.
#
# Run this on your HOST, where `gh` is authenticated with your account. It will:
#   1. ask for the repo name (+ owner + visibility),
#   2. create the repo on GitHub if it doesn't already exist,
#   3. generate a passwordless ed25519 deploy key,
#   4. register the PUBLIC key on THAT repo with write access,
#   5. wire this directory's git to push over that key only.
#
# Design choices that keep it safe alongside a Claude sandbox:
#   * The remote URL stays plain (git@github.com:owner/repo.git) — no host-only
#     SSH alias baked into .git/config, which is often shared/mounted into the
#     sandbox.
#   * The key is selected via the repo-local `core.sshCommand`, so it touches
#     neither ~/.ssh/config nor other repos. A sandbox that sets GIT_SSH_COMMAND
#     overrides it transparently, and one that doesn't simply can't read the
#     host key path — a safe failure, never a wrong-key push.

set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }

command -v gh         >/dev/null || die "GitHub CLI (gh) not found — https://cli.github.com"
command -v ssh-keygen >/dev/null || die "ssh-keygen not found"
gh auth status >/dev/null 2>&1   || die "gh is not authenticated — run: gh auth login"

# --- inputs --------------------------------------------------------------
default_name="$(basename "$PWD")"
read -rp "Repo name to create on GitHub [${default_name}]: " REPO
REPO="${REPO:-$default_name}"

default_owner="$(gh api user --jq .login)"
read -rp "Owner (user or org) [${default_owner}]: " OWNER
OWNER="${OWNER:-$default_owner}"

read -rp "Visibility — private/public/internal [private]: " VIS
VIS="${VIS:-private}"
case "$VIS" in private|public|internal) ;; *) die "visibility must be private, public, or internal" ;; esac

FULL="${OWNER}/${REPO}"
SLUG="$(printf '%s' "$FULL" | tr '/ ' '__' | tr -cd 'A-Za-z0-9_.-')"
KEY="${HOME}/.ssh/deploy_${SLUG}"
TITLE="$(hostname)"

echo
echo "  repo:       $FULL ($VIS)"
echo "  deploy key: $KEY"
read -rp "Proceed? [y/N]: " ok; [[ "${ok:-}" =~ ^[Yy]$ ]] || die "aborted"

# --- 1. create the repo if missing --------------------------------------
if gh repo view "$FULL" >/dev/null 2>&1; then
  echo "• repo $FULL already exists — skipping creation"
else
  gh repo create "$FULL" --"$VIS" >/dev/null
  echo "• created $FULL"
fi

# --- 2. passwordless deploy key (idempotent) ----------------------------
if [[ -f "$KEY" ]]; then
  echo "• key $KEY already exists — reusing"
else
  ssh-keygen -t ed25519 -N "" -C "deploy-${SLUG}" -f "$KEY" >/dev/null
  chmod 600 "$KEY"
  echo "• generated passwordless deploy key"
fi

# --- 3. register the public key on the repo (write) ---------------------
if gh repo deploy-key list --repo "$FULL" 2>/dev/null | grep -q "$TITLE"; then
  echo "• a deploy key titled '$TITLE' is already on $FULL — skipping"
else
  gh repo deploy-key add "${KEY}.pub" --repo "$FULL" --title "$TITLE" --allow-write
  echo "• added write deploy key to $FULL"
fi

# --- 4. wire up the local repo ------------------------------------------
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || git init -q
git rev-parse HEAD            >/dev/null 2>&1 || git symbolic-ref HEAD refs/heads/main
git remote remove origin 2>/dev/null || true
git remote add origin "git@github.com:${FULL}.git"
git config core.sshCommand "ssh -i ${KEY} -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
echo "• origin -> git@github.com:${FULL}.git  (this repo pushes with ${KEY##*/})"

cat <<EOF

Done. This directory now pushes ${FULL} over its own scoped deploy key.

  git add -A && git commit -m "init"
  git push -u origin main

Verify the key (deploy keys are repo-scoped, so this greets you with the repo
name then exits 1 — that is expected, not an error):
  GIT_SSH_COMMAND="ssh -i ${KEY} -o IdentitiesOnly=yes" ssh -T git@github.com
EOF
