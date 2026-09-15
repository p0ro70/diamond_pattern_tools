#!/usr/bin/env bash
if [ "$1" = "-h"  -o "$1" = "--help" ]     # Request help.
then
    echo; echo "Use: $0 [diamond_address] [rpc_url] [chain_id] [etherscan_api_key] [out_dir]"; echo
    sed --silent -e '/DOCUMENTATIONXX$/,/^DOCUMENTATIONXX$/p' "$0" |
        sed -e '/DOCUMENTATIONXX$/d'; exit $DOC_REQUEST; fi


: <<DOCUMENTATIONXX
Generates a human readable ABI for a diammond pattern contract.
---------------------------------------------------------------
It will fetch the output of the contract's 'facets()' loupe method,
obtain the  ABI for every facet contract and match it against the included
selectors. Output will be stored in OUT_DIR.

DOCUMENTATIONXX


set -euo pipefail

DIAMOND="${1:-0x1231deb6f5749ef6ce6943a275a1d3e7486f4eae}"
RPC="${2:-https://eth.llamarpc.com}"
CHAIN_ID="${3:-1}"
ETHERSCAN_API_KEY="${4:?Etherscan API key is required.}"
OUT_DIR="${5:-facet_abis}"

mkdir -p "$OUT_DIR"

cast call "$DIAMOND" "facets()((address,bytes4[])[])" \
  --rpc-url "$RPC" --json > facets.json

jq -c '.[0][]' facets.json | while read -r facet; do
  addr=$(jq -r '.[0]' <<<"$facet")
  selectors=$(jq -r '.[1][]' <<<"$facet")

  echo "== $addr =="

  response=$(curl -s "https://api.etherscan.io/v2/api?chainid=${CHAIN_ID}&module=contract&action=getabi&address=${addr}&apikey=${ETHERSCAN_API_KEY}")
  status=$(jq -r '.status' <<<"$response")

  if [[ "$status" != "1" ]]; then
    echo "  ! unverified or error: $(jq -r '.result' <<<"$response")"
    continue
  fi

  abi=$(jq -r '.result' <<<"$response")
  echo "$abi" > "$OUT_DIR/${addr}.json"

  jq -c '.[] | select(.type=="function")' <<<"$abi" | while read -r fn; do
    name=$(jq -r '.name' <<<"$fn")
    types=$(jq -r '
      def canon_type:
        if (.type | test("^tuple")) then
          "(" + ([.components[] | canon_type] | join(",")) + ")" + (.type | sub("^tuple";""))
        else
          .type
        end;
      [.inputs[] | canon_type] | join(",")
    ' <<<"$fn")
    sel=$(cast sig "${name}(${types})")
    if grep -qi "^${sel}$" <<<"$selectors"; then
      echo "  $sel  ${name}(${types})"
    fi
  done
done
