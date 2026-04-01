# Contributing

Thanks for your interest in improving this project.

## Scope

This repository contains two localized editions of the same PowerShell tool:

- `en/` for English operator-facing usage
- `ru/` for Russian operator-facing usage

Please keep functional changes aligned across both editions unless the change is intentionally language-specific.

## Before You Open A Pull Request

1. Keep behavior changes minimal and reviewable.
2. Preserve compatibility with mixed Windows Server environments where practical.
3. Update both language editions when the underlying logic changes.
4. Update user-facing documentation when parameters, outputs, or behavior change.

## Development Notes

- PowerShell `5.1` compatibility matters for the operator entry points.
- PowerShell `7+` should continue to work where parallel behavior is available.
- Avoid destructive git operations and avoid introducing environment-specific secrets or internal server names.

## Pull Request Guidelines

- Describe the problem and the operational impact.
- Summarize the change at a high level.
- Mention any compatibility implications.
- Include manual validation notes when applicable.

## Issues

Use the issue templates when reporting bugs or requesting features.
