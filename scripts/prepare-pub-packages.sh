#!/usr/bin/env bash
# Prepares patched copies of pub.dev packages under build/, selected by
# pubspec_overrides.yaml.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)

prepare() {
    local name=$1 version=$2 archive_sha256=$3 patch="$root/patches/$4"
    local destination="$root/build/${name//_/-}"
    local relative=${destination#"$root/"}

    if [[ -e "$destination" ]]; then
        if [[ -f "$destination/.fluffychat-archive.sha256" ]] &&
            [[ "$(cat "$destination/.fluffychat-archive.sha256")" == "$archive_sha256" ]] &&
            git -C "$root" apply --directory="$relative" --reverse --check "$patch"; then
            echo "Patched $name is already prepared."
            return
        fi
        echo "Refusing to replace existing $destination; move it aside first." >&2
        exit 1
    fi

    temporary=$(mktemp -d "$destination.XXXXXX")
    trap 'rm -rf "$temporary"' EXIT
    curl --fail --silent --show-error --location --output "$temporary/archive.tar.gz" \
        "https://pub.dev/api/archives/$name-$version.tar.gz"
    echo "$archive_sha256  $temporary/archive.tar.gz" | sha256sum --check --quiet
    mkdir "$temporary/package"
    tar -xzf "$temporary/archive.tar.gz" -C "$temporary/package"
    git -C "$root" apply --directory="${temporary#"$root/"}/package" --check "$patch"
    git -C "$root" apply --directory="${temporary#"$root/"}/package" "$patch"
    printf '%s\n' "$archive_sha256" > "$temporary/package/.fluffychat-archive.sha256"
    mv "$temporary/package" "$destination"
    rm -rf "$temporary"
    trap - EXIT
    echo "Prepared patched $name at $destination."
}

mkdir -p "$root/build"
prepare flutter_vodozemac 0.8.1 \
    209e7661da113a5f889ae55d574c48f245145def64df9a9fcac04d147e6f9d4e \
    flutter-vodozemac-compile-sdk.patch
prepare flutter_shortcuts_new 2.0.0 \
    16ee1c8a9bc9586b5117ebb774a8ff6b396f856743e97251eb483c4dc5769d7f \
    flutter-shortcuts-new-compile-sdk.patch
