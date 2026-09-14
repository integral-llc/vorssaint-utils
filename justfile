# Vorssaint local deploy. Run `just` to list recipes.
#
# Packaging and signing stay in build.sh and the version arithmetic in
# Tools/deploy-version.sh; these recipes only put the two together, so how the
# app is built still has one source of truth.

app_name := "Vorssaint"
install_dir := env_var("HOME") / "Applications"
installed := install_dir / (app_name + ".app")

# List available recipes
default:
    @just --list

# Show what the next deploy would be numbered and why; builds and records nothing
version *level:
    @Tools/deploy-version.sh plan {{level}} >/dev/null

# The level comes from what changed since the last deploy, see
# Tools/deploy-version.sh. Force one with `just deploy patch|minor|major`.
#
# Bump the version, build, sign with your certificate and install to ~/Applications
deploy *level:
    #!/bin/zsh
    set -euo pipefail
    identity="$(Tools/deploy-version.sh identity)"
    plan="$(Tools/deploy-version.sh plan {{level}})"
    read -r version build tree <<< "$plan"
    VORSSAINT_SIGNING_IDENTITY="$identity" \
    VORSSAINT_INSTALL_DIR="{{install_dir}}" \
    VORSSAINT_MARKETING_VERSION="$version" \
    VORSSAINT_BUILD_NUMBER="$build" \
        ./build.sh --install
    # Only a deploy that landed moves the baseline, so a failed build leaves
    # the next attempt numbered the same.
    Tools/deploy-version.sh record "$version" "$build" "$tree"
    open "{{installed}}"
    echo "Deployed {{app_name}} $version ($build) to {{installed}}"
