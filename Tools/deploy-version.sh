#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint

# Numbers a local deploy.
#
# Resources/Info.plist carries the release's version, which belongs to the
# release process and is pinned by the test suite, so a deploy never writes it.
# build.sh stamps the number worked out here into the bundle it builds instead,
# and the last number deployed is kept in .deploy-state (ignored by git).
#
#   plan [auto|patch|minor|major]    print "<version> <build> <tree>", write nothing
#   record <version> <build> <tree>  remember a deploy that landed
#   identity                         print the signing identity to use
#
# Unless a level is forced, it comes from the difference between the tree last
# deployed and the working tree now, uncommitted work included. Measuring trees
# rather than commit messages is what keeps a change from counting twice:
# committing something already deployed leaves the tree as it was.
#
#   an AppFeature case removed                   major, its saved availability key breaks
#   an AppFeature case added                     minor, a feature by the app's own catalog
#   any other change under Sources or Resources  patch
#   any other change at all                      build number only
#   no change                                    nothing
#
# The first deploy, and the first after a newer release is merged in, is
# measured from the commit that set the release version, so the number reads
# as that release plus what this checkout adds to it.

set -euo pipefail

# Read here rather than in main: inside a zsh function $0 is the function's
# name, not this file's path.
REPO_ROOT="${0:A:h:h}"
PLIST="Resources/Info.plist"
CATALOG="Sources/Vorssaint/Core/FeatureCatalog.swift"
STATE=".deploy-state"
# Nothing else references the deployed tree, and git's garbage collection
# would eventually delete it and quietly send the next deploy back to the
# release baseline.
BASELINE_REF="refs/deploy/baseline"
VERSION_PATTERN='^[0-9]+\.[0-9]+\.[0-9]+$'
BUILD_PATTERN='^[0-9]+$'

plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST"
}

state_value() {
    [[ -f "$STATE" ]] || return 0
    sed -n "s/^$1=//p" "$STATE" | head -1
}

# The working tree as a tree object, tracked and untracked files alike with
# .gitignore honoured, built in a scratch index so the real one is untouched.
snapshot_tree() {
    local scratch tree
    scratch="$(mktemp -d)"
    GIT_INDEX_FILE="$scratch/index" git read-tree HEAD
    GIT_INDEX_FILE="$scratch/index" git add -A
    tree="$(GIT_INDEX_FILE="$scratch/index" git write-tree)"
    command rm -rf "$scratch"
    print -r -- "$tree"
}

# The AppFeature case names in a FeatureCatalog.swift read on stdin, sorted.
feature_cases() {
    awk '/^enum AppFeature[: {]/ { inside = 1; next }
         inside && /^}/ { exit }
         inside { sub(/\/\/.*/, ""); print }' \
        | tr ',' '\n' \
        | sed -E 's/^[[:space:]]+//; s/^case[[:space:]]+//; s/[[:space:]]+$//' \
        | { grep -E '^[A-Za-z_][A-Za-z0-9_]*$' || true; } \
        | LC_ALL=C sort -u
}

catalog_cases() {
    { git show "$1:$CATALOG" 2>/dev/null || true; } | feature_cases
}

# "<level>|<detail>" for the change from one tree to another.
classify() {
    local from="$1" to="$2" paths before after gone added count
    paths="$(git diff --name-only "$from" "$to")"
    if [[ -z "$paths" ]]; then
        print -r -- "unchanged|nothing changed"
        return
    fi
    before="$(catalog_cases "$from")"
    after="$(catalog_cases "$to")"
    # A catalog missing on either side, moved or not yet written, says nothing
    # about features, so only two real readings are compared.
    if [[ -n "$before" && -n "$after" ]]; then
        gone="$(LC_ALL=C comm -23 <(print -r -- "$before") <(print -r -- "$after"))"
        added="$(LC_ALL=C comm -13 <(print -r -- "$before") <(print -r -- "$after"))"
        if [[ -n "$gone" ]]; then
            print -r -- "major|AppFeature loses ${(j:, :)${(f)gone}}"
            return
        fi
        if [[ -n "$added" ]]; then
            print -r -- "minor|AppFeature gains ${(j:, :)${(f)added}}"
            return
        fi
    fi
    count="$(print -r -- "$paths" | grep -cE '^(Sources|Resources)/' || true)"
    if (( count > 0 )); then
        print -r -- "patch|$count source or resource files changed"
        return
    fi
    count="$(print -r -- "$paths" | wc -l | tr -d ' ')"
    print -r -- "build|$count files changed outside Sources and Resources"
}

larger_version() {
    local -a a b
    local i
    a=("${(@s:.:)1}")
    b=("${(@s:.:)2}")
    for i in 1 2 3; do
        if (( ${a[i]:-0} != ${b[i]:-0} )); then
            if (( ${a[i]:-0} > ${b[i]:-0} )); then print -r -- "$1"; else print -r -- "$2"; fi
            return
        fi
    done
    print -r -- "$1"
}

bump() {
    local -a parts
    parts=("${(@s:.:)1}")
    local major="${parts[1]:-0}" minor="${parts[2]:-0}" patch="${parts[3]:-0}"
    case "$2" in
        major) major=$((major + 1)); minor=0; patch=0 ;;
        minor) minor=$((minor + 1)); patch=0 ;;
        patch) patch=$((patch + 1)) ;;
        build|unchanged) ;;
        *) print -u2 -r -- "deploy-version: unknown level '$2'"; return 1 ;;
    esac
    print -r -- "$major.$minor.$patch"
}

