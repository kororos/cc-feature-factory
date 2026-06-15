#!/usr/bin/env bash
#
# provision-sandbox-repo-key.sh <owner>/<repo>
# --------------------------------------------
# HOST script (needs gh). Creates a passwordless, repo-scoped DEPLOY KEY for a
# repo and drops it into the Claude sandbox's shared key dir, then registers it
# on GitHub with write access. After running this once per repo, ANY sandbox
# container started in that project auto-wires git over the right key (the
# repo-aware git-ssh/setup.sh picks deploy_<owner>_<repo> by itself).
#
# The key dir is the host side of the bind mount that every container sees as
# ~/.claude/git-ssh.  Override with CS_GITSSH_DIR if your layout differs.

set -euo pipefail
die(){ echo "error: $*" >&2; exit 1; }

command -v gh         >/dev/null || die "GitHub CLI (gh) not found — https://cli.github.com"
command -v ssh-keygen >/dev/null || die "ssh-keygen not found"
gh auth status >/dev/null 2>&1   || die "gh is not authenticated — run: gh auth login"

FULL="${1:-}"
[ -n "$FULL" ] || { read -rp "Repo (owner/name): " FULL; }
[[ "$FULL" == */* ]] || die "expected owner/name, e.g. kororos/myrepo"

gh repo view "$FULL" >/dev/null 2>&1 \
  || die "repo $FULL not found (create it first, or check access)"

KEYDIR="${CS_GITSSH_DIR:-$HOME/.claude-sandbox/dot-claude/git-ssh}"
[ -d "$KEYDIR" ] || die "sandbox key dir not found: $KEYDIR  (set CS_GITSSH_DIR)"

SLUG="$(printf '%s' "$FULL" | tr '/ ' '__' | tr -cd 'A-Za-z0-9_.-')"
KEY="$KEYDIR/deploy_${SLUG}"
TITLE="claude-sandbox"

# 1. generate the deploy key into the shared dir (idempotent)
if [ -f "$KEY" ]; then
  echo "• key already exists: $KEY"
else
  ssh-keygen -t ed25519 -N "" -C "claude-sandbox-${SLUG}" -f "$KEY" >/dev/null
  chmod 600 "$KEY"; chmod 644 "${KEY}.pub"
  echo "• generated $KEY"
fi

# 2. register the public half on the repo (write), once
if gh repo deploy-key list --repo "$FULL" 2>/dev/null | grep -q "$TITLE"; then
  echo "• a '$TITLE' deploy key is already on $FULL — skipping registration"
  echo "  (if you rotated the key, delete the old one: gh repo deploy-key delete <id> --repo $FULL)"
else
  gh repo deploy-key add "${KEY}.pub" --repo "$FULL" --title "$TITLE" --allow-write
  echo "• registered write deploy key on $FULL"
fi

cat <<EOF

Done. Start a Claude sandbox in that project and git will wire automatically:
  cd <that project>
  cs-tg          # (or cs / cs-bg) — SessionStart hook runs setup.sh, picks deploy_${SLUG}
EOF
