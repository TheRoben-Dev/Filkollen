#!/bin/sh
# Points this clone's git hooks at scripts/pre-commit.
set -eu
cd "$(dirname "$0")/.."
ln -sf ../../scripts/pre-commit .git/hooks/pre-commit
chmod +x scripts/pre-commit
echo "pre-commit hook installed (needs swiftlint and/or swiftformat from Homebrew to do anything)."
