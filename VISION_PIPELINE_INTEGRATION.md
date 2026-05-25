# Vision Pipeline and Integration with Memory and Rules

Complete workflow from frame capture through memory persistence, rule application, and engagement decisions.

---

## Pipeline Overview

```
┌─────────────────┐
│  1. Capture     │ Camera frame + metadata
└────────┬────────┘
         ↓
┌─────────────────┐
│  2. Preprocess  │ OCR, quality check, normalize
└────────┬────────┘
         ↓
┌─────────────────┐
│  3. Detect &    │ Bounding boxes, tracker IDs, embeddings
│     Track       │
└────────┬────────┘
         ↓
┌─────────────────┐
│  4. Resolve     │ Vector search + label matching
│     Entity      │
└────────┬────────┘
         ↓
┌─────────────────┐
│  5. Extract     │ Domain attributes (scuffing, wear, color)
│     Attributes  │
└────────┬────────┘
         ↓
┌─────────────────┐
│  6. Apply Rules │ Match rules, compute confidence
└────────┬────────┘
         ↓
┌─────────────────┐
│  7. Engagement  │ Interruption policy, surface decision
│     Decision    │
└────────┬────────┘
         ↓
┌─────────────────┐
│  8. Memory      │ Persist event, update entity, rule stats
│     Write       │
└─────────────────┘
```

---

## Stage 1: Capture Frame

**Input:** Camera stream

**Output:** Frame with metadata

**Processing:**
```json
{
  "frame_id": "uuid",
  "timestamp": "2026-03-11T03:07:00Z",
  "source_camera": "camera-1",
  "geolocation": {
    "zone": "shelf-A3",
    "coordinates": [40.7128, -74.0060]
  },
  "frame_metadata": {
    "width": 1920,
    "height": 1080,
    "fps": 30,
    "exposure_ms": 8.5,
    "iso": 400,
    "brightness": 0.65
  },
  "raw_frame": "base64_encoded_image_data_or_s3_reference"
}
```

---

## Stage 2: Preprocess

**Input:** Raw frame

**Output:** Validated, normalized frame

**Processing:**
- Run OCR to extract text regions
- Compute image quality metrics (sharpness, contrast, lighting)
- Drop frames below quality threshold (e.g., sharpness < 0.4)
- Resize to model input dimensions (e.g., 640×640)
- Normalize pixel values (0-1 or -1 to 1)
- Detect edges for structural features

**Output:**
```json
{
  "preprocessed_frame_id": "uuid",
  "original_frame_id": "frame-12345",
  "quality_metrics": {
    "sharpness": 0.87,
    "contrast": 0.72,
    "brightness": 0.65,
    "quality_score": 0.79,
    "passed_quality_check": true
  },
  "ocr_results": [
    {
      "text": "SN-12345",
      "bounding_box": [100, 50, 150, 80],
      "confidence": 0.94
    },
    {
      "text": "Acme Battery Co",
      "bounding_box": [110, 90, 200, 110],
      "confidence": 0.87
    }
  ],
  "preprocessed_image": "reference_to_normalized_tensor"
}
```

---

## Stage 3: Detect and Track

**Input:** Preprocessed frame

**Output:** Detections with bounding boxes, tracker IDs, visual embeddings

**Processing:**
- Run object detection model (e.g., YOLOv8 for battery_pack, enclosure, etc.)
- For each detection:
  - Extract bounding box and class label
  - Compute confidence score from model
  - Pass detection crop through embedding model to generate visual signature vector
  - Assign tracker ID based on motion and centroid tracking
- Aggregate detections across time (temporal consistency)

**Output:**
```json
{
  "frame_id": "frame-12345",
  "detections": [
    {
      "detection_id": "det-001",
      "tracker_id": "track-5",
      "class": "battery_pack",
      "confidence": 0.94,
      "bounding_box": {
        "x": 150,
        "y": 200,
        "width": 100,
        "height": 120
      },
      "visual_signature": {
        "embedding": [0.123, 0.456, 0.789, ...],
        "embedding_model": "resnet50-battery-v1",
        "embedding_dim": 512
      },
      "motion_vector": {
        "dx": 5.2,
        "dy": -2.1,
        "confidence": 0.88
      }
    },
    {
      "detection_id": "det-002",
      "tracker_id": "track-3",
      "class": "enclosure",
      "confidence": 0.87,
      "bounding_box": {
        "x": 450,
        "y": 100,
        "width": 200,
        "height": 250
      },
      "visual_signature": {
        "embedding": [0.234, 0.567, ...],
        "embedding_model": "resnet50-battery-v1",
        "embedding_dim": 512
      },
      "motion_vector": {
        "dx": 0.0,
        "dy": 0.0,
        "confidence": 0.99
      }
    }
  ],
  "timestamp": "2026-03-11T03:07:00Z"
}
```

