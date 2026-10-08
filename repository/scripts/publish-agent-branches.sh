#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -L)"
MODE="${1:-}"
case "$MODE" in --dry-run|--push) ;; *) printf '用法：sh %s --dry-run|--push\n' "$0" >&2; exit 2 ;; esac
command -v jq >/dev/null 2>&1 || { printf '分支发布需要 jq。\n' >&2; exit 1; }
if [ "$MODE" = --push ]; then
  git -C "$ROOT" remote get-url origin >/dev/null 2>&1 || { printf '缺少 origin remote。\n' >&2; exit 1; }
fi
SOURCE_COMMIT="$(git -C "$ROOT" rev-parse HEAD)"
case "$SOURCE_COMMIT" in *[!0-9a-fA-F]*|'') printf 'HEAD 不是有效 commit。\n' >&2; exit 1 ;; esac

TMP="${TMPDIR:-/tmp}/agent-branches.$$"
attempt=0
while ! (umask 077 && mkdir "$TMP") 2>/dev/null; do
  attempt=$((attempt + 1))
  [ "$attempt" -lt 10 ] || { printf '无法创建分支构建目录。\n' >&2; exit 1; }
  TMP="${TMPDIR:-/tmp}/agent-branches.$$.$attempt"
done
WORKTREE=""
LOCAL_BRANCH_CREATED=0
cleanup() {
  if [ -n "$WORKTREE" ] && [ -d "$WORKTREE" ]; then
    git -C "$ROOT" worktree remove --force "$WORKTREE" >/dev/null 2>&1 || true
  fi
  if [ "$LOCAL_BRANCH_CREATED" -eq 1 ]; then
    git -C "$ROOT" branch -D "$CLEANUP_BRANCH" >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM


for PROFILE in "$ROOT"/repository/branch-profiles/*.json; do
  [ -f "$PROFILE" ] || continue
  BRANCH="$(jq -er '.branch' "$PROFILE")"
  MIRROR_TREE="$(jq -r '(.mirrorSourceTree // false) | tostring' "$PROFILE")"
  [ "$BRANCH" = main ] && continue
  PROFILE_NAME="${PROFILE##*/}"
  PROFILE_NAME="${PROFILE_NAME%.json}"
  PACKAGE="$TMP/package-$BRANCH"
  mkdir -p "$PACKAGE"
  sh "$ROOT/repository/scripts/build-agent-branch.sh" "$PROFILE_NAME" "$(git -C "$ROOT" rev-parse --show-toplevel)" "$PACKAGE" "$SOURCE_COMMIT"
  [ "$MODE" = --push ] || continue

  REMOTE_REF="refs/remotes/origin/$BRANCH"
  if git -C "$ROOT" ls-remote --exit-code --heads origin "$BRANCH" > "$TMP/remote-ref" 2>/dev/null; then
    git -C "$ROOT" fetch --quiet --depth=1 origin "refs/heads/$BRANCH:$REMOTE_REF"
    BASE_REF="$REMOTE_REF"
    IS_NEW=0
  else
    BASE_REF="$SOURCE_COMMIT"
    IS_NEW=1
  fi

  WORKTREE="$TMP/worktree-$BRANCH"
  git -C "$ROOT" worktree add --detach "$WORKTREE" "$BASE_REF" >/dev/null
  if [ "$IS_NEW" -eq 1 ]; then
    LOCAL_BRANCH="$BRANCH-build-$$"
    git -C "$WORKTREE" switch --orphan "$LOCAL_BRANCH" >/dev/null
    LOCAL_BRANCH_CREATED=1
    CLEANUP_BRANCH="$LOCAL_BRANCH"
  fi
  git -C "$WORKTREE" rm -rf --ignore-unmatch . >/dev/null 2>&1 || true
  git -C "$WORKTREE" clean -ffdqx
  if [ "$MIRROR_TREE" = true ]; then
    cp -a "$PACKAGE/." "$WORKTREE/"
    git -C "$WORKTREE" add -A -f
  else
    SKILL_PATH="$(jq -er '.skillPath' "$PROFILE")"
    mkdir -p "$WORKTREE/$SKILL_PATH"
    cp -a "$PACKAGE/$SKILL_PATH/." "$WORKTREE/$SKILL_PATH/"
    git -C "$WORKTREE" add -A
  fi
  if git -C "$WORKTREE" diff --cached --quiet; then
    printf '%s 分支无需更新。\n' "$BRANCH"
  else
    git -C "$WORKTREE" commit -m "Build $BRANCH skill package from $SOURCE_COMMIT"
    git -C "$WORKTREE" push origin "HEAD:refs/heads/$BRANCH"
    printf '已推送 %s 分支。\n' "$BRANCH"
  fi
  git -C "$ROOT" worktree remove --force "$WORKTREE" >/dev/null
  WORKTREE=""
  if [ "$LOCAL_BRANCH_CREATED" -eq 1 ]; then
    git -C "$ROOT" branch -D "$CLEANUP_BRANCH" >/dev/null
    LOCAL_BRANCH_CREATED=0
  fi
done

if [ "$MODE" = --dry-run ]; then
  printf '已完成发行分支本地构建检查；没有推送远端分支。\n'
fi
