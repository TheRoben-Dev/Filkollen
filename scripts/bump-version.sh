#!/bin/sh
# Sets the marketing version, bumps the build number, and dates the changelog.
#   scripts/bump-version.sh 0.2.0
set -eu
cd "$(dirname "$0")/.."

new="${1:?usage: scripts/bump-version.sh <version>, e.g. 0.2.0}"
case "$new" in
  *[!0-9.]*|"") echo "Version must look like 1.2.3" >&2; exit 1 ;;
esac

build=$(sed -n 's/^ *CURRENT_PROJECT_VERSION: "\{0,1\}\([0-9]*\)"\{0,1\}$/\1/p' project.yml)
next=$((build + 1))

# In place without GNU/BSD sed differences.
tmp=$(mktemp)
sed -e "s/^\( *MARKETING_VERSION: \).*/\1\"$new\"/" \
    -e "s/^\( *CURRENT_PROJECT_VERSION: \).*/\1\"$next\"/" project.yml > "$tmp" && mv "$tmp" project.yml

if grep -q '^## \[Unreleased\]' CHANGELOG.md; then
  tmp=$(mktemp)
  awk -v v="$new" -v d="$(date +%Y-%m-%d)" '
    /^## \[Unreleased\]/ && !done { print; print ""; print "## [" v "] - " d; done=1; next }
    { print }' CHANGELOG.md > "$tmp" && mv "$tmp" CHANGELOG.md
fi

echo "Version $new (build $next). Review CHANGELOG.md, then: git commit -am \"chore(release): $new\" && git tag v$new"
