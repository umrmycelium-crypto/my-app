# Vision Pipeline: Rule Merge, Conflict Detection, and Operationalization

Complete technical specification for rule management, conflict resolution, storage strategy, and implementation roadmap.

---

## Part 1: Rule Merge, Conflict Detection, and Retirement Logic

### 1.1 Merge Strategy

When user approves an update that does not contradict existing rule:

#### Before Merge
```json
{
  "rule_id": "rule-001",
  "predicate": "older_packs_have_scuffing",
  "conditions": ["age > 2 years"],
  "evidence_clues": ["scuffing_score > 0.5"],
  "version": 1,
  "created_at": "2026-03-01T10:00:00Z"
}
```

#### Merge Trigger
User feedback: "Battery is 2 years old and doesn't have scuffing. Update rule."

#### After Merge
```json
{
  "rule_id": "rule-001",
  "predicate": "older_packs_may_have_scuffing",
  "conditions": ["age > 2 years"],
  "evidence_clues": [
    "scuffing_score > 0.5",
    "scuffing_is_clue = true"
  ],
  "version": 2,
  "created_at": "2026-03-01T10:00:00Z",
  "updated_at": "2026-03-11T03:15:00Z",
  "updated_by": "user:Archer",
  "merged_from": ["rule-001-v1"],
  "restatement": "Batteries older than 2 years may show scuffing, but scuffing is not a definitive indicator of replacement need. Treat as supporting evidence.",
  "metadata": {
    "merge_reason": "user_correction",
    "merge_event_id": "event-uuid-123"
  }
}
```

#### Merge Logic Operations

**1. Add conditions (conjunction):**
```
Before: conditions = ["age > 2 years"]
User feedback: "only flag if also high wear"
After: conditions = ["age > 2 years", "wear_score > 0.6"]
```

**2. Soften predicates (reduce specificity):**
```
Before: predicate = "older_packs_have_scuffing"
         (implies scuffing is required)
After:  predicate = "older_packs_may_have_scuffing"
         (scuffing is optional, softened evidence)
```

**3. Adjust evidence clues:**
```
Before: evidence_clues = ["scuffing_score > 0.5"]
After:  evidence_clues = ["scuffing_score > 0.5", "wear_score > 0.6", "visual_damage_detected"]
        (multiple signals required instead of single)
```

**4. Update action:**
```
Before: action = "flag_for_replacement"
After:  action = "escalate_to_human"
        (lower confidence triggers human review instead of direct action)
```

**5. Adjust priority:**
```
Before: priority = 80
After:  priority = 50
        (reduce priority after contradictions)
```

#### Merge Metadata
```json
{
  "merge_event": {
    "merge_id": "merge-uuid-456",
    "source_rules": ["rule-001-v1"],
    "resulting_rule": "rule-001-v2",
    "merge_strategy": "soften_predicate_add_condition",
    "merged_by": "user:Archer",
    "merged_at": "2026-03-11T03:15:00Z",
    "user_feedback": "Battery is 2 years old and doesn't have scuffing. Rule is too strict.",
    "changes": {
      "predicate": "older_packs_have_scuffing → older_packs_may_have_scuffing",
      "conditions_added": ["wear_score > 0.6"],
      "evidence_clues_added": ["wear_score > 0.6"],
      "priority_adjusted": "80 → 50",
      "action_changed": "flag_for_replacement → escalate_to_human"
    }
  }
}
```

---

### 1.2 Contradiction Handling

#### Contradiction Detection

Each time user marks detection as "contradiction" or system detects repeated mismatches:

```json
{
  "contradiction_event_id": "event-uuid-789",
  "timestamp": "2026-03-11T03:10:00Z",
  "rule_id": "rule-001",
  "entity_id": "entity-001",
  "contradiction_type": "user_feedback",
  "details": "User marked as false positive: Battery functions normally",
  "contradiction_count_before": 0,
  "contradiction_count_after": 1,
  "contradiction_threshold": 3
}
```

#### Contradiction Counter Logic

