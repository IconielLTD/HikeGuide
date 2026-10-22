# Security policy

## Supported versions

Only the **latest release** on the
[Releases](https://github.com/IconielLTD/HikeGuide/releases) page gets security
fixes. If you're on an older version, please update first — the fix you're
looking for may already be there.

## Reporting a vulnerability

Please report security problems **privately**, not in a public issue:

1. Go to this repository's **Security** tab.
2. Choose **Report a vulnerability**.
3. Describe the problem, how to reproduce it, and what an attacker could do
   with it. Include the app version (Info tab) and your Android version.

HikeGuide is a small hobby project, so fixes are best-effort, but reports are
taken seriously: you'll get a reply, and confirmed issues are fixed in a new
release and credited in its release notes unless you'd rather not be named.

## What's in scope

- The HikeGuide Android app and its source in this repository.
- The region packs and index files published on this repository's Releases.
- How the app handles the API keys you give it, your location, and what it
  sends to third-party services.

The third-party services themselves — Anthropic, CARTO, Ordnance Survey,
Overpass servers, OpenStreetMap and GitHub — are out of scope; please report
problems with them to their owners.

## Verifying a download

Only install HikeGuide from this repository's Releases page. Every genuine
release is signed with the same key; its certificate fingerprint and how to
check it are in the [README](README.md#install).
