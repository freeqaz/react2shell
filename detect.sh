#!/bin/bash
# detect.sh - Non-destructive detection probe for CVE-2025-55182 / CVE-2025-66478
#
# Based on Searchlight/Assetnote high-fidelity detection mechanism.
# This does NOT execute code - it only triggers a distinguishable error on vulnerable servers.
#
# Usage: ./detect.sh [TARGET_URL]
# Example: ./detect.sh http://localhost:3000
#
# Detection logic:
# - Sends ["$1:a:a"] referencing an empty object {}
# - Vulnerable servers: {}.a.a -> (undefined).a -> throws -> HTTP 500 + E{"digest"
# - Patched servers: hasOwnProperty check prevents the crash

set -e

# Default to the port our vulnerable server is running on
TARGET="${1:-http://localhost:3443}"

BOUNDARY="----WebKitFormBoundaryx8jO2oVc6SWP3Sad"

# Detection payload:
# Part 1: Empty object {}
# Part 0: ["$1:a:a"] - tries to access {}.a.a which throws on vulnerable servers
BODY=$(cat <<EOF
--${BOUNDARY}
Content-Disposition: form-data; name="1"

{}
--${BOUNDARY}
Content-Disposition: form-data; name="0"

["\$1:a:a"]
--${BOUNDARY}--
EOF
)

echo "[*] React2Shell Detection Probe (CVE-2025-55182 / CVE-2025-66478)"
echo "[*] Target: ${TARGET}"
echo ""

# Send the detection probe
RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST "${TARGET}" \
    -H "Next-Action: x" \
    -H "Content-Type: multipart/form-data; boundary=${BOUNDARY}" \
    --data-binary "${BODY}" \
    2>&1)

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY_RESPONSE=$(echo "$RESPONSE" | sed '$d')

echo "[*] HTTP Status: ${HTTP_CODE}"

# Check for vulnerability signature: HTTP 500 + E{"digest" in response
if [[ "${HTTP_CODE}" == "500" ]] && echo "${BODY_RESPONSE}" | grep -q 'E{"digest"'; then
    echo "[!] VULNERABLE - Server returned 500 with E{\"digest\" pattern"
    echo ""
    echo "[*] Response body:"
    echo "${BODY_RESPONSE}"
    echo ""
    echo "[!] This server is running a vulnerable version of React RSC / Next.js"
    echo "[!] Upgrade to Next.js 16.0.7+ or React 19.2.1+ immediately"
    exit 1
elif [[ "${HTTP_CODE}" == "500" ]]; then
    echo "[?] UNKNOWN - Server returned 500 but without expected pattern"
    echo "[*] Response body:"
    echo "${BODY_RESPONSE}"
    exit 2
else
    echo "[+] NOT VULNERABLE - Server did not return expected error pattern"
    echo "[*] HTTP ${HTTP_CODE} response indicates patched or non-RSC server"
    exit 0
fi
