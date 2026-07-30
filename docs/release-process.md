# Release Process

`open-homelab` uses GitHub Releases managed by Release Please.

The workflow runs on pushes to `main`. It reads Conventional Commit messages, opens or updates a release pull request, and publishes the GitHub Release when that release PR is merged.

## Semver Rules

Use Conventional Commit subjects:

```text
fix: correct OpenBao bootstrap retry
feat: add Satisfactory workload
docs: clarify local DNS setup
chore: update issue templates
feat!: change platform hostname layout
```

Version impact:

- `fix:` creates a patch release, such as `v0.1.1`
- `feat:` creates a minor release, such as `v0.2.0`
- `feat!:` or `BREAKING CHANGE:` creates a major release
- `docs:` and `chore:` do not force a release by themselves

## Normal Flow

1. Merge feature, fix, or docs PRs to `main` using Conventional Commit-style squash messages.
2. The `Release Please` workflow opens or updates a release PR.
3. Review the generated `CHANGELOG.md` and `.release-please-manifest.json` changes.
4. Merge the release PR.
5. Release Please creates the semver tag and GitHub Release.

The current baseline is `v0.1.0`.

## Manual Rerun

If the workflow needs to be rerun, use the `Release Please` workflow's manual dispatch in GitHub Actions.

## Inspect Releases

```bash
git fetch --tags
git tag --list 'v*' --sort=-v:refname
git log --oneline v0.1.0..v0.2.0
git diff v0.1.0..v0.2.0
```

GitHub Releases are published at:

```text
https://github.com/open-homelab-io/open-homelab/releases
```
