#!/usr/bin/env bash
# Regenerate test/fixtures/parity from the VS Code extension's TypeScript
# generator. Run this after changing the extension's generator, then port the
# same change to lib/ until `dart test test/parity_test.dart` passes.
#
#   tool/update_parity_goldens.sh <path-to-modular_l10n_extension>
set -euo pipefail

EXT=$(cd "${1:?usage: $0 <path-to-modular_l10n_extension>}" && pwd)
PKG=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
F="$PKG/test/fixtures/parity"

(cd "$EXT" && npx tsc -p . --outDir "$WORK/tsout" --sourceMap false)

rm -rf "$F"
mkdir -p "$F"
for mode in part library; do
  NODE_PATH="$EXT/node_modules" node "$PKG/tool/parity.cjs" "$WORK/tsout" "$WORK/work" "$mode" false
  cp -r "$WORK/work/ts/lib/generated/modular_l10n" "$F/expected_$mode"
  # The suffix keeps analyzers and formatters away: the corpus contains
  # messages that deliberately do not compile.
  find "$F/expected_$mode" -type f -exec mv {} {}.golden \;
done

(cd "$WORK/work/ts" && find lib -name '*.arb' -not -path 'lib/generated/*' -print0 |
  while IFS= read -r -d '' f; do mkdir -p "$F/project/$(dirname "$f")"; cp "$f" "$F/project/$f"; done)
cp "$WORK/work/ts_warnings.txt" "$F/expected_warnings.txt"

# Combined ARBs carry today's date; the parity test pins its clock to match.
TODAY=$(date -u +%Y-%m-%d)
sed -i "s/DateTime.utc([0-9, ]*)/DateTime.utc(${TODAY:0:4}, $((10#${TODAY:5:2})), $((10#${TODAY:8:2})))/" "$PKG/test/parity_test.dart"
echo "Goldens regenerated in $F (dated $TODAY)."
