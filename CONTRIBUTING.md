# Coding rules

This part defines all the coding rules that should be respected.

## Format

The code should respect the format defined by Zig.

You can verify your code with `zig fmt --check .` at the root of the project.

## Copyright

Every Zig file must contain the following header:

```zig
// Copyright 2026-$(file.latest_modification_date.year) Rekka contributors
// Licensed under Apache License 2.0 or any later version
// Refer to the LICENSE file included.
```

## Git

### Commits

* Commits should respect [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/) and specific rules defined in `commitlint.config.js`.
* Commits should be [signed](https://docs.github.com/en/authentication/managing-commit-signature-verification/about-commit-signature-verification).
* Changes in commits should be described in [imperative mood](https://www.kernel.org/doc/html/v4.10/process/submitting-patches.html#describe-your-changes).

Do not hesitate to propose scopes not defined in `commitlint.config.js`.
