#!/usr/bin/env bash
#
# init-repo-with-deploy-key.sh [--no-sandbox]
# -------------------------------------------
# Bootstrap a project directory against a GitHub repo for host + Claude-sandbox
# use. Run on the HOST (needs gh).
#
# Key design point: it sets a PLAIN ssh remote and writes NO repo-local
# core.sshCommand. The repo's .git/config is shared into the sandbox container,
# and a repo-local core.sshCommand (host paths / bare `ssh`) breaks git in the
# container. Instead:
#   * HOST pushes with your account key (your ~/.ssh/config default for github.com).
#   * SANDBOX pushes with a per-repo deploy key, provisioned here and auto-selected
#     by the sandbox's git-ssh/setup.sh.

set -euo pipefail
die(){ echo "error: $*" >&2; exit 1; }

WANT_SANDBOX=1
[ "${1:-}" = "--no-sandbox" ] && { WANT_SANDBOX=0; shift; }

command -v gh >/dev/null || die "gh not found — https://cli.github.com"
gh auth status >/dev/null 2>&1 || die "gh not authenticated — run: gh auth login"

default_name="$(basename "$PWD")"
read -rp "Repo name to create on GitHub [${default_name}]: " REPO; REPO="${REPO:-$default_name}"
default_owner="$(gh api user --jq .login)"
read -rp "Owner (user or org) [${default_owner}]: " OWNER; OWNER="${OWNER:-$default_owner}"
read -rp "Visibility — private/public/internal [private]: " VIS; VIS="${VIS:-private}"
case "$VIS" in private|public|internal) ;; *) die "visibility must be private/public/internal" ;; esac
FULL="${OWNER}/${REPO}"

echo
echo "  repo:    $FULL ($VIS)"
echo "  sandbox: $([ "$WANT_SANDBOX" = 1 ] && echo 'yes — provision a repo-scoped deploy key' || echo 'no (--no-sandbox)')"
read -rp "Proceed? [y/N]: " ok; [[ "${ok:-}" =~ ^[Yy]$ ]] || die "aborted"

# 1. create the repo if missing
if gh repo view "$FULL" >/dev/null 2>&1; then
  echo "• $FULL already exists — skipping creation"
else
  gh repo create "$FULL" --"$VIS" >/dev/null
  echo "• created $FULL"
fi

# 2. wire the LOCAL repo — plain remote, NO core.sshCommand
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || git init -q
git rev-parse HEAD            >/dev/null 2>&1 || git symbolic-ref HEAD refs/heads/main
git config --local --unset core.sshCommand 2>/dev/null || true   # strip any legacy override
git remote remove origin 2>/dev/null || true
git remote add origin "git@github.com:${FULL}.git"
echo "• origin -> git@github.com:${FULL}.git (plain — no repo-local ssh override)"

# 3. provision the sandbox deploy key (unless --no-sandbox)
if [ "$WANT_SANDBOX" = 1 ]; then
  prov=""
  if command -v provision-sandbox-repo-key >/dev/null 2>&1; then
    prov="provision-sandbox-repo-key"
  else
    sib="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/provision-sandbox-repo-key.sh"
    [ -x "$sib" ] && prov="$sib"
  fi
  if [ -n "$prov" ]; then
    echo "• provisioning sandbox deploy key…"
    "$prov" "$FULL"
  else
    echo "⚠ provision-sandbox-repo-key not found — run it yourself: provision-sandbox-repo-key $FULL" >&2
  fi
fi

cat <<EOF

Done.
  Host push:   git add -A && git commit -m "init" && git push -u origin main
  Sandbox:     cd "$PWD" && cs-tg     # the SessionStart hook wires git to the sandbox key
EOF
