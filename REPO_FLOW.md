# Mycelium Repo Flow

This repo is the public/shareable core layer for Mycelium:

```text
C:\Users\marcu\mycelium-core
```

It should contain code, schemas, infrastructure templates, test fixtures, and public documentation. It should not contain personal memory, household inventory, live credentials, device-specific secrets, private vault notes, or local runtime data.

## Connected Locations

| Layer | Path | Purpose | Git posture |
| --- | --- | --- | --- |
| Main mushroom | private/local truth root | Personal memory, lived context, raw truth, unresolved notes | Private/local |
| Public core | `C:\Users\marcu\mycelium-core` | Rule engine, schemas, deploy templates, tests, public docs | Publishable |
| Internal system | `C:\Users\marcu\mycelium-system-staging\mycelium-system` | System bundle, vault, local services, private operations | Private/local |
| Operator docs | `C:\Users\marcu\.github` | Personal ecosystem docs and GitHub/operator guidance | Private unless curated |
| Synced copy | `C:\Users\marcu\MobiusSync\my-app` | Secondary/sync copy | Do not treat as source of truth |
| Backups | `D:\Migration_Backup\...` | Recovery snapshots | Read-only archive |

## Information Boundaries

Use three lanes:

| Lane | Belongs here | Never include |
| --- | --- | --- |
| Public | Generic code, schemas, templates, sanitized examples, architecture docs | Tokens, passwords, private hostnames, family data, live IPs |
| Private | Personal operating docs, vault notes, machine names, local topology, internal runbooks | Plaintext credentials |
| Secret | `.env`, keys, certificates, API tokens, OAuth files, database passwords | Anything committed to Git |

## Branching Model

Use simple branches until the project needs more ceremony:

```text
main                         public, stable, publishable
concepts/<topic>             public-safe philosophy and architecture
examples/<topic>             working demos with fake or sanitized data
enterprise/<topic>           hardened deployable reference systems
internal/<topic>             private integration work before sanitizing
ops/<topic>                  local deployment and operations changes
archive/<date>               snapshots before major reshaping
```

Rules:

- `main` must stay public-safe.
- `internal/*` may reference private paths and machine names, but should still avoid secrets.
- `concepts/*` explains the pattern without exposing the private truth source.
- `examples/*` proves the pattern with toy data or sanitized fixtures.
- `enterprise/*` turns known-working examples into supportable deployment patterns.
- Secrets never go into any branch.
- Before merging to `main`, check `PUBLIC_PRIVATE_SECRET.md` and run a secrets scan.
- Backups on `D:\Migration_Backup` are not development roots.

## Daily Flow

1. Work in `C:\Users\marcu\mycelium-core` for code and public-safe docs.
2. Keep private operating context in `C:\Users\marcu\.github` or the system bundle.
3. Keep runtime values in `.env`; keep `.env.example` sanitized.
4. When a private idea becomes reusable, move only the sanitized version into this repo.
5. Commit from a topic branch, then merge into `main` only after checking boundaries.

## Public Output Lanes

| Directory | Purpose |
| --- | --- |
| `concepts/` | Explain the ideas, vocabulary, architecture, and design principles. |
| `examples/` | Demonstrate the ideas with fake data, toy systems, or sanitized fixtures. |
| `enterprise/` | Package known-working systems as hardened deployment and operations patterns. |

## Current Cleanup Notes

- `.env` was already tracked before this flow file was added. Treat its values as exposed until rotated if they were real credentials.
- `.gitmodules` is currently modified and empty.
- `ios` is currently deleted in the working tree, likely related to previous submodule work.
