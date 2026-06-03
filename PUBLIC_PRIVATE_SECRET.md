# Public, Private, Secret Policy

Mycelium needs connected files with clear reasons. This policy defines where each kind of file belongs.

## Public

Public files are safe to publish or share.

Examples:

- Application source code
- JSON schemas
- Docker and Kubernetes templates with placeholder values
- Bicep/IaC templates without real subscription-specific secrets
- Sanitized architecture docs
- `.env.example`
- Tests using fake data

Public root:

```text
C:\Users\marcu\mycelium-core
```

## Private

Private files are personal or internal, but not credentials.

Examples:

- Obsidian memory notes
- machine profiles
- household/system operating docs
- internal diagrams
- local runbooks
- non-secret topology notes

Private roots:

```text
C:\Users\marcu\.github
C:\Users\marcu\mycelium-system-staging\mycelium-system
```

## Secret

Secret files contain values that must not be committed.

Examples:

- `.env`
- API keys and tokens
- database passwords
- OAuth credentials
- SSH private keys
- TLS private keys and cert material
- live webhook URLs with tokens

Secret handling:

- Keep secrets outside Git or in a dedicated encrypted store.
- Commit only templates such as `.env.example`.
- Rotate any real credential that was committed or pushed.
- Prefer environment variables, encrypted vaults, or platform secret stores for deployment.

## Promotion Rule

Private material can become public only after sanitization:

1. Remove credentials and private identifiers.
2. Replace local paths with placeholders where needed.
3. Replace live domains/IPs with examples unless intentionally public.
4. Preserve the honest pattern while removing personal payload.
5. Check for secrets before committing.
6. Move the sanitized artifact into `C:\Users\marcu\mycelium-core`.

Secret material never gets promoted.
