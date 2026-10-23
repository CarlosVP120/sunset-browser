# Security Policy

A browser handles passwords, cookies and everything people do online, so we take security reports seriously.

## Supported versions

Sunset is young and moves fast. Security fixes go into the latest release only.

| Version | Supported |
|---|---|
| Latest release | Yes |
| Older releases | No |

## Reporting a vulnerability

**Please don't open a public issue for security problems.**

Report it privately through GitHub: go to the [Security tab](https://github.com/CarlosVP120/sunset-browser/security/advisories/new) and choose **Report a vulnerability**. Include:

- what the issue is and what an attacker could do with it,
- steps or a proof of concept to reproduce it,
- the Sunset version and macOS version you tested.

You can expect an acknowledgment within a few days. We'll keep you updated while we work on a fix, and credit you in the release notes if you'd like.

## Scope

In scope: the Sunset app and its scripts in this repository. For example, the password vault and autofill, the browser import, injected scripts, extension handling and anything that could expose user data.

Out of scope: vulnerabilities in WebKit or macOS themselves. Please report those to [Apple](https://security.apple.com/).
