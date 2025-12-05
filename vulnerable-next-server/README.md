# Vulnerable Next.js Test Server

**This is a deliberately vulnerable Next.js application for testing CVE-2025-55182 (React) and CVE-2025-66478 (Next.js).**

## Purpose

This server provides a safe, isolated environment to test and demonstrate the React Server Components RCE vulnerability. It is locked to vulnerable versions and should **never** be deployed to production or exposed to untrusted networks.

## Vulnerable Versions

| Package | Version |
|---------|---------|
| Next.js | 16.0.6 |
| React | 19.2.0 |
| react-dom | 19.2.0 |

These versions contain the vulnerable Flight protocol deserializer that allows remote code execution via prototype chain traversal.

## Setup

```bash
# Install dependencies
pnpm install

# Start development server (port 3443)
pnpm dev
```

The server runs on **http://localhost:3443** by default.

### Production Mode

To test production error sanitization behavior:

```bash
pnpm build && pnpm start
```

Note: In production mode, error messages are sanitized. The `exploit-throw.sh` method won't capture output, but `exploit-redirect.sh` still works.

## Testing the Vulnerability

From the parent directory:

```bash
# Detection (non-destructive)
./detect.sh http://localhost:3443

# RCE with output capture (recommended)
./exploit-redirect.sh http://localhost:3443 "id"

# Interactive shell
./shell.sh http://localhost:3443
```

See the [main README](../README.md) for full exploit documentation.

## What Makes It Vulnerable?

This is a minimal Next.js App Router application. The vulnerability exists in the underlying React Server Components Flight protocol, meaning:

- **No special configuration required** - Default App Router setup is vulnerable
- **Any route is exploitable** - The vulnerable code path is triggered by `Next-Action` header
- **No authentication bypass needed** - Exploitation occurs before any app logic runs

The attack works by sending a crafted multipart POST request that abuses colon-delimited path resolution (`$1:__proto__:then`) to traverse the prototype chain and reach the JavaScript `Function` constructor.

## Security Warning

- Run only on localhost or isolated networks
- Do not expose to the internet
- For authorized security testing only