```python
def handle_contradiction(rule_id, entity_id, contradiction_type):
    rule = get_rule(rule_id)
    rule.contradiction_count += 1
    rule.last_contradiction_at = now()
    
    # Update rule status
    if rule.contradiction_count >= rule.contradiction_threshold:
        rule.status = "stale"
        rule.flagged_for_retirement = True
        emit_event("rule_stale", rule_id=rule_id)
    
    # Update entity feedback history
    entity = get_entity(entity_id)
    entity.corrections.append({
        "feedback_type": contradiction_type,
        "rule_id": rule_id,
        "timestamp": now()
    })
    
    # Log contradiction
    log_event({
        "event_type": "rule.contradicted",
        "rule_id": rule_id,
        "entity_id": entity_id,
        "contradiction_count": rule.contradiction_count
    })
    
    return rule.contradiction_count
```

#### Stale Rule Detection

```sql
-- Query for rules that should be flagged
SELECT rule_id, predicate, contradiction_count, match_count, 
       (contradiction_count / NULLIF(match_count, 0)) as contradiction_ratio
FROM rules
WHERE contradiction_count >= contradiction_threshold
  AND status != 'retired'
  AND retired_at IS NULL
ORDER BY contradiction_count DESC;
```

#### User Notification (Engagement Layer)

When rule reaches contradiction threshold:

```json
{
  "notification_type": "rule_retirement_prompt",
  "rule_id": "rule-001",
  "message": "Rule 'older_packs_have_scuffing' has received 3+ contradictions. This rule may be outdated. Would you like to retire it, update it, or keep it?",
  "options": [
    {
      "action": "retire",
      "label": "Retire rule",
      "consequence": "This rule will no longer surface alerts."
    },
    {
      "action": "update",
      "label": "Update rule",
      "consequence": "Edit rule conditions and evidence clues."
    },
    {
      "action": "keep",
      "label": "Keep rule",
      "consequence": "Rule remains active. Continue tracking contradictions."
    }
  ],
  "tone": "tentative",
  "confidence": 0.45
}
```

---

### 1.3 Conflict Resolution Between Rules

When two or more rules fire for same entity with conflicting recommendations:

#### Conflict Detection

```python
def detect_conflicts(entity_id, rule_matches):
    """
    Check if multiple rule actions are incompatible
    """
    conflicts = []
    actions = [m['action'] for m in rule_matches]
    
    # Define conflicting action pairs
    conflict_pairs = [
        ("flag_for_replacement", "keep_operational"),
        ("escalate", "suppress_alert"),
        ("quarantine", "approve_for_use")
    ]
    
    for (action1, action2) in conflict_pairs:
        if action1 in actions and action2 in actions:
            conflicts.append({
                "conflict_type": "action_conflict",
                "action1": action1,
                "action2": action2,
                "rules_involved": [m for m in rule_matches 
                                  if m['action'] in [action1, action2]]
            })
    
    return conflicts
```

#### Conflict Resolution Strategy

**Priority Scoring:**

```python
def compute_rule_priority(rule):
    """
    Compute priority score for conflict resolution
    """
    base_confidence = rule['confidence']
    recency_weight = compute_recency_weight(rule['last_match_at'])
    usage_count_factor = min(rule['match_count'] / 100.0, 1.0)
    contradiction_penalty = (1.0 - rule['contradiction_count'] 
                            / rule['contradiction_threshold'])
    
    priority_score = (
        base_confidence * 0.4 +           # 40% model confidence
        recency_weight * 0.3 +            # 30% recency (recent matches weighted higher)
        usage_count_factor * 0.2 +        # 20% track record (more uses = more reliable)
        contradiction_penalty * 0.1       # 10% contradiction history (fewer contradictions = better)
    )
    
    return priority_score
```

**Example Conflict Resolution:**

```json
{
  "entity_id": "entity-001",
  "detected_conflicts": [
    {
      "rule1": {
        "rule_id": "rule-001",
        "predicate": "older_packs_have_scuffing",
        "action": "flag_for_replacement",
        "priority_score": 0.78
      },
      "rule2": {
        "rule_id": "rule-002",
        "predicate": "battery_voltage_acceptable",
        "action": "keep_operational",
        "priority_score": 0.65
      },
      "conflict_type": "action_conflict"
    }
  ],
  "resolution_decision": {
    "winning_rule": "rule-001",
    "reason": "Higher priority score (0.78 > 0.65)",
    "recommended_action": "flag_for_replacement",
    "tone": "confident_but_tentative",
    "message": "Recommend replacement based on scuffing assessment (0.78 confidence). Battery voltage is acceptable, but age and surface condition suggest proactive replacement.",
    "conflict_logged": true,
    "conflict_event_id": "event-uuid-999"
  }
}
```