---

## Stage 4: Resolve Entity

**Input:** Detection with visual signature and OCR text

**Output:** Entity ID (new or matched)

**Processing:**

### 4a. Label-based matching (Priority 1)
- Extract OCR text from detection or nearby regions
- Query PostgreSQL for exact serial/brand matches
- If found: `entity_id = matched_entity.id`

### 4b. Serial number extraction (Priority 2)
- Use regex to extract serial patterns (e.g., `SN-\d+`)
- Query durable memory for entity with that serial
- If found: `entity_id = matched_entity.id`

### 4c. Visual similarity search (Priority 3)
- Query Milvus vector index with detection embedding
- Retrieve top-k similar visual signatures (k=5)
- Rank by:
  - Cosine similarity to embedding
  - Temporal recency (last_seen)
  - Track continuity (same tracker_id in recent frames)
- If similarity > threshold (e.g., 0.85): `entity_id = nearest_match.entity_id`

### 4d. Create new entity (if no match)
- Generate new UUID
- Initialize with this detection as first observation

**Output:**
```json
{
  "detection_id": "det-001",
  "entity_id": "550e8400-e29b-41d4-a716-446655440001",
  "resolution_method": "visual_similarity",
  "resolution_confidence": 0.89,
  "resolution_details": {
    "label_match": null,
    "serial_match": null,
    "visual_matches": [
      {
        "entity_id": "550e8400-e29b-41d4-a716-446655440001",
        "similarity": 0.92,
        "last_seen": "2026-03-11T02:45:00Z",
        "visual_signature_id": "vec-123"
      },
      {
        "entity_id": "650e8400-e29b-41d4-a716-446655440002",
        "similarity": 0.71,
        "last_seen": "2026-02-28T10:00:00Z"
      }
    ]
  }
}
```

---

## Stage 5: Attribute Extraction

**Input:** Detection crop + entity context

**Output:** Normalized attributes

**Processing:**
- Extract visual attributes from bounding box crop:
  - `scuffing_score`: Compute from edge density, texture roughness (0-1)
  - `wear_score`: Compute from color fading, surface degradation (0-1)
  - `color`: Classify dominant color (black, white, red, blue, gray, etc.)
- Extract text attributes from OCR results:
  - `serial`: Extracted serial number
  - `brand`: Brand name if detected
- Extract location:
  - `location`: Zone label from camera metadata or manual annotation
- Aggregate with entity history (moving averages, time-weighted)

**Output:**
```json
{
  "entity_id": "550e8400-e29b-41d4-a716-446655440001",
  "detection_id": "det-001",
  "extracted_attributes": {
    "scuffing_score": 0.72,
    "scuffing_confidence": 0.85,
    "wear_score": 0.68,
    "wear_confidence": 0.82,
    "color": "black",
    "color_confidence": 0.94,
    "serial": "SN-12345",
    "serial_confidence": 0.94,
    "brand": "Acme",
    "brand_confidence": 0.88,
    "location": "shelf-A3"
  },
  "aggregated_attributes": {
    "scuffing_score_ma": 0.70,
    "wear_score_ma": 0.66,
    "age_estimate_days": 930
  }
}
```

---

## Stage 6: Apply Rules

**Input:** Entity with attributes

**Output:** Rule matches with explanations and confidence

**Processing:**

For each active rule in memory:
1. Evaluate condition expressions against entity attributes
2. If all conditions satisfied:
   - Compute match confidence as product of condition confidences
   - Generate explanation trace (which conditions matched, evidence found)
   - Add to matches list

**Example Rule Matching:**

Rule: `older_packs_have_scuffing`
```
Conditions: ["age > 2 years"]
Evidence Clues: ["scuffing_score > 0.5"]
```

