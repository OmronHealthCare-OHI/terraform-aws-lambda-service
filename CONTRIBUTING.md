# Contributing

## Versioning & releases

Shared Terraform modules, versioned with [Semantic Versioning](https://semver.org)
git tags: `vMAJOR.MINOR.PATCH`. Consumers reference modules by exact tag and
**never** by `main`:

```hcl
source = "github.com/OmronHealthCare-OHI/terraform-aws-lambda-service?ref=v0.1.0"
```

- **MAJOR** — breaking: a removed/renamed variable or output, or a change that
  forces resource replacement or a provider major bump.
- **MINOR** — backwards-compatible additions (new optional variable/output).
- **PATCH** — backwards-compatible fixes.
- **0.x note:** while under `v0`, minor versions may still break; we move to
  `v1.0.0` once the module set is stable and then honour SemVer strictly.

Terraform git sources don't support version ranges, so consumers pin an exact
tag and bump deliberately — the release notes say what an upgrade brings.

### Cutting a release

1. Label each PR `major`/`breaking`, `minor`/`feature`, or `patch`/`fix`.
2. Merge to `main`. **Release Drafter** updates the draft release + notes.
3. Publish the draft in the **Releases** UI → creates the `vX.Y.Z` tag.

### One-time seed (first release)

```bash
git tag v0.1.0 && git push origin v0.1.0
```
## Commit & PR conventions

Releases are driven by the **PR label** (version bump) and **PR title** (the
changelog line) — not by commit messages. But we keep commits consistent too,
using [Conventional Commits](https://www.conventionalcommits.org):

```
<type>(<scope>): <imperative summary>

<why, if not obvious>
```

**Types → release effect:**

| Type | Meaning | Bump |
|------|---------|------|
| `feat` | new capability | minor |
| `fix` | bug fix | patch |
| `docs`, `chore`, `ci`, `refactor`, `test`, `build` | housekeeping | patch / none |
| any type with `!` (e.g. `feat!:`) or a `BREAKING CHANGE:` footer | breaking | major |

**Rules of thumb:**

- Subject line: imperative, lowercase, no trailing period, ~50–72 chars. Put the *why* in the body.
- Reference the tracking issue if you have one (internal maintainers use Linear keys, e.g. `ABC-123`).
- The **PR title** should be a clean Conventional-Commit-style summary — it becomes the release note.
- Apply the right **label** (`major`/`breaking`, `minor`/`feature`, `patch`/`fix`) — this is what sets the version bump.
- **Squash-merge** PRs, so `main` keeps one clean commit per PR that matches the PR title.

**Examples:**

```
feat: add configurable memory_size and timeout
fix: scope the runtime log policy to the function's own log group
docs: document extra_policy_json usage
feat!: replace extra_policy_arns with an inline extra_policy_json
```