---

### 1.4 Versioning and Audit

#### Version History
```sql
-- Rule versions table
CREATE TABLE rule_versions (
  version_id UUID PRIMARY KEY,
  rule_id UUID NOT NULL,
  version_number INT NOT NULL,
  predicate VARCHAR(128),
  conditions JSONB,
  evidence_clues JSONB,
  action VARCHAR(50),
  priority INT,
  created_at TIMESTAMP,
  created_by VARCHAR(100),
  updated_at TIMESTAMP,
  updated_by VARCHAR(100),
  merged_from UUID[],
  merge_reason VARCHAR(100),
  restatement TEXT,
  UNIQUE(rule_id, version_number),
  FOREIGN KEY (rule_id) REFERENCES rules(rule_id)
);

-- Immutable audit trail
CREATE TABLE rule_audit_log (
  audit_id UUID PRIMARY KEY,
  rule_id UUID NOT NULL,
  version_number INT,
  event_type VARCHAR(50), -- 'created', 'updated', 'merged', 'retired'
  change_details JSONB,
  changed_by VARCHAR(100),
  changed_at TIMESTAMP,
  FOREIGN KEY (rule_id) REFERENCES rules(rule_id)
);
```

#### Restatement Generation
```python
def generate_restatement(rule_before, rule_after, merge_reason):
    """
    Generate human-readable restatement of rule changes
    """
    statements = []
    
    # Predicate change
    if rule_before.predicate != rule_after.predicate:
        statements.append(
            f"Rule name changed from '{rule_before.predicate}' "
            f"to '{rule_after.predicate}' (more tentative interpretation)."
        )
    
    # Conditions change
    added_conditions = set(rule_after.conditions) - set(rule_before.conditions)
    if added_conditions:
        conditions_str = ", ".join(added_conditions)
        statements.append(f"Added conditions: {conditions_str}")
    
    # Evidence change
    added_evidence = set(rule_after.evidence_clues) - set(rule_before.evidence_clues)
    if added_evidence:
        evidence_str = ", ".join(added_evidence)
        statements.append(f"Added supporting evidence clues: {evidence_str}")
    
    # Action change
    if rule_before.action != rule_after.action:
        statements.append(
            f"Action changed from '{rule_before.action}' "
            f"to '{rule_after.action}' (lower confidence response)."
        )
    
    # Priority change
    if rule_before.priority != rule_after.priority:
        statements.append(
            f"Priority adjusted from {rule_before.priority} to {rule_after.priority}."
        )
    
    # Merge reason
    if merge_reason:
        statements.append(f"Reason for update: {merge_reason}")
    
    return " ".join(statements)
```

---

## Part 2: Storage, Indexing, and Retrieval

### 2.1 Storage Choice Matrix

| Component | Recommended | Alternative | Rationale |
|-----------|-------------|-------------|-----------|
| **Durable facts** | PostgreSQL JSONB | MongoDB | ACID, complex queries, full-text search on labels |
| **Visual index** | Milvus | FAISS | Scalable vector search, distributed, GPU-accelerated |
| **Text search** | ElasticSearch | PostgreSQL FTS | Fast fuzzy OCR search, exact label matching |
| **Event log** | Kafka | DynamoDB Streams | Replayable events, time-ordered, audit trail |
| **Cache** | Redis | Memcached | Session facts, surfacing counters, rate limiting |

### 2.2 PostgreSQL JSONB Schema for Facts and Rules

