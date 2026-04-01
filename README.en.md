# AD Server Local Group Report

Monorepo with two localized editions of the same PowerShell solution for auditing Windows Server local-group membership.

## Repository Layout

- [en/](./en/): full English edition
- [ru/](./ru/): full Russian edition
- [LICENSE](./LICENSE): shared MIT license

## What Is Inside Each Edition

Each edition contains its own:

- user-facing entry scripts
- localized help text
- localized runtime messages and logs
- documentation
- module manifest and implementation

The business logic is equivalent, while operator-facing text is localized for the chosen audience.

## Recommended Entry Points

English edition:

- [en/Start-ServerLocalGroupReport.ps1](./en/Start-ServerLocalGroupReport.ps1)

Russian edition:

- [ru/Start-ServerLocalGroupReport.ps1](./ru/Start-ServerLocalGroupReport.ps1)

Legacy compatibility wrappers are also kept in both editions.

## Optional Development Tooling

The delivered repository is intentionally kept compact and does not include the test suite or quality-runner scripts.

If you plan to extend or validate the project further, the following tools are recommended but not required for normal
operator use:

```powershell
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
Install-Module -Name Pester -RequiredVersion 5.7.1 -Scope CurrentUser -Force -SkipPublisherCheck
Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Force
```

## Publishing Strategy

This repository is intended to avoid maintaining separate Git repositories only because of language differences.

Use this structure when you want:

- one issue tracker
- one release flow
- one license
- one star/fork history
- two operator-facing language editions

## License

Distributed under the MIT License. See [LICENSE](./LICENSE).