Evaluation:
```
Entity age_estimate_days = 930 days ≈ 2.54 years
Condition "age > 2 years" = TRUE (confidence 0.95)

Scuffing_score = 0.72 > 0.5
Evidence clue satisfied: TRUE (confidence 0.85)

Match Confidence = 0.95 × 0.85 = 0.81
```

**Output:**
```json
{
  "entity_id": "550e8400-e29b-41d4-a716-446655440001",
  "rule_matches": [
    {
      "rule_id": "550e8400-e29b-41d4-a716-446655440000",
      "predicate": "older_packs_have_scuffing",
      "conditions_satisfied": [
        "age (930 days) > 2 years (730 days): TRUE"
      ],
      "evidence_found": [
        "scuffing_score (0.72) > threshold (0.5): TRUE"
      ],
      "match_confidence": 0.81,
      "explanation": "Battery is 2.54 years old (>2 year threshold) with scuffing score 0.72 (>0.5 threshold). Recommend replacement."
    },
    {
      "rule_id": "rule-voltage-critical",
      "predicate": "battery_voltage_low",
      "conditions_satisfied": [
        "battery_voltage (10.8V) < threshold (11.0V): TRUE",
        "temperature (28°C) > threshold (25°C): TRUE"
      ],
      "evidence_found": [
        "battery_voltage: 10.8V (CRITICAL)",
        "temperature_elevated: 28°C"
      ],
      "match_confidence": 0.95,
      "explanation": "Battery voltage critically low at 10.8V with elevated temperature. Immediate replacement required."
    }
  ]
}
```

---

## Stage 7: Engagement Decision

**Input:** Rule matches + entity history + user feedback history

**Output:** Decision to surface or suppress alert

**Processing:**

### Interruption Policy:
1. **Check rule surface count**
   - How many times has this rule fired for this entity?
   - Threshold: Surface first N times (e.g., N=2), then silent

2. **Check contradiction state**
   - If rule.contradiction_count > rule.contradiction_threshold: suppress
   - Reason: Rule is unreliable

3. **Check confidence**
   - If match_confidence < engagement_threshold (e.g., 0.65): suppress

4. **Check rate limiting**
   - If similar alert sent within last M minutes (e.g., M=5): suppress
   - Store in Redis for fast lookup

5. **Compute priority**
   - If multiple rules match: select highest priority
   - Critical rules always surface
   - Warning rules surface based on policy

**Output:**
```json
{
  "entity_id": "550e8400-e29b-41d4-a716-446655440001",
  "engagement_decision": {
    "decision": "surface_alert",
    "alert_type": "warning",
    "selected_rule": {
      "rule_id": "550e8400-e29b-41d4-a716-446655440000",
      "predicate": "older_packs_have_scuffing",
      "explanation": "Battery is 2.54 years old (>2 year threshold) with scuffing score 0.72 (>0.5 threshold)."
    },
    "reasoning": {
      "rule_surface_count": 1,
      "rule_surface_threshold": 2,
      "status": "within_threshold",
      "contradiction_count": 0,
      "contradiction_threshold": 3,
      "confidence": 0.81,
      "confidence_threshold": 0.65,
      "rate_limit_check": "passed",
      "priority": 50
    },
    "notification": {
      "channel": "mobile_push",
      "message": "Battery SN-12345 flagged for replacement: scuffing (0.72), age (2.5 years). Verify and plan replacement.",
      "target_user": "user:Archer",
      "tone": "confident_but_tentative"
    }
  }
}
```

---

## Stage 8: Memory Write

**Input:** Event with all stages complete

**Output:** Persisted event + updated entity + updated rule stats

**Processing:**

### 8a. Persist Event Log
Write to PostgreSQL events table:
```sql
INSERT INTO events (
  event_id, frame_id, timestamp, entity_id, detection_id, applied_rules,
  action, user_feedback, confidence_overall, metadata
) VALUES (...);
```

### 8b. Update Entity
Update entity last_seen and attributes:
```sql
UPDATE entities SET
  last_seen = NOW(),
  attributes = jsonb_set(attributes, '{scuffing_score}', 0.72),
  updated_at = NOW(),
  history = array_append(history, event_id)
WHERE entity_id = '550e8400-e29b-41d4-a716-446655440001';
```