```sql
-- Entities table
CREATE TABLE entities (
  entity_id UUID PRIMARY KEY,
  type VARCHAR(50) NOT NULL, -- battery_pack, enclosure, etc.
  visual_signature_id VARCHAR(100), -- Reference to Milvus vector
  labels JSONB, -- {"serial": "SN-12345", "brand": "Acme"}
  attributes JSONB, -- {"scuffing_score": 0.72, "wear_score": 0.68, ...}
  source VARCHAR(100),
  confidence DECIMAL(3,2),
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  last_seen TIMESTAMP,
  history UUID[] DEFAULT '{}', -- Event IDs
  metadata JSONB,
  INDEX idx_entity_type (type),
  INDEX idx_entity_visual (visual_signature_id),
  INDEX idx_entity_updated (updated_at DESC)
);

-- Rules table
CREATE TABLE rules (
  rule_id UUID PRIMARY KEY,
  predicate VARCHAR(128) NOT NULL,
  conditions JSONB NOT NULL, -- Array of condition strings
  evidence_clues JSONB NOT NULL, -- Array of clue strings
  type VARCHAR(50), -- heuristic, learned_from_corrections, domain_expert, etc.
  version INT DEFAULT 1,
  action VARCHAR(50),
  action_metadata JSONB,
  priority INT DEFAULT 50,
  created_by VARCHAR(100),
  created_at TIMESTAMP DEFAULT NOW(),
  updated_by VARCHAR(100),
  updated_at TIMESTAMP,
  contradiction_count INT DEFAULT 0,
  contradiction_threshold INT DEFAULT 3,
  last_contradiction_at TIMESTAMP,
  match_count INT DEFAULT 0,
  last_match_at TIMESTAMP,
  confidence DECIMAL(3,2),
  tags JSONB, -- Array of tags
  description TEXT,
  merged_from UUID[], -- Array of rule IDs
  superseded_by UUID,
  retired_at TIMESTAMP,
  retirement_reason VARCHAR(50),
  status VARCHAR(50) DEFAULT 'active', -- active, stale, retired
  metadata JSONB,
  INDEX idx_rule_status (status),
  INDEX idx_rule_predicate (predicate),
  INDEX idx_rule_contradiction (contradiction_count DESC),
  INDEX idx_rule_created (created_at DESC)
);

-- Events (immutable log)
CREATE TABLE events (
  event_id UUID PRIMARY KEY,
  timestamp TIMESTAMP NOT NULL,
  entity_id UUID NOT NULL,
  rule_id UUID,
  detection JSONB, -- Detection metadata
  applied_rules UUID[],
  action VARCHAR(50),
  action_metadata JSONB,
  source VARCHAR(100),
  user_feedback VARCHAR(50),
  feedback_metadata JSONB,
  session_id UUID,
  frame_id VARCHAR(100),
  confidence_overall DECIMAL(3,2),
  processing_ms INT,
  metadata JSONB,
  tags JSONB,
  created_at TIMESTAMP DEFAULT NOW(),
  INDEX idx_event_timestamp (timestamp DESC),
  INDEX idx_event_entity (entity_id),
  INDEX idx_event_rule (rule_id),
  INDEX idx_event_feedback (user_feedback)
);

-- Corrections (for learning loop)
CREATE TABLE corrections (
  correction_id UUID PRIMARY KEY,
  entity_id UUID NOT NULL,
  rule_id UUID,
  correction_type VARCHAR(50), -- entity_classification, attribute_update, rule_adjustment
  previous_value JSONB,
  corrected_value JSONB,
  reason TEXT,
  corrected_by VARCHAR(100),
  corrected_at TIMESTAMP DEFAULT NOW(),
  event_id UUID, -- Link back to event
  INDEX idx_correction_rule (rule_id),
  INDEX idx_correction_entity (entity_id),
  FOREIGN KEY (event_id) REFERENCES events(event_id)
);

-- Rule merge history
CREATE TABLE rule_merges (
  merge_id UUID PRIMARY KEY,
  source_rule_ids UUID[],
  resulting_rule_id UUID NOT NULL,
  merge_strategy VARCHAR(50), -- combine_conditions, soften_predicate, etc.
  merged_by VARCHAR(100),
  merged_at TIMESTAMP DEFAULT NOW(),
  merge_reason TEXT,
  changes JSONB,
  FOREIGN KEY (resulting_rule_id) REFERENCES rules(rule_id)
);
```

### 2.3 Milvus Vector Index for Visual Signatures

