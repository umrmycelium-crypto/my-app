# Truth-to-Output Architecture

Mycelium has to stay honest without exposing everything. The private system is the root. Public work is a careful translation from that root into useful patterns, examples, and systems.

## Core Principle

Do not lie. Do not overshare.

The goal is to preserve the truth of the pattern while removing private payload: names, secrets, family context, raw memory, live infrastructure details, and anything that turns a helpful system into an exposed life.

## Layers

```text
Main mushroom / truth layer
  -> capture layer
  -> processing layer
  -> public concept layer
  -> public example layer
  -> enterprise layer
```

## 1. Main Mushroom / Truth Layer

This is the private root system.

It may contain:

- lived context
- personal memory
- raw notes
- machine-specific details
- private rituals and operating patterns
- unresolved material
- source material that should never be public as-is

This layer is allowed to be human, messy, contradictory, and incomplete. Its job is truth, not presentation.

## 2. Capture Layer

This layer accepts anything:

- Markdown
- voice transcripts
- screenshots
- chats
- logs
- PDFs
- JSON
- code fragments
- field notes

Capture should optimize for continuity and low friction. It should not require public polish.

## 3. Processing Layer

This layer turns raw material into structured understanding:

- normalize inputs
- dedupe facts
- classify public/private/secret risk
- map notes to existing schemas
- extract reusable patterns
- separate examples from personal context
- produce candidate public artifacts

Processing is where private truth becomes reusable system knowledge.

## 4. Public Concept Layer

This layer explains ideas safely:

- philosophy
- architecture
- patterns
- diagrams
- design principles
- vocabulary
- decision records

It should answer: what is the idea, why does it matter, and how does someone reason with it?

It should not expose the private root material that produced the idea.

## 5. Public Example Layer

This layer proves the ideas with safe material:

- toy data
- fake users
- sanitized fixtures
- demo pipelines
- starter templates
- known-working minimal examples

It should answer: how does someone try this without needing access to the private system?

## 6. Enterprise Layer

This layer turns examples into systems others can trust:

- deployable reference architectures
- infrastructure templates
- security posture
- CI/CD workflows
- monitoring and recovery patterns
- compliance-friendly documentation
- repeatable operating runbooks

It should answer: how does this survive contact with real teams and real constraints?

## Translation Rules

- Keep private truth private.
- Publish patterns, not personal payload.
- Use fake data when teaching.
- Use sanitized fixtures when demonstrating.
- Use explicit placeholders for secrets and private infrastructure.
- Move slowly when a document contains lived context.
- Treat accidental exposure as a rotation and cleanup event, not a normal edit.

## Branch Mapping

```text
main                         stable public-safe output
concepts/<topic>             public philosophy and architecture
examples/<topic>             runnable demos with fake/sanitized data
enterprise/<topic>           hardened deployable systems
internal/<topic>             private integration and translation work
ops/<topic>                  local operations, private by default
archive/<date>               snapshots before large changes
```

## Human Boundary

The main mushroom is not a product. It is the source system.

The public project can help other people because it is distilled from real use, but it does not need to expose the private root to be honest. The honest public artifact is the tested pattern, not the private material that taught it.
