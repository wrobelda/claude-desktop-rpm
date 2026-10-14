#!/usr/bin/env bash
# Merge upstream main into the current branch and bump to the newest build.
#
# This branch carries changes that upstream has not merged yet, including the
# per-architecture checksums in packaging/. Upstream's version bumps rewrite
# the same lines, so merging them conflicts. A conflict is resolved
# automatically only when upstream's side of every conflicting hunk consists
# of version-bump lines; scripts/bump-version.sh then rewrites the version
# data in this branch's format. Any other conflict stops the sync.
#
# Usage: .github/scripts/sync-upstream.sh <upstream-ref>
# Exit status: 0 when the branch is up to date or a merge/bump was committed,
#              1 when a conflict needs manual resolution.
set -euo pipefail

upstream="${1:?usage: $0 <upstream-ref>}"
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"
SPEC=packaging/claude-desktop.spec

# Lines that an upstream version bump changes.
bump_line='^(%global deb_sha256 [0-9a-f]+|Version:[[:space:]].*|Release:[[:space:]].*|\* .* - [0-9.]+-0|- Update to upstream [0-9.]+|[[:space:]]*<param name="(url|filename)">.*</param>|)$'

# Version before the merge. Upstream's bump changes the Version line, which
# this branch does not touch, so the merge takes upstream's value even when it
# keeps this branch's checksums. Restore it after the merge so that
# bump-version.sh moves Version and the checksums together.
old_version=$(sed -n 's/^Version:[[:space:]]*//p' "$SPEC")

if git merge-base --is-ancestor "$upstream" HEAD; then
  echo "already contains $upstream"
else
  if git merge --no-edit "$upstream" >/dev/null 2>&1; then
    echo "merged $upstream without conflicts"
  else
    conflicted=$(git diff --name-only --diff-filter=U)
    for f in $conflicted; do
      case "$f" in
        "$SPEC"|packaging/_service) ;;
        *) echo "conflict outside packaging version data: $f" >&2
           git merge --abort; exit 1 ;;
      esac
      # Upstream's side of a hunk is between "=======" and ">>>>>>>".
      bad=$(awk '/^=======$/{u=1; next} /^>>>>>>> /{u=0; next} u' "$f" \
            | grep -Ev "$bump_line" || true)
      if [ -n "$bad" ]; then
        echo "conflict in $f is not a version bump:" >&2
        echo "$bad" >&2
        git merge --abort; exit 1
      fi
    done
    git merge --abort
    git merge --no-edit -X ours "$upstream" >/dev/null
    echo "merged $upstream, keeping this branch's side of version-bump conflicts"
  fi
  if [ "$(sed -n 's/^Version:[[:space:]]*//p' "$SPEC")" != "$old_version" ]; then
    sed -i "s/^Version:[[:space:]].*/Version:        $old_version/" "$SPEC"
    git commit -q --amend --no-edit "$SPEC"
  fi
fi

# Bring Version and the checksums to the newest build, in this branch's format.
out=$(scripts/bump-version.sh)
echo "$out"
if grep -q '^bumped ' <<<"$out"; then
  new=$(sed -n 's/^bumped .* -> //p' <<<"$out")
  # The merge may already have brought upstream's changelog entry for this
  # version; keep that one and drop the duplicate the bump just added.
  python3 - "$SPEC" "$new" <<'EOF'
import re, sys
path, ver = sys.argv[1], sys.argv[2]
text = open(path).read()
head, sep, log = text.partition("%changelog\n")
entries = [e.strip("\n") for e in re.split(r"\n(?=\* )", log.strip("\n"))]
if len(entries) > 1 and all(e.splitlines()[0].endswith(f" - {ver}-0") for e in entries[:2]):
    entries.pop(0)
open(path, "w").write(head + sep + "\n\n".join(entries) + "\n")
EOF
  git add "$SPEC" packaging/_service
  git commit -q -m "claude-desktop ${new}: update to upstream release"
  echo "committed bump to $new"
fi