```python
from pymilvus import Collection, CollectionSchema, FieldSchema, DataType

# Define schema
fields = [
    FieldSchema(name="entity_id", dtype=DataType.VARCHAR, max_length=100, is_primary=True),
    FieldSchema(name="visual_embedding", dtype=DataType.FLOAT_VECTOR, dim=512),
    FieldSchema(name="entity_type", dtype=DataType.VARCHAR, max_length=50),
    FieldSchema(name="last_seen", dtype=DataType.INT64),  # Unix timestamp
    FieldSchema(name="metadata", dtype=DataType.VARCHAR, max_length=1000),
]

schema = CollectionSchema(fields=fields, description="Entity visual signatures")
collection = Collection(name="entity_signatures", schema=schema)

# Create index
index_params = {
    "metric_type": "L2",  # Euclidean distance
    "index_type": "IVF_FLAT",
    "params": {"nlist": 100}
}
collection.create_index(field_name="visual_embedding", index_params=index_params)

# Example: Query nearest neighbors
def find_similar_entities(query_embedding, top_k=5):
    results = collection.search(
        data=[query_embedding],
        anns_field="visual_embedding",
        param={"metric_type": "L2", "params": {"nprobe": 10}},
        limit=top_k,
        output_fields=["entity_id", "entity_type", "last_seen"]
    )
    return results[0]
```

### 2.4 ElasticSearch Index for OCR and Labels

```json
{
  "mappings": {
    "properties": {
      "entity_id": { "type": "keyword" },
      "serial": { 
        "type": "text",
        "analyzer": "standard",
        "fields": { "keyword": { "type": "keyword" } }
      },
      "brand": { "type": "keyword" },
      "part_number": { "type": "keyword" },
      "ocr_text": { 
        "type": "text",
        "analyzer": "standard"
      },
      "labels": {
        "type": "keyword"
      },
      "location": { "type": "keyword" },
      "timestamp": { "type": "date" }
    }
  }
}
```

---

## Part 3: APIs and Event Flows

### 3.1 Core Endpoints (REST)

#### POST /frame
Upload frame metadata; returns frame_id.

```http
POST /api/v1/frame
Content-Type: application/json

{
  "camera_id": "camera-1",
  "timestamp": "2026-03-11T03:07:00Z",
  "geolocation": {"zone": "shelf-A3"},
  "image_url": "s3://bucket/frames/frame-12345.jpg",
  "metadata": {
    "width": 1920,
    "height": 1080,
    "fps": 30
  }
}

Response:
{
  "frame_id": "frame-12345",
  "status": "accepted",
  "processing_id": "proc-001"
}
```

#### POST /detect
Submit detection results; returns entity_id or candidate entities.

```http
POST /api/v1/detect
Content-Type: application/json

{
  "frame_id": "frame-12345",
  "detections": [
    {
      "class": "battery_pack",
      "confidence": 0.94,
      "bounding_box": [150, 200, 100, 120],
      "visual_embedding": [0.123, 0.456, ...],
      "ocr_text": "SN-12345"
    }
  ]
}

Response:
{
  "detections_processed": 1,
  "resolved_entities": [
    {
      "detection_id": "det-001",
      "entity_id": "entity-001",
      "resolution_method": "visual_similarity",
      "confidence": 0.89
    }
  ]
}
```

#### GET /entity/{id}
Fetch entity facts and history.

```http
GET /api/v1/entity/550e8400-e29b-41d4-a716-446655440001

Response:
{
  "entity_id": "550e8400-e29b-41d4-a716-446655440001",
  "type": "battery_pack",
  "labels": {"serial": "SN-12345", "brand": "Acme"},
  "attributes": {
    "scuffing_score": 0.72,
    "wear_score": 0.68,
    "color": "black",
    "last_seen": "2026-03-11T03:07:00Z"
  },
  "confidence": 0.92,
  "history": [
    {"event_id": "event-001", "timestamp": "2026-03-11T03:07:00Z", "action": "detection"},
    {"event_id": "event-002", "timestamp": "2026-03-11T03:07:02Z", "action": "rule_matched"}
  ],
  "metadata": {
    "contradiction_count": 1,
    "rule_match_count": 5
  }
}
```

#### POST /feedback
User feedback on a surfaced rule or detection.

