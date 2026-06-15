#!/usr/bin/env bash
#
# cleanup-repo.sh <owner>/<repo> [project_dir]
# --------------------------------------------
# Tear down everything created for a repo so you can re-test from scratch.
# Run on the HOST. Interactive; asks before destructive steps. Removes:
#   - the running sandbox container for the project
#   - local git wiring (.git in the project dir; your working files are kept)
#   - host deploy key files          ~/.ssh/deploy_<slug>{,.pub}
#   - sandbox deploy key + env       ~/.claude-sandbox/dot-claude/git-ssh/deploy_<slug>{,.pub}, <slug>.env
#   - saved sandbox session history  ~/.claude-sandbox/dot-claude/projects/-<encoded-path>
#   - (optional, separate confirm) the GitHub repo itself
#
# Override locations with CS_GITSSH_DIR / CS_SESS_DIR if your layout differs.

set -uo pipefail
die(){ echo "error: $*" >&2; exit 1; }

FULL="${1:-}"; [ -n "$FULL" ] || { read -rp "Repo (owner/name): " FULL; }
[[ "$FULL" == */* ]] || die "expected owner/name, e.g. kororos/inventory"
OWNER="${FULL%%/*}"; REPO="${FULL##*/}"
SLUG="$(printf '%s' "$FULL" | tr '/ ' '__' | tr -cd 'A-Za-z0-9_.-')"

PROJ="${2:-$HOME/projects/$REPO}"
GITSSH="${CS_GITSSH_DIR:-$HOME/.claude-sandbox/dot-claude/git-ssh}"
SESSROOT="${CS_SESS_DIR:-$HOME/.claude-sandbox/dot-claude/projects}"
ENC="$(printf '%s' "$PROJ" | tr '/' '-')"
CNAME="claude-$(basename "$PROJ")"

echo "Cleanup plan for '$FULL':"
echo "  project dir:     $PROJ            (remove .git only — your files are kept)"
echo "  container:       $CNAME           (stop + remove if present)"
echo "  host key:        $HOME/.ssh/deploy_${SLUG}{,.pub}"
echo "  sandbox key/env: $GITSSH/deploy_${SLUG}{,.pub}, $GITSSH/${SLUG}.env"
echo "  session history: $SESSROOT/$ENC"
echo
read -rp "Proceed with this LOCAL cleanup? [y/N]: " ok; [[ "${ok:-}" =~ ^[Yy]$ ]] || die "aborted"

# container
if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$CNAME"; then
  docker rm -f "$CNAME" >/dev/null 2>&1 && echo "• removed container $CNAME"
else
  echo "• no container $CNAME"
fi

# local git wiring
if [ -d "$PROJ/.git" ]; then rm -rf "$PROJ/.git" && echo "• removed $PROJ/.git"; else echo "• no $PROJ/.git"; fi

# host deploy key
rm -f "$HOME/.ssh/deploy_${SLUG}" "$HOME/.ssh/deploy_${SLUG}.pub" && echo "• cleared host deploy key (if any)"

# sandbox key + env
rm -f "$GITSSH/deploy_${SLUG}" "$GITSSH/deploy_${SLUG}.pub" "$GITSSH/${SLUG}.env" && echo "• cleared sandbox key/env (if any)"

# session history
if [ -d "$SESSROOT/$ENC" ]; then rm -rf "$SESSROOT/$ENC" && echo "• removed session history"; else echo "• no session history"; fi

echo "• local cleanup done"
echo

# GitHub repo — destructive, separate confirm
read -rp "Also DELETE the GitHub repo $FULL? [y/N]: " delok
if [[ "${delok:-}" =~ ^[Yy]$ ]]; then
  if gh repo delete "$FULL" --yes 2>/dev/null; then
    echo "• deleted GitHub repo $FULL"
  else
    echo "⚠ gh couldn't delete it (the token needs the delete_repo scope). To finish:"
    echo "    gh auth refresh -h github.com -s delete_repo && gh repo delete $FULL --yes"
    echo "  …or delete it in the GitHub web UI."
  fi
fi

echo
echo "If you added a 'Host' alias for $REPO in ~/.ssh/config, remove it by hand."
echo "Re-test with:  cd \"$PROJ\" && init-repo"
