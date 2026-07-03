# Contributing to My_Powershell_Profile

Thank you for your interest in contributing! This document explains how to report bugs, suggest enhancements, and submit pull requests so maintainers can review and merge them quickly.

## Quick checklist

- Search existing issues before opening a new one.
- Keep changes small and focused.
- Add or update tests/examples when appropriate.
- Follow the commit message and code style guidelines below.

## Reporting bugs

Before opening an issue, please search existing issues to avoid duplicates. A good bug report should include:

- A short, descriptive title.
- Steps to reproduce the problem.
- Expected vs actual behavior.
- The operating system and PowerShell version (pwsh --version).
- Any relevant error messages or stack traces.

Tag the issue with `bug` where appropriate.

## Suggesting enhancements

Check the issue tracker for similar requests. When proposing an enhancement, explain the problem it solves and include examples or a short design when applicable.

## Your first code contribution

1. Fork the repository.
2. Create a feature branch from `main` (e.g. `feat/my-feature`).
3. Make your changes in small, well-named commits.
4. Run any tests you added and ensure existing behaviour is not broken.
5. Push your branch and open a Pull Request.

## Pull request checklist

- Use a descriptive title.
- Reference relevant issues in the PR description.
- Describe what changed and why in the PR body.
- Keep PRs small and reviewable.

## Commit message style

- Use present tense: "Add feature" not "Added feature".
- Capitalize the first letter.
- Keep the subject line to 72 characters or less.
- Optionally include a body explaining the motivation and implementation details.

## Code style

- Keep PowerShell functions small and well-documented.
- Validate parameters using `param()` blocks and `Validate*` attributes where appropriate.
- Prefer descriptive variable names and avoid global state.

## Code of conduct

This project follows the Microsoft Open Source Code of Conduct: [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/)

## Getting help

If you need help, open an issue and include the details described above.

Thank you for contributing!
