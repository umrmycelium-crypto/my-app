# Vision System Technical Design Overview

A compact, production-ready architecture that turns camera input into persistent, actionable memories and ties those memories into the learning loop.

## Goals
- Reliable perception
- Explainable interpretation
- Implicit memory storage
- Rule merging
- Conflict detection
- Low‑noise user engagement

---

## Architecture Components

### 1. Perception Layer
Captures and preprocesses images and video frames.

#### Camera Adapter
- Handles frame rate, exposure, timestamps, device metadata
- Manages multiple camera feeds
- Buffers frames for downstream processing
- Tracks frame quality and exposure metrics

#### Preprocessor
- Resize and normalize images to model input dimensions
- OCR pass for text detection
- Edge detection for structural features
- Automatic timestamping
- Metadata enrichment (camera ID, location, lighting conditions)

---

### 2. Detection and Recognition Layer
Object detectors, OCR, text recognition, and instance trackers.

#### Object Detector
- Produces bounding boxes + class labels + confidence scores
- Supports multi-class detection (battery_pack, enclosure, connector, etc.)
- Outputs: `[x, y, width, height, class, confidence]`

#### Text Extractor
- OCR results with bounding boxes and confidence
- Serial number extraction
- Label and marking detection
- Outputs: `{text, bbox, confidence, language}`

#### Instance Tracker
- Maintains persistent IDs across frames
- Tracks object centroids and motion vectors
- Handles occlusion and re-identification
- Outputs: `{track_id, frame_id, detection_id, confidence}`

---

### 3. Interpretation Layer
Converts detections into semantic facts and candidate rules.

#### Entity Resolver
- Links visual instances to memory entities by:
  - Visual signature matching
  - Label matching (serial numbers, barcodes)
  - Spatial-temporal clustering
- Creates or updates entity records
- Maintains entity provenance (source detection, timestamp)

#### Feature Extractor
- Extracts attributes from detections:
  - `scuffing_score`: 0.0–1.0 (computed from edge density)
  - `wear_score`: 0.0–1.0 (computed from color fading, texture)
  - `color`: dominant color classification
  - `serial`: extracted text
  - `location`: spatial coordinates or zone label
- Outputs: structured attribute dictionary

#### Rule Engine
- Applies stored rules to detections and entities
- Computes matches with explanation traces
- Produces confidence scores and reasoning chains
- Example: *"Battery X matches wear-rule-42 because scuffing_score (0.72) > threshold (0.65) AND color == 'black'"*

---

### 4. Memory Layer
Stores facts, entities, rules, and event history.

#### Short Term Store
- Ephemeral session facts for immediate context
- Holds working hypotheses and candidate rules
- Time-windowed retention (e.g., 1 hour)
- Fast read/write for real-time decisions

#### Durable Memory Store
- Persistent structured facts and rule metadata
- PostgreSQL schema:
  - `entities`: {id, type, visual_signature, labels, created_at, updated_at}
  - `attributes`: {entity_id, key, value, confidence, source, timestamp}
  - `rules`: {id, name, condition, action, priority, contradiction_count, created_at}
  - `events`: {id, entity_id, rule_id, event_type, details, timestamp}
  - `corrections`: {id, rule_id, event_id, correction_type, delta, user_id, timestamp}

#### Indexing Service
- Vector index for visual signatures (Milvus)
  - Enables similarity search on image embeddings
  - Supports fast entity re-identification
- Text index for labels and notes (PostgreSQL full-text search)
  - Rapid lookup by serial number, part name, notes

---

### 5. Learning and Merge Layer
Merges new corrections into existing rules, tracks contradictions, and triggers retirement checks.

#### Merge Logic
- Delta detection: compares correction to current rule state
- Restatement generation: rewrites rule conditions to incorporate new evidence
- Versioning: maintains rule history and rollback capability
- Conflict resolution: prioritizes user corrections over model predictions

#### Contradiction Counter
- Per-rule counters for conflicting observations
- Thresholds determine when rules enter "uncertain" state
- Triggers alerts to user when contradiction rate > threshold
- Enables rule retirement or refinement workflows

---

### 6. Engagement Layer
Decides when to surface information to the user using behavioral specifications.

#### Interruption Policy
- Uses rule-surface counts (how often has rule fired?)
- Uses confidence scores and conflict state
- Suppresses noisy/redundant notifications
- Prioritizes high-confidence, low-contradiction findings
- Rate-limits notifications to prevent alert fatigue

#### Tone Generator
- Templates for "confident but tentative" phrasing
- Example high-confidence: *"Battery flagged for replacement: scuffing (0.92), wear (0.87)"*
- Example tentative: *"Possible issue with connector (0.58 confidence). Verify?"*
- Adjusts tone based on contradiction state and user correction history