```http
POST /api/v1/feedback
Content-Type: application/json

{
  "entity_id": "550e8400-e29b-41d4-a716-446655440001",
  "rule_id": "550e8400-e29b-41d4-a716-446655440000",
  "feedback_type": "contradiction",
  "reason": "Battery is still functioning well. Scuffing is cosmetic.",
  "user_id": "user:Archer"
}

Response:
{
  "correction_id": "corr-001",
  "feedback_recorded": true,
  "rule_contradiction_count": 1,
  "rule_status": "active",
  "action": "none"
}
```

#### POST /rule/update
Apply user-approved update; triggers merge logic.

```http
POST /api/v1/rule/update
Content-Type: application/json

{
  "rule_id": "550e8400-e29b-41d4-a716-446655440000",
  "changes": {
    "conditions": ["age > 2 years", "wear_score > 0.6"],
    "evidence_clues": ["scuffing_score > 0.5", "wear_score > 0.6"],
    "action": "escalate_to_human",
    "priority": 50
  },
  "reason": "User feedback: rule too strict on scuffing alone",
  "user_id": "user:Archer"
}

Response:
{
  "rule_id": "550e8400-e29b-41d4-a716-446655440000",
  "new_version": 2,
  "merge_id": "merge-001",
  "restatement": "Batteries older than 2 years with wear_score > 0.6 may need replacement. Escalate for human verification.",
  "merged_from": ["550e8400-e29b-41d4-a716-446655440000-v1"]
}
```

#### GET /rules/pending
List rules flagged for retirement or conflict.

```http
GET /api/v1/rules/pending

Response:
{
  "stale_rules": [
    {
      "rule_id": "550e8400-e29b-41d4-a716-446655440000",
      "predicate": "older_packs_have_scuffing",
      "contradiction_count": 3,
      "match_count": 12,
      "contradiction_ratio": 0.25,
      "recommendation": "Retire or update"
    }
  ],
  "conflict_rules": [
    {
      "rule_ids": ["rule-001", "rule-002"],
      "conflict_type": "action_conflict",
      "last_conflict": "2026-03-11T03:10:00Z"
    }
  ]
}
```

---

### 3.2 Event Flow Example

**Sequence: Detection → Entity → Rule → Feedback → Learning**

```
1. Frame Capture
   camera → frame_id
   
2. Detection Submitted
   POST /detect → detection_id, entity_id resolved
   
3. Rules Applied
   Rule engine evaluates entity against all active rules
   → rule_matches with explanations
   
4. Engagement Decision
   Interruption policy: Should we surface?
   - Rule surface count for this entity: 1
   - Threshold: 2
   → Decision: SURFACE ALERT
   
5. User Receives Alert
   "Battery flagged for replacement: scuffing (0.72), age (2.5 years)"
   
6. User Provides Feedback
   POST /feedback → feedback_type: "contradiction"
   reason: "Battery functions normally"
   
7. System Updates
   - Increment rule.contradiction_count (now 1)
   - Log correction event
   - Update engagement counters
   
8. Rule Status Check
   contradiction_count (1) < threshold (3)
   → Rule remains active
   → Log event for monitoring
   
9. Next Occurrence (if contradiction_count reaches 3)
   - Flag rule as STALE
   - Emit "rule_stale" event
   - Surface retirement prompt to user
   
10. User Acts
    POST /rule/update or POST /rule/retire
    → Merge logic triggered
    → New version created
    → Restatement generated
    → Event logged
```

---

## Part 4: Security, Privacy, and Operational Considerations

### 4.1 Access Control (RBAC)

```json
{
  "roles": {
    "operator": {
      "permissions": [
        "view_entities",
        "view_events",
        "view_rules",
        "provide_feedback"
      ]
    },
    "rule_editor": {
      "permissions": [
        "view_entities",
        "view_events",
        "view_rules",
        "create_rules",
        "update_rules",
        "merge_rules",
        "retire_rules"
      ]
    },
    "admin": {
      "permissions": [
        "*"
      ]
    }
  },
  "rule_edit_audit": {
    "require_approval": true,
    "approval_roles": ["rule_editor", "admin"],
    "log_all_changes": true
  }
}
```

### 4.2 Data Retention and Privacy