# The tree of the commit that set a release version. HEAD stands in when the
# history does not say.
release_baseline() {
    local commit
    commit="$(git log -1 --format=%H -S"<string>$1</string>" -- "$PLIST" 2>/dev/null || true)"
    git rev-parse "${commit:-HEAD}^{tree}"
}

plan() {
    local forced="${1:-auto}"
    case "$forced" in
        auto|patch|minor|major) ;;
        *)
            print -u2 -r -- "deploy-version: unknown level '$forced' (use patch, minor or major)"
            return 1
            ;;
    esac

    local release_version release_build last_version last_build last_tree
    release_version="$(plist_value CFBundleShortVersionString)"
    release_build="$(plist_value CFBundleVersion)"
    last_version="$(state_value version)"
    last_build="$(state_value build)"
    last_tree="$(state_value tree)"

    local newer_release=0
    if [[ -n "$last_version" && "$release_version" != "$last_version" \
          && "$(larger_version "$release_version" "$last_version")" == "$release_version" ]]; then
        newer_release=1
    fi

    local from since
    if (( ! newer_release )) && [[ -n "$last_tree" ]] \
        && git cat-file -e "$last_tree^{tree}" 2>/dev/null; then
        from="$last_tree"
        since="since the last deploy, $last_version ($last_build)"
    else
        from="$(release_baseline "$release_version")"
        since="since the $release_version release"
    fi

    local tree base_version base_build
    tree="$(snapshot_tree)"
    base_version="$(larger_version "$release_version" "${last_version:-0.0.0}")"
    # LaunchServices picks between copies by build number, so it never goes
    # back, not even across a merged release.
    base_build=$(( release_build > ${last_build:-0} ? release_build : ${last_build:-0} ))

    local detected level summary
    detected="$(classify "$from" "$tree")"
    level="${detected%%|*}"
    summary="$level: ${detected#*|}"
    if [[ "$forced" != auto ]]; then
        summary="$forced, forced; on its own this reads as $summary"
        level="$forced"
    fi

    local version build
    case "$level" in
        unchanged) version="$base_version"; build="$base_build" ;;
        build) version="$base_version"; build=$(( base_build + 1 )) ;;
        *) version="$(bump "$base_version" "$level")"; build=$(( base_build + 1 )) ;;
    esac

    print -u2 -r -- "Version $base_version ($base_build) -> $version ($build)"
    print -u2 -r -- "  $summary, $since"
    print -r -- "$version $build $tree"
}

record() {
    local version="${1:-}" build="${2:-}" tree="${3:-}"
    if [[ ! "$version" =~ $VERSION_PATTERN || ! "$build" =~ $BUILD_PATTERN ]]; then
        print -u2 -r -- "deploy-version: record needs a version like 1.2.3 and a whole build number"
        return 1
    fi
    if ! git cat-file -e "$tree^{tree}" 2>/dev/null; then
        print -u2 -r -- "deploy-version: '$tree' is not a tree in this repository"
        return 1
    fi
    git update-ref "$BASELINE_REF" "$tree"
    print -r -- "version=$version
build=$build
tree=$tree" > "$STATE.tmp"
    command mv "$STATE.tmp" "$STATE"
}

# A Developer ID if there is one, else an Apple Development certificate, by
# hash so two certificates sharing a name cannot make codesign guess. An ad-hoc
# signature changes on every build and orphans the Accessibility and Screen
# Recording grants, so having neither is an error rather than a fallback.
identity() {
    if [[ -n "${VORSSAINT_SIGNING_IDENTITY:-}" ]]; then
        print -r -- "$VORSSAINT_SIGNING_IDENTITY"
        return
    fi
    local listing line kind
    listing="$(security find-identity -v -p codesigning 2>/dev/null || true)"
    for kind in "Developer ID Application" "Apple Development"; do
        line="$(print -r -- "$listing" | grep -F "\"$kind: " | head -1 || true)"
        if [[ -n "$line" ]]; then
            print -u2 -r -- "Signing as ${${line#*\"}%\"}"
            print -r -- "$line" | awk '{ print $2 }'
            return
        fi
    done
    print -u2 -r -- "deploy-version: no Developer ID or Apple Development certificate in the keychain."
    print -u2 -r -- "  Name one with VORSSAINT_SIGNING_IDENTITY; an ad-hoc signature would lose"
    print -u2 -r -- "  the Accessibility and Screen Recording grants on every deploy."
    return 1
}

main() {
    cd "$REPO_ROOT"
    local command="${1:-}"
    shift $(( $# > 0 ? 1 : 0 ))
    case "$command" in
        plan) plan "$@" ;;
        record) record "$@" ;;
        identity) identity ;;
        *)
            print -u2 -r -- "usage: Tools/deploy-version.sh plan [patch|minor|major] | record <version> <build> <tree> | identity"
            return 2
            ;;
    esac
}

if [[ "$ZSH_EVAL_CONTEXT" == toplevel ]]; then
    main "$@"
fi