---

### 7. API and Event Bus
Event-driven communication between components and external clients.

#### Event Types
- `detection.created`: new object detected
- `entity.recognized`: detection linked to known entity
- `rule.matched`: rule condition satisfied
- `rule.contradicted`: contradictory evidence observed
- `correction.applied`: user feedback received
- `rule.retired`: low-confidence rule removed
- `alert.surfaced`: notification sent to user

#### Client Interfaces
- **Mobile App**: real-time alerts, manual correction UI
- **Web Dashboard**: rule management, analytics, entity browser
- **Operator Console**: live video feed, confidence heatmaps, batch corrections
- **External Systems**: webhook integration for downstream workflows

---

## Data Flow Example

1. **Capture**: Camera frames → Perception Layer
2. **Preprocess**: Frames → resized, normalized, OCR-scanned
3. **Detect**: Objects + text detected with bounding boxes and confidence
4. **Track**: Detections assigned instance IDs; motion tracked
5. **Resolve**: Detection linked to known entity (battery #X-123)
6. **Extract**: Attributes computed (scuffing=0.72, color="black", wear=0.68)
7. **Match**: Rule engine checks stored rules
   - Rule-42: *IF scuffing > 0.65 AND color=="black" THEN flag_for_replacement*
   - **MATCH**: confidence=0.89 (composite of detection confidence × rule conditions)
8. **Store**: Event logged to durable memory; entity attributes updated
9. **Learn**: If user corrects (e.g., *"This battery is fine"*):
   - Contradiction counter incremented for Rule-42
   - Merge logic re-evaluates rule conditions
10. **Engage**: Interruption policy checks:
    - Rule-42 has fired 5 times; contradiction_count=2
    - Decision: suppress notification; add to low-confidence queue
11. **Notify**: If threshold crossed or high-confidence match:
    - Tone generator formats message
    - Event published to client subscriptions

---

## Integration with Learning Loop

The memory layer directly feeds back into the learning loop:

- **Explicit corrections** update rule conditions (merge logic)
- **Implicit corrections** increment contradiction counters
- **Rule retirement** removes low-signal rules
- **Versioning** enables A/B testing of rule variants
- **Attribution** tracks which rules drive user actions

---

## Deployment Topology

```
┌─────────────────────────────────────────────────────┐
│                  Perception Layer                   │
│  [Camera] → [Adapter] → [Preprocessor]              │
└──────────────────┬──────────────────────────────────┘
                   ↓
┌─────────────────────────────────────────────────────┐
│           Detection & Recognition Layer             │
│  [Object Detector] [Text Extractor] [Tracker]       │
└──────────────────┬──────────────────────────────────┘
                   ↓
┌─────────────────────────────────────────────────────┐
│            Interpretation Layer                     │
│  [Entity Resolver] [Feature Extractor] [Rules]      │
└──────────────────┬──────────────────────────────────┘
                   ↓
┌─────────────────────────────────────────────────────┐
│            Memory & Storage Layer                   │
│  [Cache] [PostgreSQL] [Milvus Vector DB]            │
└──────────────────┬──────────────────────────────────┘
                   ↓
┌─────────────────────────────────────────────────────┐
│        Learning & Engagement Layer                  │
│  [Merge Logic] [Contradiction Counter] [Policy]     │
└──────────────────┬──────────────────────────────────┘
                   ↓
┌─────────────────────────────────────────────────────┐
│           API & Event Bus                           │
│  [Mobile] [Web] [Console] [External Systems]        │
└─────────────────────────────────────────────────────┘
```

---

## Key Design Principles

1. **Separation of Concerns**: Each layer is independently testable and scalable
2. **Explainability**: All decisions include reasoning chains and confidence scores
3. **Graceful Degradation**: System works with degraded components (e.g., tracker failure)
4. **User-Centric Learning**: Corrections and feedback directly improve rule quality
5. **Low False Positives**: Interruption policy prioritizes precision over recall
6. **Event-Driven**: Asynchronous processing enables real-time responsiveness
7. **Audit Trail**: All decisions and corrections are logged for compliance and debugging

---

## Next Steps

1. Implement Perception Layer adapters for your camera hardware
2. Integrate pre-trained object detectors (e.g., YOLOv8 for batteries)
3. Design PostgreSQL schema for durable memory store
4. Build Rule Engine with Rete or similar inference system
5. Develop user-facing mobile/web clients for feedback collection
6. Instrument engagement layer with analytics and A/B testing
7. Deploy on Kubernetes (AKS) with Redis for caching, Milvus for vector search
