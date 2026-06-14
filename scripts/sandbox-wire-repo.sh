#!/usr/bin/env bash
#
# sandbox-wire-repo.sh — make a repo (mounted into the Claude sandbox) pushable
# from INSIDE the sandbox, over its own repo-scoped deploy key.
#
# Why this exists
# ---------------
# The sandbox base image has NO system ssh. Git works in here only because the
# git-over-SSH setup provisions a private OpenSSH at ~/.local-ssh and points git
# at it by ABSOLUTE path. A host tool like init-repo wires a repo with a bare
# `ssh`, which doesn't exist in the container — so this script does the sandbox
# side correctly instead.
#
# Boundary-safe by design
# ------------------------
#   * The deploy key is generated HERE; its private half never leaves the
#     container. You authorise only its PUBLIC half on the repo, from the host
#     (which has gh).
#   * It sets a per-repo GIT_SSH_COMMAND (an env override) rather than a
#     repo-local core.sshCommand — so it coexists with init-repo's host wiring in
#     the same shared .git/config: the host uses its core.sshCommand, the sandbox
#     uses this env (env wins).
#
# Prerequisite: the repo must be MOUNTED into the sandbox. The container only
# sees mounted paths (today, just the primary project dir). To use another repo
# from the sandbox, add it as a volume in the sandbox's docker/compose config.
#
# Usage (inside the sandbox):   ./sandbox-wire-repo.sh [REPO_DIR]   (default: $PWD)

set -euo pipefail
die(){ echo "error: $*" >&2; exit 1; }

REPO_DIR="$(cd "${1:-$PWD}" 2>/dev/null && pwd)" || die "no such directory: ${1:-$PWD}"
git -C "$REPO_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || die "$REPO_DIR is not a git repo (is it mounted into the sandbox?)"

KEYDIR="$HOME/.claude/git-ssh"
SSH="$HOME/.local-ssh/usr/bin/ssh"
KEYGEN="$HOME/.local-ssh/usr/bin/ssh-keygen"
KEYSCAN="$HOME/.local-ssh/usr/bin/ssh-keyscan"

# 1. ensure the container's private ssh exists (provisioned by the git-over-ssh setup)
if [ ! -x "$SSH" ]; then
  [ -f "$KEYDIR/setup.sh" ] || die "no $SSH and no $KEYDIR/setup.sh to provision ssh"
  echo "• provisioning container ssh via $KEYDIR/setup.sh"
  bash "$KEYDIR/setup.sh" >/dev/null
fi
[ -x "$KEYGEN" ] || die "ssh-keygen not found at $KEYGEN"

# 2. per-repo slug from origin (owner_repo), falling back to the directory name
ORIGIN="$(git -C "$REPO_DIR" remote get-url origin 2>/dev/null || true)"
if printf '%s' "$ORIGIN" | grep -qiE '[:/][^/]+/[^/]+(\.git)?/?$'; then
  SLUG="$(printf '%s' "$ORIGIN" | sed -E 's#/$##; s#\.git$##; s#.*[:/]([^/]+/[^/]+)$#\1#' | tr '/ ' '__')"
else
  SLUG="$(basename "$REPO_DIR")"
fi
SLUG="$(printf '%s' "$SLUG" | tr -cd 'A-Za-z0-9_.-')"
[ -n "$SLUG" ] || die "could not derive a slug"
KEY="$KEYDIR/deploy_${SLUG}"
ENVF="$KEYDIR/${SLUG}.env"

mkdir -p "$KEYDIR" "$HOME/.ssh"; chmod 700 "$HOME/.ssh" "$KEYDIR" 2>/dev/null || true

# 3. generate the deploy key (idempotent); private half stays in the container
if [ -f "$KEY" ]; then
  echo "• reusing existing key $KEY"
else
  "$KEYGEN" -t ed25519 -N "" -C "claude-sandbox-${SLUG}" -f "$KEY" >/dev/null
  chmod 600 "$KEY"
  echo "• generated deploy key $KEY"
fi

# 4. known_hosts for github.com
[ -s "$HOME/.ssh/known_hosts" ] || "$KEYSCAN" -t ed25519,rsa github.com 2>/dev/null > "$HOME/.ssh/known_hosts"

# 5. write a sourceable per-repo env. GIT_SSH_COMMAND overrides any repo-local
#    core.sshCommand baked into .git/config by a host tool.
GSC="$SSH -i $KEY -o IdentitiesOnly=yes -o UserKnownHostsFile=$HOME/.ssh/known_hosts -o StrictHostKeyChecking=accept-new"
printf 'export GIT_SSH_COMMAND=%q\n' "$GSC" > "$ENVF"
echo "• wrote env file $ENVF"

cat <<EOF

Two steps to finish:

1) On the HOST (it has gh), authorise the PUBLIC key on the repo with write
   access — save the key below to a file, then:
     gh repo deploy-key add KEY.pub --repo <owner>/<name> --title claude-sandbox --allow-write

   public key:
     $(cat "${KEY}.pub")

2) In the SANDBOX, before pushing this repo:
     source "$ENVF"
     git -C "$REPO_DIR" push

Verify the key (greets you with the repo name, then exits 1 — that is normal
for a deploy key):
   $SSH -i $KEY -o IdentitiesOnly=yes -o UserKnownHostsFile=$HOME/.ssh/known_hosts -T git@github.com
EOF
