#!/bin/sh
set -eu

fail() {
  printf 'release tag validation failed: %s\n' "$1" >&2
  exit 1
}

[ "$#" -eq 2 ] || fail 'usage: validate-release-tag.sh TAG_COMMIT MAIN_REF'
tag_commit=$1
main_ref=$2

git rev-parse --verify --quiet "$tag_commit^{commit}" >/dev/null ||
  fail 'tag does not resolve to a commit'
git rev-parse --verify --quiet "$main_ref^{commit}" >/dev/null ||
  fail 'main ref is unavailable'

if ! git merge-base --is-ancestor "$tag_commit^{commit}" "$main_ref^{commit}"; then
  fail 'tag commit is not reachable from main'
fi
