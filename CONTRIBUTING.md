# Contributing

Start with an issue for a substantial feature or a change to the identity or enforcement model. For a small fix, a focused pull request is welcome. See the [build guide](docs/building.md) and [architecture notes](docs/architecture.md).

Use original code and public macOS APIs. Do not add proprietary code, extracted assets, or dependencies without a compatible license.

Run these checks before proposing a change:

```sh
swift test
bash Scripts/test-identity.sh
bash Scripts/build.sh
```

Keep policy and history logic in `Sources/Core`. Keep process attribution and IPC authentication in `Sources/Shared`. UI preview mode must never activate the filter or publish sample rules.

Write tests for behavior that could grant or deny the wrong app, lose persisted rules, accept an unauthorized control connection, or exhaust resources. Keep history and flow tracking bounded. Describe the signed-device checks performed for provider changes.

Do not commit signing certificates, private keys, provisioning profiles, personal team settings, or real connection histories. Code changes that alter filtering behavior need corresponding updates in `VERIFY.md` and the README.

## Pull requests

Describe the problem, the resulting behavior, and the checks you ran. Distinguish unit tests, preview checks, and real signed-device tests. Redact personal paths and destinations from shared diagnostics. Keep unrelated changes in separate pull requests.

`project.yml` is the source of truth for the Xcode project. Generate the checked-in project without personal signing environment variables. CI builds without a signing identity; it does not prove live enforcement.

Keep discussion respectful and focused on the work. Report exploitable security issues through [private vulnerability reporting](SECURITY.md), rather than a public issue.

By contributing, you agree that your contribution is provided under the repository's [MIT license](LICENSE). No contributor license agreement is required.