```python
# Configurable retention policy
retention_policy = {
    "raw_images": "30 days",           # Delete after 30 days
    "ocr_text": "90 days",             # Retain for label matching
    "entity_facts": "indefinite",      # Keep persistent
    "event_logs": "1 year",            # Audit trail
    "user_feedback": "2 years",        # Learning history
}

# API for explicit memory deletion (GDPR compliance)
@app.delete("/api/v1/entity/{entity_id}/purge")
async def force_delete_entity(entity_id: str, user_id: str):
    """
    GDPR-compliant deletion of entity and related data
    """
    deleted = []
    
    # Delete from all storage systems
    deleted.append(delete_from_postgresql(entity_id))
    deleted.append(delete_from_milvus(entity_id))
    deleted.append(delete_from_elasticsearch(entity_id))
    deleted.append(delete_from_redis_cache(entity_id))
    
    # Audit log (keep deletion record for compliance)
    log_deletion({
        "entity_id": entity_id,
        "deleted_by": user_id,
        "deleted_at": now(),
        "systems": deleted
    })
    
    return {"status": "deleted", "systems": deleted}
```

### 4.3 Explainability and Audit

```json
{
  "decision_explanation": {
    "entity_id": "550e8400-e29b-41d4-a716-446655440001",
    "surfaced_rule": "550e8400-e29b-41d4-a716-446655440000",
    "decision": "surface_alert",
    "confidence": 0.81,
    "reasoning": {
      "rule_match": {
        "predicate": "older_packs_have_scuffing",
        "conditions_satisfied": [
          "age (930 days) > 2 years (730 days): TRUE"
        ],
        "evidence_found": [
          "scuffing_score (0.72) > threshold (0.5): TRUE"
        ],
        "match_confidence": 0.81
      },
      "engagement_policy": {
        "rule_surface_count": 1,
        "surface_threshold": 2,
        "passed_threshold": true,
        "contradiction_count": 0,
        "contradiction_threshold": 3,
        "no_recent_contradictions": true
      }
    },
    "trace_timestamp": "2026-03-11T03:07:00Z",
    "trace_id": "trace-uuid-123"
  }
}
```

### 4.4 Monitoring and Observability

```python
# Key metrics to track
monitoring_metrics = {
    "surfacing_frequency": {
        "metric": "rules_surfaced_per_hour",
        "alert_if": "> 100",  # Too many alerts = low precision
    },
    "contradiction_rates": {
        "metric": "contradiction_count_per_rule",
        "alert_if": "> 0.2",  # >20% contradiction rate
    },
    "false_positive_rates": {
        "metric": "user_marked_incorrect / rules_surfaced",
        "alert_if": "> 0.15",  # >15% false positive rate
    },
    "pipeline_latency": {
        "metric": "end_to_end_processing_ms",
        "target": "100-180ms",
        "alert_if": "> 500ms"
    },
    "entity_resolution_accuracy": {
        "metric": "correct_entity_matches / total_resolutions",
        "target": "> 0.95",
        "alert_if": "< 0.90"
    }
}

# Example Prometheus metrics
from prometheus_client import Counter, Histogram, Gauge

rules_surfaced = Counter('rules_surfaced_total', 'Total rules surfaced', ['rule_id'])
contradiction_count = Gauge('rule_contradictions', 'Contradiction count per rule', ['rule_id'])
pipeline_latency = Histogram('pipeline_latency_ms', 'End-to-end latency', buckets=[50, 100, 150, 200, 500])
```

---

## Part 5: Implementation Roadmap and Minimal Viable Stack

### Phase 1: MVP Perception (Weeks 1-3)

**Goal:** Capture frames, run detection, extract features

**Tasks:**
- [ ] Camera adapter for frame streaming (USB, RTSP, or file-based)
- [ ] Download pre-trained object detector (YOLOv8 for batteries)
- [ ] Integrate Tesseract or EasyOCR for text extraction
- [ ] Store detections and OCR results in PostgreSQL
- [ ] Basic frame quality checks (sharpness, brightness)

**Deliverables:**
- POST /frame endpoint
- POST /detect endpoint
- Raw detection logs in PostgreSQL

---

### Phase 2: Entity Resolution and Vector Index (Weeks 4-6)

**Goal:** Resolve detections to persistent entities

**Tasks:**
- [ ] Integrate embedding model (ResNet50 or CLIP for visual signatures)
- [ ] Deploy Milvus and build visual signature index
- [ ] Implement label-first resolution logic
- [ ] Implement serial number extraction and matching
- [ ] Implement visual similarity search (top-k nearest neighbors)

