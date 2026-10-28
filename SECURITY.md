# Security policy

## Report a vulnerability

Use [GitHub's private vulnerability reporting form](https://github.com/fberrez/openfirewall/security/advisories/new) for issues that could bypass rules, impersonate an app, change policy without authorization, or expose private connection data.

Include the affected commit, macOS version, signing/build setup, reproduction steps, expected behavior, and observed result. A minimal test app is useful. Remove private keys, provisioning profiles, credentials, and personal network history from reports.

Keep exploitable details out of public issues until a fix or coordinated disclosure is ready. Ordinary interface and build bugs can use the public bug-report form.

## Support scope

OpenFirewall is in early development. Security fixes are targeted at the latest `main` branch. There is no stable binary release or guaranteed response time yet.

The current test coverage and unqualified scenarios are documented in [VERIFY.md](VERIFY.md). In particular, the project does not claim fail-closed behavior during a provider crash or full coverage of every macOS network path.
