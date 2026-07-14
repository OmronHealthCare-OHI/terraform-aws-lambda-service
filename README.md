# Omron-Terraform-Modules

Shared Terraform building blocks for OMRON services. Each module comes
pre-configured with the organization's requirements: naming prefix, required
tags, encryption, and sensible defaults, so resources built from these
modules pass the pipeline guardrails without extra work.

## How to use a module

Reference a module by git source, pinned to a version tag:

```hcl
module "service" {
  source = "github.com/OmronHealthCare-OHI/Omron-Terraform-Modules//modules/lambda-service?ref=v0.1.0"

  # inputs, see the module's README
}
```

The `?ref=` pin means nothing changes under your feet: you upgrade by
bumping the version deliberately. Never reference `main` directly.

## Modules

| Module | What it builds |
|--------|----------------|
| [`lambda-service`](modules/lambda-service/) | A Lambda function with alias-based rollback, minimal runtime role, and logs |

Planned: `dynamodb-table`, `service-secrets`.

## Conventions every module follows

- Required inputs: `service_name`, `name_prefix` (e.g. `usnp-usw2`)
- Tags come from the consumer's provider `default_tags` (team, service, stage); modules accept an optional `extra_tags` input
- Resource names: `{name_prefix}-{service_name}[-suffix]`
- Each module has a README and an `examples/complete` folder showing full usage
- Breaking changes only in a new major version

## Versioning

Semver git tags (`v0.1.0`). Changelog in GitHub Releases. Consumers pin
exact versions; the changelog tells them what an upgrade brings.

## Ownership

Cloud Foundations (CLF). Changes via PR.

## Consuming this repo from CI (access token)

This is a **private** repo, and Terraform fetches modules over git
(`github.com/OmronHealthCare-OHI/Omron-Terraform-Modules//modules/...`). So a
pipeline that consumes these modules needs a **read token**, provided as a
secret **in the consuming repo** (not here):

| Where | Name | What it is |
|-------|------|------------|
| Consuming pipeline repo → Secrets | `MODULES_READ_TOKEN` | Read access to this repo. A fine-grained PAT or GitHub App installation token with **Contents: Read** on `Omron-Terraform-Modules`. The build/plan/apply workflows use it via `git config insteadOf` to fetch modules. |

Create it, then in the consuming repo:

```bash
gh secret set MODULES_READ_TOKEN --repo OmronHealthCare-OHI/<service-repo> --body "<token>"
```

See `.env.example` for the reference.

**This repo itself needs no GitHub variables or secrets today.** If module CI
is added later (e.g. `terraform validate` + Checkov on PRs), it runs offline
and needs no AWS credentials.