**Deliverables:**
- GET /entity/{id} endpoint
- Entity resolution with confidence scores
- Milvus index with 1000+ vectors

---

### Phase 3: Rule Engine and Memory Store (Weeks 7-10)

**Goal:** Apply rules, compute confidence, track contradictions

**Tasks:**
- [ ] Design rule schema (conditions, evidence, actions)
- [ ] Implement rule evaluation engine
- [ ] Implement contradiction counter and threshold logic
- [ ] Add rule versioning and merge metadata
- [ ] Build event log persistence (PostgreSQL + Kafka)

**Deliverables:**
- Rule schema in PostgreSQL
- Rule application logic with explanations
- Event log with 10K+ entries
- Contradiction tracking per rule

---

### Phase 4: Engagement Layer (Weeks 11-13)

**Goal:** Decide when to surface alerts with low false positives

**Tasks:**
- [ ] Implement surfacing policy (surface N times, then silent)
- [ ] Implement interruption policy (confidence thresholds, rate limiting)
- [ ] Integrate Redis for state caching
- [ ] Implement tone templates (confident, tentative, escalation)
- [ ] Implement conflict resolution between rules

**Deliverables:**
- POST /feedback endpoint
- Alert suppression and rate limiting
- Conflict detection and best-guess resolution
- Tone-appropriate notifications

---

### Phase 5: Merge and Versioning (Weeks 14-16)

**Goal:** Learn from user feedback, merge rules, retire stale rules

**Tasks:**
- [ ] Implement merge logic (add conditions, soften predicates)
- [ ] Implement restatement generation
- [ ] Implement rule retirement flow
- [ ] Add merge event logging
- [ ] Build rule history browser UI

**Deliverables:**
- POST /rule/update endpoint
- Merge strategy implementation
- Rule version history in PostgreSQL
- User-facing rule update UI

---

### Phase 6: Operationalize (Weeks 17-20)

**Goal:** Production-ready system with monitoring, RBAC, compliance

**Tasks:**
- [ ] Implement RBAC for rule edits and memory deletion
- [ ] Add data retention policies and GDPR compliance
- [ ] Integrate Prometheus metrics and alerting
- [ ] Build Grafana dashboards (surfacing frequency, contradiction rates, latency)
- [ ] Load testing (1000 frames/second, 10K rules)
- [ ] Documentation and runbooks

**Deliverables:**
- Production deployment on Kubernetes
- RBAC-protected endpoints
- Memory deletion API (GDPR)
- Monitoring and alerting
- Runbook for common operations

---

## Stack Summary

```
┌─────────────────────────────────────────┐
│      Application Layer (Python/Go)      │
│  - Pipeline orchestration               │
│  - Rule engine                          │
│  - Engagement logic                     │
└─────────────────────────────────────────┘
         ↓
┌─────────────────────────────────────────┐
│      Storage & Indexing Layer           │
│  - PostgreSQL (facts, rules, events)    │
│  - Milvus (visual similarity)           │
│  - ElasticSearch (text search)          │
│  - Kafka (event stream)                 │
│  - Redis (cache, state)                 │
└─────────────────────────────────────────┘
         ↓
┌─────────────────────────────────────────┐
│      Infrastructure (Kubernetes)        │
│  - Docker containers                    │
│  - AKS or EKS cluster                   │
│  - Persistent volumes                   │
│  - Load balancer                        │
└─────────────────────────────────────────┘
```

---

## Deployment Checklist

- [ ] Kubernetes cluster (AKS with 3+ nodes)
- [ ] PostgreSQL managed service (Azure Database for PostgreSQL)
- [ ] Milvus deployment (containerized on K8s)
- [ ] ElasticSearch cluster (managed service)
- [ ] Kafka or managed streams (Azure Event Hubs)
- [ ] Redis cluster (Azure Cache for Redis)
- [ ] Docker registry (Azure Container Registry)
- [ ] Monitoring (Prometheus + Grafana)
- [ ] API gateway and load balancer
- [ ] SSL/TLS certificates
- [ ] Secret management (Azure Key Vault)
- [ ] Backup and disaster recovery plan
