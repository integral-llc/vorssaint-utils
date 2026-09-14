#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint

set -euo pipefail
cd "$(dirname "$0")/.."
script="$PWD/Tools/deploy-version.sh"
build_script="${VORSSAINT_BUILD_SCRIPT:-$PWD/build.sh}"
source "$script"

repo="$(mktemp -d)"
trap 'command rm -rf "$repo"' EXIT
cd "$repo"

fail() {
    print -u2 -r -- "deploy version: $1"
    exit 1
}

check() {
    [[ "$1" == "$2" ]] || fail "$3 (expected '$2', got '$1')"
}

planned() {
    plan "$@" 2>/dev/null
}

# The install parent seals the copied bundle and exits long before the end of
# build.sh. A function it reaches that is only defined further down is
# "command not found" there, and the deploy leaves a copied, unsealed bundle.
parent_exit="$(grep -n 'VORSSAINT_INSTALL_CHILD:-0' "$build_script" | head -1 | cut -d: -f1)"
[[ -n "$parent_exit" ]] || fail "build.sh no longer has the install parent this checks"
while IFS=: read -r line definition; do
    name="${definition%%\(*}"
    (( line > parent_exit )) || continue
    if head -n "$parent_exit" "$build_script" | grep -vE '^[[:space:]]*#' \
        | grep -qE "(^|[^A-Za-z0-9_])${name}([^A-Za-z0-9_]|\$)"; then
        fail "$name is used before the install parent exits but defined below it, at line $line"
    fi
done < <(grep -nE '^[a-z_]+\(\) \{' "$build_script")

check "$(bump 3.3.5 patch)" 3.3.6 "a patch bumps the last number"
check "$(bump 3.3.5 minor)" 3.4.0 "a minor bump starts the patch over"
check "$(bump 3.9.5 major)" 4.0.0 "a major bump starts minor and patch over"
check "$(bump 3.3.5 build)" 3.3.5 "a build-only change keeps the version"
check "$(larger_version 3.3.10 3.3.9)" 3.3.10 "versions compare by number, not as text"
check "$(larger_version 3.3.9 3.4.0)" 3.4.0 "a higher minor outranks a higher patch"

catalog() {
    mkdir -p Sources/Vorssaint/Core
    print -r -- "enum AppFeature: String, CaseIterable {
    // One group
    case alpha, beta,
         gamma$1
}

enum Other {
    case notAFeature
}" > "$CATALOG"
}

release() {
    mkdir -p Resources
    print -r -- '<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleShortVersionString</key>
	<string>'"$1"'</string>
	<key>CFBundleVersion</key>
	<string>'"$2"'</string>
</dict>
</plist>' > "$PLIST"
}

catalog ""
check "$(feature_cases < "$CATALOG" | tr '\n' ' ')" "alpha beta gamma " \
    "cases split over lines and around comments are read, and nothing past the enum"

git init -q -b main
git config user.name tests
git config user.email tests@example.invalid
git config commit.gpgsign false
print -r -- "$STATE" > .gitignore
print -r -- "notes" > README.md
release 3.3.5 86
git add -A
git commit -qm "chore: release 3.3.5"
git checkout -q -b fork

read -r version build tree <<< "$(planned)"
check "$version $build" "3.3.5 86" "a checkout identical to the release deploys as the release"
[[ ! -e "$STATE" ]] || fail "planning wrote deploy state"

catalog ", delta"
read -r version build tree <<< "$(planned)"
check "$version $build" "3.4.0 87" "an uncommitted new feature is a minor bump"
record "$version" "$build" "$tree"
check "$(git rev-parse "$BASELINE_REF")" "$tree" "the deployed tree stays reachable from a ref"

git add -A
git commit -qm "feat: delta"
read -r version build tree <<< "$(planned)"
check "$version $build" "3.4.0 87" "committing what was already deployed is not a second bump"

print -r -- "// tweak" > Sources/Vorssaint/Core/Other.swift
read -r version build tree <<< "$(planned)"
check "$version $build" "3.4.1 88" "a source change without a new feature is a patch"
command rm -f Sources/Vorssaint/Core/Other.swift

print -r -- "more notes" >> README.md
read -r version build tree <<< "$(planned)"
check "$version $build" "3.4.0 88" "a change outside the app's sources only bumps the build"
git checkout -q -- README.md

catalog ""
read -r version build tree <<< "$(planned)"
check "$version $build" "4.0.0 88" "a removed feature is a major bump"
catalog ", delta"

read -r version build tree <<< "$(planned minor)"
check "$version $build" "3.5.0 88" "a forced level applies even with nothing changed"
if planned bogus >/dev/null 2>&1; then
    fail "an unknown level was accepted"
fi
if record 3.4 87 "$tree" 2>/dev/null; then
    fail "a malformed version was recorded"
fi

# Upstream ships 3.5.0 without the fork's feature; the fork merges it. The
# number has to read as 3.5.0 plus the fork's feature, not as 3.5.0 plus
# upstream's own changes counted a second time.
git checkout -q main
print -r -- "// upstream fix" > Sources/Vorssaint/Core/Upstream.swift
release 3.5.0 90
git add -A
git commit -qm "chore: release 3.5.0"
git checkout -q fork
git merge -q --no-edit main
read -r version build tree <<< "$(planned)"
check "$version $build" "3.6.0 91" \
    "a newer release merged in is measured from again, and the build number never goes back"

# The recipe runs the script, not its functions, so the way it finds its own
# repository has to hold from any working directory.
mkdir -p Tools
command cp "$script" Tools/deploy-version.sh
read -r version build tree <<< "$(cd / && "$repo/Tools/deploy-version.sh" plan 2>/dev/null)"
check "$version $build" "3.6.0 91" "the script finds its repository wherever it is run from"

print 'DEPLOY VERSION TESTS OK'
