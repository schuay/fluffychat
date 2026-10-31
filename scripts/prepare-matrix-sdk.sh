#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
source_repo=${1:?Usage: scripts/prepare-matrix-sdk.sh /path/to/matrix-dart-sdk}
base=b325fb82049b9ad656682e59f57bd1b31ba33813
patch="$root/patches/matrix-sdk-token-refresh.patch"
destination="$root/build/matrix-sdk"

git -C "$source_repo" cat-file -e "$base^{commit}"

if [[ -e "$destination" ]]; then
    if [[ -f "$destination/.fluffychat-base" ]] &&
        [[ "$(cat "$destination/.fluffychat-base")" == "$base" ]] &&
        [[ -f "$destination/.fluffychat-source.sha256" ]] &&
        (cd "$destination" && sha256sum --check --quiet .fluffychat-source.sha256) &&
        git -C "$root" apply --directory=build/matrix-sdk --reverse --check "$patch"; then
        echo "Patched Matrix SDK is already prepared."
        exit 0
    fi
    echo "Refusing to replace existing $destination; move it aside first." >&2
    exit 1
fi

mkdir -p "$root/build"
temporary=$(mktemp -d "$root/build/matrix-sdk.XXXXXX")
trap 'rm -rf "$temporary"' EXIT
git -C "$source_repo" archive "$base" | tar -x -C "$temporary"
git -C "$root" apply --directory="${temporary#"$root/"}" --check "$patch"
git -C "$root" apply --directory="${temporary#"$root/"}" "$patch"
printf '%s\n' "$base" > "$temporary/.fluffychat-base"
(cd "$temporary" && find . -type f ! -name .fluffychat-source.sha256 -print0 |
    sort -z | xargs -0 sha256sum > .fluffychat-source.sha256)
mv "$temporary" "$destination"
echo "Prepared patched Matrix SDK at $destination."
