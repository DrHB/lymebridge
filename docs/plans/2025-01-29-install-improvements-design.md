# Lymebridge Install Improvements Design

**Date:** 2025-01-29
**Status:** Approved

## Goal

Simplify installation and usage:
- One-line install via `curl`
- Single binary for all commands (no separate shell scripts)

## Changes

### Before vs After

| What | Before | After |
|------|--------|-------|
| Install | `git clone` + `./install.sh` | `curl ... \| bash` |
| Connect | `./bridge-client.sh imessage work1` | `lymebridge connect imessage work1` |
| Files | Separate shell script | All in one binary |

### New CLI Structure

```bash
# Daemon
lymebridge                          # Run daemon (default)
lymebridge daemon                   # Explicit
lymebridge setup                    # Configure

# Client
lymebridge connect <channel> <name> # Connect session
lymebridge connect imessage work1   # Example

# Info
lymebridge version
lymebridge help
```

### One-Line Install

```bash
curl -fsSL https://raw.githubusercontent.com/DrHB/lymebridge/main/install.sh | bash
```

Install script:
1. Detects architecture (arm64 vs x86_64)
2. Downloads pre-built binary from GitHub Releases
3. Installs to `/usr/local/bin/lymebridge`
4. Prints next steps

### Files to Update

1. `Sources/lymebridge/main.swift` - Add `connect` subcommand
2. `install.sh` - Curl-based installer from GitHub Releases
3. `README.md` - Update docs

### No Tests

Manual testing sufficient for v1.

## Implementation Tasks

1. Add `lymebridge connect` subcommand to main.swift
2. Update install.sh for curl-based install
3. Update README.md with new instructions
4. Create GitHub Release with binaries (manual step)
