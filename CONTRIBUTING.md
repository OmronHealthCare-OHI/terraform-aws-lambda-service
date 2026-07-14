# Contributing

## Versioning and releases

Semantic versioning. Git tags have **no `v` prefix** (for example `0.1.0`). On
each release the moving tags `0` (major), `0.1` (minor), and `latest` are moved
to the release too, so consumers can pin at the level they want.

Consumers pin a tag and never reference `main`:

```hcl
source = "github.com/OmronHealthCare-OHI/terraform-aws-lambda-service?ref=0.1.0"
```

You can also pin a moving tag (`?ref=0`, `?ref=0.1`, or `?ref=latest`) for
automatic updates at that level. While the module is in `0.x`, minor releases
may still break, so prefer exact pins until `1.0.0`.

- **MAJOR**: breaking. A removed or renamed variable or output, or a change that
  forces resource replacement or a provider major bump.
- **MINOR**: backwards compatible additions (a new optional variable or output).
- **PATCH**: backwards compatible fixes.

## How a release happens

1. Open a PR. The labeler adds a `version: major|minor|patch` label from your
   branch name or PR title. Add or correct it if needed.
2. Merge to `main`. Release Drafter keeps a draft release updated with the next
   version and the notes.
3. Publish the draft in the Releases tab. That creates the version tag, and the
   moving `major` / `minor` / `latest` tags follow automatically.

The version bump is read from labels:
- `version: major` (or a `feat!:` / `fix!:` PR title)
- `version: minor` (a `feat:` PR title)
- `version: patch` (a `fix:` or `chore:` PR title, or `bug` / `dependencies`)

## Commit and PR conventions

Use [Conventional Commits](https://www.conventionalcommits.org):
`type(scope): summary`. Types: `feat` (minor), `fix` (patch),
`docs` / `chore` / `ci` / `refactor` / `test` / `build` (patch or none), and any
type with `!` or a `BREAKING CHANGE:` footer (major).

- Keep the subject short, imperative, lowercase, no trailing period.
- The PR title becomes the changelog line, so keep it clean.
- Squash-merge so `main` keeps one commit per PR.

## Checks on every PR

`pull-request.yml` runs the labeler and `validate.yml`, which runs
`terraform fmt`, `init`, `validate`, `terraform test`, and Checkov (config in
`.checkov-config.yml`). Keep the code formatted with `terraform fmt` and the
tests green.
