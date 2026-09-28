# proxyctl

A single POSIX shell script for managing proxy environment variables in the current shell.

```sh
source ./proxyctl set http://proxy.example.com:8080
source ./proxyctl unset --http-proxy
source ./proxyctl status
./proxyctl --help
```

Manages six variables: `HTTP_PROXY`, `HTTPS_PROXY`, `http_proxy`, `https_proxy`, `ALL_PROXY`, `all_proxy`. `NO_PROXY` is never touched.

## Why

I change these variables all the time, switching between a proxy, a direct connection, and a SOCKS tunnel... Typing `export HTTP_PROXY=... HTTPS_PROXY=...` every time was slow and annoying. This script gives me one command to set, unset, or check them all.

## Commands

| Command | What it does |
|---|---|
| `source ./proxyctl set URL [--all-proxy URL]` | Sets all six variables; `--all-proxy` separates the ALL value |
| `source ./proxyctl unset OPTION...` | Selective unset (`--http-proxy`, `--https-proxy`, `--all-proxy`) or `-a` for all six |
| `source ./proxyctl status` | Prints current proxy environment (`env \| grep -i proxy`) |
| `./proxyctl --help` | Shows help (no sourcing needed) |

## Notes

- Must be **sourced** for `set`/`unset`/`status` — operational commands run directly are rejected.
- URL validation is syntactic only (scheme, host, optional port); no DNS or connectivity checks.
- POSIX `sh` compatible — works with `dash`, `bash`, `zsh`, `ksh`.

## Vibe-coding disclosure

This script was built by iterating with an AI-agent against a spec file. The agent wrote and fixed the script based on explicit requirements.