### 8c. Update Rule Metadata
If rule matched:
```sql
UPDATE rules SET
  match_count = match_count + 1,
  last_match_at = NOW()
WHERE rule_id = '550e8400-e29b-41d4-a716-446655440000';
```

### 8d. Handle Contradictions
If user feedback contradicts rule:
```sql
UPDATE rules SET
  contradiction_count = contradiction_count + 1,
  last_contradiction_at = NOW()
WHERE rule_id = '550e8400-e29b-41d4-a716-446655440000';
```

### 8e. Cache Alert State (Redis)
Store alert decision for rate limiting:
```redis
SET "alert:entity_550e8400-e29b-41d4-a716-446655440001:rule_550e8400-e29b-41d4-a716-446655440000" "1" EX 300
```

**Output (Event Log Entry):**
```json
{
  "event_id": "550e8400-e29b-41d4-a716-446655440000",
  "timestamp": "2026-03-11T03:07:00Z",
  "entity_id": "550e8400-e29b-41d4-a716-446655440001",
  "detection": {
    "detection_id": "det-001",
    "type": "battery_pack",
    "confidence": 0.94,
    "attributes": {
      "scuffing_score": 0.72,
      "wear_score": 0.68,
      "color": "black",
      "serial": "SN-12345"
    }
  },
  "applied_rules": [
    "550e8400-e29b-41d4-a716-446655440000"
  ],
  "action": "surfaced_rule",
  "action_metadata": {
    "alert_type": "warning",
    "notification_channel": "mobile_push",
    "target_user": "user:Archer"
  },
  "source": "camera-1",
  "user_feedback": null,
  "confidence_overall": 0.81,
  "processing_ms": 156,
  "tags": [
    "battery",
    "wear_assessment",
    "alerted"
  ]
}
```

---

## Handling User Feedback (Learning Loop Integration)

When user provides feedback (e.g., "this is a contradiction"):

1. **Create Correction Event**
   ```json
   {
     "correction_id": "uuid",
     "entity_id": "550e8400-e29b-41d4-a716-446655440001",
     "rule_id": "550e8400-e29b-41d4-a716-446655440000",
     "feedback_type": "contradiction",
     "user_feedback": "Battery is still functioning well. Scuffing is cosmetic.",
     "corrected_value": "condition_acceptable",
     "timestamp": "2026-03-11T03:10:00Z"
   }
   ```

2. **Update Rule Contradiction Counter**
   - Increment `rule.contradiction_count`
   - Update `rule.last_contradiction_at`

3. **Trigger Merge Logic** (if applicable)
   - Re-evaluate rule conditions
   - Potentially adjust thresholds
   - Create new rule version

4. **Log to Event Log**
   - Mark as correction event with traceability

---

## Performance Targets

| Stage | Target Latency | Notes |
|-------|-----------------|-------|
| Capture | N/A | Real-time stream |
| Preprocess | 10-20ms | Per frame |
| Detect & Track | 30-50ms | GPU-accelerated |
| Resolve Entity | 5-10ms | Vector index lookup |
| Extract Attributes | 5-10ms | Local computation |
| Apply Rules | 10-20ms | Rule engine inference |
| Engagement Decision | 5-10ms | Policy evaluation + Redis lookup |
| Memory Write | 20-50ms | PostgreSQL write + cache update |
| **Total Pipeline** | **100-180ms** | Per frame (end-to-end) |

---

## Data Flow Diagram (with storage)

```
Frame Capture (Camera)
        ↓
    Preprocess → [Drop low-quality frames]
        ↓
  Detect & Track → [Embeddings to Milvus]
        ↓
  Resolve Entity → [Vector search] → [PostgreSQL entity lookup]
        ↓
 Extract Attributes
        ↓
   Apply Rules → [PostgreSQL rules table]
        ↓
 Engagement Decision → [Redis rate-limit cache]
        ↓
 Memory Write → [PostgreSQL events] [Redis alert state]
        ↓
   Event Log Entry (queryable, auditable)
```

---

## Next Steps

1. Implement Stage 1-3 with camera adapter and detection model
2. Integrate Milvus for visual signature indexing (Stage 4c)
3. Build rule engine for Stage 6 (Rete algorithm or similar)
4. Implement interruption policy in Stage 7
5. Wire up PostgreSQL schema for Stage 8
6. Add user feedback handling and learning loop
7. Deploy on Kubernetes with Redis caching layer
