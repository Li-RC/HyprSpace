#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

resources="${1:?Usage: check-bundled-licenses.sh APP_PATH}/Contents/Resources"
cmp LICENSE.txt "$resources/LICENSE.txt"
while IFS= read -r -d '' notice; do
    cmp "$notice" "$resources/$notice"
done < <(find legal \( -type f -o -type l \) -print0)
