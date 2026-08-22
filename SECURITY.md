# Security Policy

## Supported versions

Companion is in active pre-1.0 development. Only the latest commit on `main`
receives security fixes. There are no maintained release branches yet.

## Reporting a vulnerability

**Do not open a public issue for security reports.**

Use GitHub's private vulnerability reporting instead:

1. Go to the [Security tab](https://github.com/karenrebecag/Companion/security)
2. Click **Report a vulnerability**
3. Describe the issue, the affected version or commit, and reproduction steps

You will get an acknowledgement within 7 days. Because this is a personal
project maintained by one person, a fix may take longer — the report stays
private until a patch is available and you are credited in the advisory unless
you ask otherwise.

## Scope

Companion is a native macOS app that records audio, talks to third-party model
providers, and can delegate work to an agent with access to your files and
terminal. Reports that are in scope include:

- Credential or API key leakage (keychain handling, logs, crash reports)
- Command injection or path traversal through the agent's file and terminal access
- Prompt injection that escalates into arbitrary command execution
- Audio or transcript data sent to an endpoint the user did not configure
- Dependency vulnerabilities reachable from Companion's own code paths

Out of scope:

- Vulnerabilities in the model providers' own services
- Issues that require an attacker to already have local admin on the machine
- Missing hardening that has no demonstrated impact

## Secrets

If you find a credential committed to this repository, report it privately
through the process above rather than opening an issue, so it can be rotated
before it is publicised.
