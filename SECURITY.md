# Security Policy

## Supported versions

Only the latest release gets security fixes. Macotron updates itself through Sparkle, so staying current means accepting the update when it's offered.

## Reporting a vulnerability

Please report vulnerabilities privately through [GitHub's private vulnerability reporting](https://github.com/statico/macotron/security/advisories/new). Do not open a public issue.

Include what you can: the Macotron version, the macOS version, steps or a plugin that reproduces it, and what an attacker gains.

Macotron is maintained by one person, so responses are best effort. Expect an acknowledgment within a week. Once a fix ships, the advisory is published and you're credited unless you'd rather not be.

## Scope

In scope:

- The Macotron app and its system helper
- The built-in plugins in `Examples/plugins`
- The update path: the appcast, signature checks and Sparkle
- Plugin trust: the hash ledger, the source scan and the blocklist (`blocked.json`)
- The website at [macotron.statico.io](https://macotron.statico.io)

Out of scope:

- What a plugin you enabled does with the access it asks for. Enabling a plugin trusts it, and `macotron.shell.run` runs any command by design. See [docs/06-security.md](docs/06-security.md).
- Attacks that need an attacker who already has your user account or admin rights
- Third-party services that plugins call

## Malicious plugins

If you find a plugin in the wild that steals data or runs hidden code, report it the same way. Include where it's published and its SHA-256 hash. Known-bad hashes go into the blocklist, which every copy of Macotron checks before it runs a plugin.
