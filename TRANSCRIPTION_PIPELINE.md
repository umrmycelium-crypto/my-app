# Transcription Pipeline

This is the missing bridge between your input surface and the structured data layer.

## Flow

```text
UI / capture form
  -> raw intake
  -> transcription worker
  -> structured packet
  -> Baserow raw capture
  -> target record
  -> rule engine / public output
```

## What "transcribe into data" means here

The worker does not just turn audio into text. It converts messy input into a packet with:

- transcript
- summary
- boundary classification
- lane classification
- extracted entities
- recommended record type
- relevance statement

That packet is what the rest of the system can store, search, and route.

## Docker Roles

- `forge-chat`: capture surface and operator hub.
- `transcription-worker`: turns raw input into structured packets.
- `rule-engine`: applies your rules and writes normalized records.
- `postgres` and `redis`: persistence and fast state.

## Data Rules

- Keep raw input.
- Keep the transcript.
- Keep the structured packet.
- Append the analysis to notes instead of overwriting source text.
- Never promote secret material to public output.

## Practical Contract

If a capture is text-only, the worker classifies it immediately.
If it includes media, the media stays linked and the text packet carries the meaning.
If the worker is unavailable, the raw capture still saves and the analysis becomes best-effort.
