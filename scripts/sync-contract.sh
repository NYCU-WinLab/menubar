#!/bin/sh
# Pulls the portal API contract and regenerates the Swift types.
#   scripts/sync-contract.sh            from portal's main branch on GitHub
#   scripts/sync-contract.sh <file>     from a local contract/actions.json
set -eu
cd "$(dirname "$0")/.."
source=${1:-}
if [ -z "$source" ]; then
  source=$(mktemp)
  trap 'rm -f "$source"' EXIT
  curl -fsSL https://raw.githubusercontent.com/NYCU-WinLab/portal/main/contract/actions.json -o "$source"
fi
swift run --quiet ContractGen sync "$source"
