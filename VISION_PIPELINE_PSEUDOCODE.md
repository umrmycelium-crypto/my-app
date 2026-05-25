# Vision Pipeline: Pseudocode Implementation Examples

Complete implementation pseudocode for all pipeline stages, rule management, and engagement logic.

---

## Stage 1: Frame Capture and Preprocessing

```python
def capture_frame(camera_id: str, source: Union[RTSP, USB, S3]) -> Frame:
    """
    Capture frame from camera with metadata
    """
    try:
        raw_frame = camera.read_frame()
        
        return Frame(
            frame_id=generate_uuid(),
            timestamp=now_utc(),
            camera_id=camera_id,
            image_data=raw_frame,
            metadata={
                "width": raw_frame.shape[1],
                "height": raw_frame.shape[0],
                "fps": camera.fps,
                "exposure_ms": camera.exposure_ms,
                "iso": camera.iso,
                "geolocation": get_camera_geolocation(camera_id)
            }
        )
    except CameraError as e:
        log_error(f"Frame capture failed: {e}")
        return None


def preprocess_frame(frame: Frame) -> PreprocessedFrame:
    """
    Normalize, validate quality, extract OCR
    """
    # Quality metrics
    sharpness = compute_sharpness(frame.image_data)
    contrast = compute_contrast(frame.image_data)
    brightness = compute_brightness(frame.image_data)
    
    quality_score = (sharpness * 0.4 + contrast * 0.3 + brightness * 0.3)
    
    if quality_score < QUALITY_THRESHOLD:  # e.g., 0.4
        log_warning(f"Frame {frame.frame_id} below quality threshold: {quality_score}")
        return None  # Drop frame
    
    # OCR extraction
    ocr_results = []
    for region in detect_text_regions(frame.image_data):
        text = ocr_engine.extract_text(region)
        ocr_results.append({
            "text": text,
            "bounding_box": region.bbox,
            "confidence": region.confidence
        })
    
    # Normalize image
    normalized_image = normalize_to_model_input(frame.image_data, target_size=(640, 640))
    
    return PreprocessedFrame(
        preprocessed_frame_id=generate_uuid(),
        original_frame_id=frame.frame_id,
        quality_metrics={
            "sharpness": sharpness,
            "contrast": contrast,
            "brightness": brightness,
            "quality_score": quality_score,
            "passed_quality_check": quality_score >= QUALITY_THRESHOLD
        },
        ocr_results=ocr_results,
        normalized_image=normalized_image,
        timestamp=frame.timestamp
    )
```

---

## Stage 2: Detection, Tracking, and Embedding

```python
class DetectionTracker:
    """
    Multi-frame tracker maintaining persistent IDs
    """
    def __init__(self):
        self.active_tracks = {}  # tracker_id -> Track
        self.track_counter = 0
        self.max_track_age = 30  # frames
    
    def update(self, detections: List[Detection]) -> List[TrackedDetection]:
        """
        Assign tracker IDs to detections based on motion and centroids
        """
        # Compute centroids
        centroids = [d.bounding_box.centroid() for d in detections]
        
        # Match detections to existing tracks
        matches = self.hungarian_match(
            self.get_active_centroids(),
            centroids,
            distance_threshold=50  # pixels
        )
        
        tracked_detections = []
        used_tracks = set()
        
        # Process matches
        for track_id, detection_idx in matches:
            track = self.active_tracks[track_id]
            detection = detections[detection_idx]
            
            # Update track
            track.update(detection, now_utc())
            used_tracks.add(track_id)
            
            # Create tracked detection
            motion_vector = track.compute_motion_vector()
            tracked_detections.append(TrackedDetection(
                detection_id=generate_uuid(),
                tracker_id=track_id,
                class_name=detection.class_name,
                confidence=detection.confidence,
                bounding_box=detection.bounding_box,
                motion_vector=motion_vector
            ))
        
        # Create new tracks for unmatched detections
        for i, detection in enumerate(detections):
            if i not in [d[1] for d in matches]:
                self.track_counter += 1
                new_track_id = f"track-{self.track_counter}"
                self.active_tracks[new_track_id] = Track(detection, now_utc())
                
                tracked_detections.append(TrackedDetection(
                    detection_id=generate_uuid(),
                    tracker_id=new_track_id,
                    class_name=detection.class_name,
                    confidence=detection.confidence,
                    bounding_box=detection.bounding_box,
                    motion_vector={"dx": 0, "dy": 0, "confidence": 0}
                ))
        
        # Remove old tracks
        current_time = now_utc()
        for track_id in list(self.active_tracks.keys()):
            if current_time - self.active_tracks[track_id].last_update > self.max_track_age:
                del self.active_tracks[track_id]
        
        return tracked_detections


def run_detection_and_tracking(preprocessed_frame: PreprocessedFrame) -> List[TrackedDetection]:
    """
    Run YOLO-v8 detector and compute embeddings
    """
    # Object detection
    raw_detections = detector_model.predict(preprocessed_frame.normalized_image)
    
    # Filter by confidence
    detections = [
        Detection(
            class_name=det.class_name,
            confidence=det.confidence,
            bounding_box=det.bbox
        )
        for det in raw_detections
        if det.confidence >= DETECTION_CONFIDENCE_THRESHOLD  # e.g., 0.5
    ]
    
    # Tracking
    tracker = DetectionTracker()
    tracked_detections = tracker.update(detections)
    
    # Compute visual embeddings for each detection
    for tracked_det in tracked_detections:
        # Extract detection crop
        crop = extract_crop(
            preprocessed_frame.normalized_image,
            tracked_det.bounding_box
        )
        
        # Compute embedding
        embedding = embedding_model.forward(crop)  # 512-dim vector
        
        tracked_det.visual_signature = {
            "embedding": embedding.tolist(),
            "embedding_model": "resnet50-battery-v1",
            "embedding_dim": 512
        }
    
    return tracked_detections
```

---

## Stage 3: Entity Resolution

```python
def resolve_entity(detection: TrackedDetection, ocr_results: List[OCRResult]) -> EntityResolution:
    """
    Priority-based entity resolution:
    1. Label match (exact/approx serial)
    2. Visual similarity search
    3. Create new entity
    """
    
    # Priority 1: Label-based matching
    for ocr in ocr_results:
        # Try to extract serial/brand patterns
        serial = extract_serial_pattern(ocr.text)
        if serial:
            existing_entity = query_db(
                "SELECT entity_id FROM entities WHERE labels->>'serial' = %s",
                [serial]
            )
            if existing_entity:
                return EntityResolution(
                    entity_id=existing_entity.entity_id,
                    resolution_method="label_match",
                    resolution_confidence=0.98,
                    resolution_details={
                        "serial_matched": serial,
                        "ocr_text": ocr.text,
                        "ocr_confidence": ocr.confidence
                    }
                )
    
    # Priority 2: Visual similarity search (Milvus)
    embedding = detection.visual_signature.embedding
    
    milvus_results = milvus_client.search(
        collection_name="entity_signatures",
        data=[embedding],
        limit=5,
        output_fields=["entity_id", "entity_type", "last_seen"]
    )
    
    if milvus_results and milvus_results[0].distance < VISUAL_SIMILARITY_THRESHOLD:  # e.g., 0.15
        top_match = milvus_results[0]
        similarity = 1.0 - (top_match.distance / 100.0)  # Normalize L2 distance
        
        return EntityResolution(
            entity_id=top_match.entity_id,
            resolution_method="visual_similarity",
            resolution_confidence=similarity,
            resolution_details={
                "top_matches": [
                    {
                        "entity_id": m.entity_id,
                        "similarity": 1.0 - (m.distance / 100.0),
                        "last_seen": m.last_seen
                    }
                    for m in milvus_results
                ]
            }
        )
    
    # Priority 3: Create new entity
    new_entity_id = generate_uuid()
    
    new_entity = Entity(
        entity_id=new_entity_id,
        type=detection.class_name,
        visual_signature_id=generate_uuid(),
        labels={},
        attributes={},
        source=f"detection-{detection.detection_id}",
        confidence=detection.confidence,
        created_at=now_utc()
    )
    
    # Persist to database
    insert_entity_to_postgres(new_entity)
    
    # Add to Milvus index
    milvus_client.insert(
        collection_name="entity_signatures",
        data={
            "entity_id": new_entity_id,
            "visual_embedding": embedding,
            "entity_type": detection.class_name,
            "last_seen": int(now_utc().timestamp() * 1000),
            "metadata": json.dumps({"created": "true"})
        }
    )
    
    return EntityResolution(
        entity_id=new_entity_id,
        resolution_method="new_entity",
        resolution_confidence=0.0,
        resolution_details={"reason": "No match found, entity created"}
    )
```

---

## Stage 4: Attribute Extraction

```python
def extract_attributes(detection: TrackedDetection, detection_crop) -> dict:
    """
    Extract domain-specific attributes from detection
    """
    attributes = {}
    
    # Compute scuffing_score from edge density
    edges = cv2.Canny(detection_crop, 50, 150)
    edge_density = np.sum(edges > 0) / edges.size
    scuffing_score = min(edge_density * 2.0, 1.0)  # Normalize to 0-1
    attributes["scuffing_score"] = scuffing_score
    attributes["scuffing_confidence"] = 0.78  # Model confidence
    
    # Compute wear_score from color fading
    mean_intensity = np.mean(cv2.cvtColor(detection_crop, cv2.COLOR_BGR2GRAY))
    wear_score = 1.0 - (mean_intensity / 255.0)  # Darker = more wear
    attributes["wear_score"] = wear_score
    attributes["wear_confidence"] = 0.72
    
    # Classify color
    color_hist = compute_color_histogram(detection_crop)
    dominant_color = classify_color(color_hist)  # black, white, red, etc.
    attributes["color"] = dominant_color
    attributes["color_confidence"] = 0.94
    
    # Extract text from nearby OCR results
    if len(ocr_results) > 0:
        best_ocr = max(ocr_results, key=lambda x: x.confidence)
        attributes["serial"] = extract_serial_pattern(best_ocr.text)
        attributes["serial_confidence"] = best_ocr.confidence
        attributes["brand"] = extract_brand_pattern(best_ocr.text)
    
    # Location from camera metadata
    attributes["location"] = get_camera_zone(detection.camera_id)
    
    # Aggregate with entity history (moving average)
    entity = get_entity(resolution.entity_id)
    if entity.attributes:
        history_scuffing = entity.attributes.get("scuffing_score_ma", scuffing_score)
        attributes["scuffing_score_ma"] = 0.7 * history_scuffing + 0.3 * scuffing_score
        
        history_wear = entity.attributes.get("wear_score_ma", wear_score)
        attributes["wear_score_ma"] = 0.7 * history_wear + 0.3 * wear_score
    
    # Compute age estimate
    if entity.created_at:
        age_days = (now_utc() - entity.created_at).days
        attributes["age_estimate_days"] = age_days
    
    return attributes
```

---

## Stage 5: Rule Application

```python
class RuleEngine:
    """
    Evaluate rules against entity attributes with explanation traces
    """
    
    def __init__(self, db_connection):
        self.db = db_connection
        self.rule_cache = {}  # In-memory cache of active rules
    
    def load_active_rules(self) -> List[Rule]:
        """
        Load all active rules from database
        """
        if self.rule_cache:
            return self.rule_cache.values()
        
        rows = self.db.query("""
            SELECT * FROM rules 
            WHERE status = 'active' 
              AND retired_at IS NULL
            ORDER BY priority DESC
        """)
        
        rules = [Rule.from_db_row(row) for row in rows]
        self.rule_cache = {rule.rule_id: rule for rule in rules}
        
        return rules
    
    def evaluate_condition(self, condition: str, attributes: dict) -> bool:
        """
        Evaluate a single condition expression
        Examples:
            "age > 2 years" → 930 days > 730 days
            "scuffing_score > 0.5" → 0.72 > 0.5
            "color == 'black'" → "black" == "black"
        """
        # Parse condition
        match = re.match(r'(\w+)\s*(>|<|==|>=|<=)\s*(.+)', condition.strip())
        if not match:
            log_error(f"Invalid condition: {condition}")
            return False
        
        field, operator, threshold_str = match.groups()
        
        # Get field value
        if field not in attributes:
            log_warning(f"Field {field} not in attributes")
            return False
        
        value = attributes[field]
        
        # Parse threshold
        if "years" in threshold_str:
            # Convert to days for age comparisons
            years = float(threshold_str.replace("years", "").strip())
            threshold = years * 365
            value = value  # Already in days
        elif "'" in threshold_str:
            # String comparison
            threshold = threshold_str.strip("'")
        else:
            threshold = float(threshold_str)
        
        # Evaluate
        if operator == ">":
            return value > threshold
        elif operator == "<":
            return value < threshold
        elif operator == "==":
            return value == threshold
        elif operator == ">=":
            return value >= threshold
        elif operator == "<=":
            return value <= threshold
        
        return False
    
    def evaluate_rule(self, rule: Rule, attributes: dict, entity: Entity) -> Optional[RuleMatch]:
        """
        Evaluate all conditions for a rule
        """
        conditions_satisfied = []
        evidence_found = []
        
        # Evaluate all conditions (AND logic)
        for condition in rule.conditions:
            satisfied = self.evaluate_condition(condition, attributes)
            if satisfied:
                conditions_satisfied.append(condition)
            else:
                # One condition failed, rule doesn't match
                return None
        
        # Check evidence clues (supporting signals)
        for clue in rule.evidence_clues:
            if self.evaluate_condition(clue, attributes):
                evidence_found.append(clue)
        
        # Compute match confidence
        if not evidence_found:
            # No supporting evidence, low confidence
            match_confidence = 0.5
        else:
            # Multiple evidence clues found, higher confidence
            match_confidence = min(
                rule.confidence * (len(evidence_found) / len(rule.evidence_clues)),
                1.0
            )
        
        # Generate explanation
        explanation = f"Rule '{rule.predicate}' matched: {', '.join(conditions_satisfied)}. "
        if evidence_found:
            explanation += f"Supporting evidence: {', '.join(evidence_found)}"
        
        return RuleMatch(
            rule_id=rule.rule_id,
            predicate=rule.predicate,
            conditions_satisfied=conditions_satisfied,
            evidence_found=evidence_found,
            match_confidence=match_confidence,
            explanation=explanation
        )
    
    def match(self, entity_id: str, attributes: dict) -> List[RuleMatch]:
        """
        Match entity against all active rules
        """
        entity = get_entity(entity_id)
        rules = self.load_active_rules()
        
        matches = []
        
        for rule in rules:
            try:
                match = self.evaluate_rule(rule, attributes, entity)
                if match:
                    matches.append(match)
            except Exception as e:
                log_error(f"Rule evaluation error {rule.rule_id}: {e}")
        
        # Sort by confidence (highest first)
        matches.sort(key=lambda m: m.match_confidence, reverse=True)
        
        return matches
```

---

## Stage 6: Engagement Decision and Surfacing

```python
class EngagementPolicy:
    """
    Interruption policy: decide when to surface alerts
    """
    
    def __init__(self, redis_client, db_connection):
        self.redis = redis_client
        self.db = db_connection
        self.surface_threshold = 2  # Surface first N times
        self.rate_limit_minutes = 5  # Suppress duplicate alerts
    
    def should_surface(self, rule_match: RuleMatch, entity_id: str) -> bool:
        """
        Apply interruption policy to rule match
        """
        # Check 1: Match confidence above threshold
        if rule_match.match_confidence < 0.65:
            log_debug(f"Rule {rule_match.rule_id} below confidence threshold")
            return False
        
        # Check 2: Rule contradiction state
        rule = self.db.query_one(
            "SELECT contradiction_count, contradiction_threshold FROM rules WHERE rule_id = %s",
            [rule_match.rule_id]
        )
        
        if rule.contradiction_count >= rule.contradiction_threshold:
            log_debug(f"Rule {rule_match.rule_id} in stale state")
            return False
        
        # Check 3: Surface count (surface first N times, then silent)
        cache_key = f"surface_count:{entity_id}:{rule_match.rule_id}"
        surface_count = int(self.redis.get(cache_key) or 0)
        
        if surface_count >= self.surface_threshold:
            log_debug(f"Rule {rule_match.rule_id} has surfaced {surface_count} times (threshold: {self.surface_threshold})")
            return False
        
        # Check 4: Rate limiting (don't surface same alert twice within N minutes)
        rate_limit_key = f"alert_limit:{entity_id}:{rule_match.rule_id}"
        if self.redis.exists(rate_limit_key):
            log_debug(f"Alert rate limited for {entity_id}:{rule_match.rule_id}")
            return False
        
        # All checks passed
        return True
    
    def get_priority_score(self, rule_match: RuleMatch) -> float:
        """
        Compute priority when multiple rules match
        """
        rule = self.db.query_one(
            "SELECT priority, confidence, contradiction_count, contradiction_threshold FROM rules WHERE rule_id = %s",
            [rule_match.rule_id]
        )
        
        priority_score = (
            rule_match.match_confidence * 0.5 +        # 50% match confidence
            (rule.priority / 100.0) * 0.3 +            # 30% rule priority
            (1.0 - rule.contradiction_count / rule.contradiction_threshold) * 0.2  # 20% reliability
        )
        
        return priority_score
    
    def detect_conflicts(self, rule_matches: List[RuleMatch]) -> List[Conflict]:
        """
        Detect conflicting recommendations
        """
        conflict_pairs = [
            ("flag_for_replacement", "keep_operational"),
            ("escalate", "suppress_alert"),
            ("quarantine", "approve_for_use")
        ]
        
        conflicts = []
        actions = {}
        
        # Group rules by action
        for match in rule_matches:
            rule = self.db.query_one(
                "SELECT action FROM rules WHERE rule_id = %s",
                [match.rule_id]
            )
            action = rule.action
            if action not in actions:
                actions[action] = []
            actions[action].append(match)
        
        # Check for conflicts
        for (action1, action2) in conflict_pairs:
            if action1 in actions and action2 in actions:
                conflicts.append(Conflict(
                    action1=action1,
                    action2=action2,
                    rules1=actions[action1],
                    rules2=actions[action2]
                ))
        
        return conflicts
    
    def resolve_conflict(self, conflicts: List[Conflict]) -> RuleMatch:
        """
        Choose best rule when conflicts exist
        """
        all_conflicting = []
        for conflict in conflicts:
            all_conflicting.extend(conflict.rules1)
            all_conflicting.extend(conflict.rules2)
        
        # Score each rule
        scored = [
            (match, self.get_priority_score(match))
            for match in all_conflicting
        ]
        
        # Select highest priority
        winning_match, score = max(scored, key=lambda x: x[1])
        
        return winning_match
```

---

## Stage 7: Full Detection Pipeline

```python
def handle_detection(detection: TrackedDetection, entity_resolution: EntityResolution, 
                     ocr_results: List[OCRResult], preprocessed_frame: PreprocessedFrame) -> EventLog:
    """
    Main pipeline: detection → entity → attributes → rules → engagement → persist
    """
    
    start_time = time.time()
    
    # Get or create entity
    entity_id = entity_resolution.entity_id
    entity = get_entity(entity_id)
    
    # Extract attributes
    detection_crop = extract_crop(preprocessed_frame.normalized_image, detection.bounding_box)
    attributes = extract_attributes(detection, detection_crop)
    
    # Apply rules
    rule_engine = RuleEngine(get_db())
    matched_rules = rule_engine.match(entity_id, attributes)
    
    # Engagement policy
    engagement_policy = EngagementPolicy(get_redis(), get_db())
    rules_to_surface = []
    
    for rule_match in matched_rules:
        if engagement_policy.should_surface(rule_match, entity_id):
            rules_to_surface.append(rule_match)
    
    # Handle conflicts
    if len(rules_to_surface) > 1:
        conflicts = engagement_policy.detect_conflicts(rules_to_surface)
        if conflicts:
            log_warning(f"Conflicts detected: {len(conflicts)}")
            selected_rule = engagement_policy.resolve_conflict(conflicts)
            rules_to_surface = [selected_rule]
    
    # Surface alerts
    surfaced_alerts = []
    for rule_match in rules_to_surface:
        message = format_surface_message(rule_match, entity, attributes)
        user_id = get_entity_owner(entity_id)
        
        send_notification(
            user_id=user_id,
            message=message,
            alert_type=get_rule_alert_type(rule_match.rule_id),
            channel="mobile_push"
        )
        
        surfaced_alerts.append({
            "rule_id": rule_match.rule_id,
            "message": message,
            "confidence": rule_match.match_confidence
        })
        
        # Increment surface count
        cache_key = f"surface_count:{entity_id}:{rule_match.rule_id}"
        self.redis.incr(cache_key)
        self.redis.expire(cache_key, 86400)  # 24 hours
        
        # Set rate limit
        rate_limit_key = f"alert_limit:{entity_id}:{rule_match.rule_id}"
        self.redis.setex(rate_limit_key, 300, "1")  # 5 minutes
    
    # Update entity
    update_entity(
        entity_id=entity_id,
        last_seen=now_utc(),
        attributes=attributes,
        history_append=detection.detection_id
    )
    
    # Persist event log
    event_log = EventLog(
        event_id=generate_uuid(),
        timestamp=now_utc(),
        entity_id=entity_id,
        detection={
            "detection_id": detection.detection_id,
            "type": detection.class_name,
            "confidence": detection.confidence,
            "bounding_box": detection.bounding_box,
            "attributes": attributes
        },
        applied_rules=[m.rule_id for m in matched_rules],
        action="surfaced_rule" if surfaced_alerts else "detection_created",
        source=f"camera-{detection.camera_id}",
        user_feedback=None,
        confidence_overall=max([m.match_confidence for m in matched_rules]) if matched_rules else 0.0,
        processing_ms=int((time.time() - start_time) * 1000),
        tags=["battery", "detection"] if detection.class_name == "battery_pack" else []
    )
    
    insert_event_log(event_log)
    
    return event_log
```

---

## Stage 8: User Feedback and Contradiction Handling

```python
def handle_user_feedback(entity_id: str, rule_id: str, feedback_type: str, 
                        reason: str, user_id: str) -> dict:
    """
    Process user feedback: contradiction, incorrect, correct
    """
    
    # Create correction record
    correction = Correction(
        correction_id=generate_uuid(),
        entity_id=entity_id,
        rule_id=rule_id,
        feedback_type=feedback_type,
        reason=reason,
        corrected_by=user_id,
        corrected_at=now_utc()
    )
    
    insert_correction(correction)
    
    # Handle contradiction
    if feedback_type == "contradiction":
        rule = get_rule(rule_id)
        rule.contradiction_count += 1
        rule.last_contradiction_at = now_utc()
        
        # Update database
        update_rule(
            rule_id=rule_id,
            contradiction_count=rule.contradiction_count,
            last_contradiction_at=rule.last_contradiction_at
        )
        
        # Check if rule should be retired
        if rule.contradiction_count >= rule.contradiction_threshold:
            rule.status = "stale"
            rule.flagged_for_retirement = True
            
            # Emit event
            emit_event("rule_stale", {
                "rule_id": rule_id,
                "contradiction_count": rule.contradiction_count,
                "threshold": rule.contradiction_threshold
            })
            
            # Surface retirement prompt
            send_notification(
                user_id=user_id,
                message=f"Rule '{rule.predicate}' has {rule.contradiction_count} contradictions. "
                        f"Would you like to retire or update it?",
                alert_type="warning",
                action_options=[
                    {"action": "retire_rule", "label": "Retire"},
                    {"action": "update_rule", "label": "Update"},
                    {"action": "keep_rule", "label": "Keep"}
                ]
            )
        
        return {
            "status": "contradiction_recorded",
            "contradiction_count": rule.contradiction_count,
            "rule_status": rule.status if rule.contradiction_count >= rule.contradiction_threshold else "active"
        }
    
    return {"status": "feedback_recorded"}


def handle_rule_update(rule_id: str, changes: dict, reason: str, user_id: str) -> dict:
    """
    Process rule update: merge conditions, soften predicates
    """
    
    old_rule = get_rule(rule_id)
    new_version = old_rule.version + 1
    
    # Generate restatement
    restatement = generate_restatement(old_rule, changes, reason)
    
    # Create new rule version
    new_rule = Rule(
        rule_id=rule_id,  # Same ID for tracking
        predicate=changes.get("predicate", old_rule.predicate),
        conditions=changes.get("conditions", old_rule.conditions),
        evidence_clues=changes.get("evidence_clues", old_rule.evidence_clues),
        action=changes.get("action", old_rule.action),
        priority=changes.get("priority", old_rule.priority),
        version=new_version,
        created_by=old_rule.created_by,
        created_at=old_rule.created_at,
        updated_by=user_id,
        updated_at=now_utc(),
        merged_from=[f"{rule_id}-v{old_rule.version}"],
        restatement=restatement
    )
    
    # Update in database
    update_rule_version(rule_id, new_rule)
    
    # Log merge event
    log_event({
        "event_type": "rule_merged",
        "rule_id": rule_id,
        "old_version": old_rule.version,
        "new_version": new_version,
        "changes": changes,
        "reason": reason,
        "merged_by": user_id
    })
    
    return {
        "rule_id": rule_id,
        "new_version": new_version,
        "restatement": restatement
    }


def generate_restatement(old_rule: Rule, changes: dict, reason: str) -> str:
    """
    Generate human-readable description of rule changes
    """
    statements = []
    
    # Predicate change
    if changes.get("predicate", old_rule.predicate) != old_rule.predicate:
        statements.append(
            f"Rule renamed from '{old_rule.predicate}' to '{changes['predicate']}'"
        )
    
    # Conditions change
    new_conditions = set(changes.get("conditions", old_rule.conditions))
    old_conditions = set(old_rule.conditions)
    added = new_conditions - old_conditions
    if added:
        statements.append(f"Added conditions: {', '.join(added)}")
    
    # Evidence change
    new_evidence = set(changes.get("evidence_clues", old_rule.evidence_clues))
    old_evidence = set(old_rule.evidence_clues)
    added_evidence = new_evidence - old_evidence
    if added_evidence:
        statements.append(f"Added evidence clues: {', '.join(added_evidence)}")
    
    # Action change
    if changes.get("action", old_rule.action) != old_rule.action:
        statements.append(
            f"Action changed from '{old_rule.action}' to '{changes['action']}'"
        )
    
    statements.append(f"Reason: {reason}")
    
    return " ".join(statements)
```

---

## Stage 9: Conflict Resolution Example

```python
def resolve_rule_conflict(entity_id: str, conflicting_rules: List[RuleMatch]) -> dict:
    """
    Example: Battery SN-12345 triggers two conflicting rules
    """
    
    print(f"Resolving conflict for entity {entity_id}")
    print(f"Conflicting rules: {len(conflicting_rules)}")
    
    # Score each rule
    scored_rules = []
    for rule_match in conflicting_rules:
        rule = get_rule(rule_match.rule_id)
        
        priority_score = (
            rule_match.match_confidence * 0.4 +
            (rule.priority / 100.0) * 0.3 +
            (1.0 - rule.contradiction_count / max(rule.contradiction_threshold, 1)) * 0.3
        )
        
        scored_rules.append({
            "rule_id": rule_match.rule_id,
            "predicate": rule_match.predicate,
            "action": rule.action,
            "priority_score": priority_score,
            "confidence": rule_match.match_confidence,
            "explanation": rule_match.explanation
        })
    
    # Sort by priority
    scored_rules.sort(key=lambda x: x["priority_score"], reverse=True)
    
    winning_rule = scored_rules[0]
    
    print(f"Winner: {winning_rule['predicate']} (score: {winning_rule['priority_score']:.2f})")
    
    # Log conflict for later reconciliation
    log_conflict({
        "entity_id": entity_id,
        "conflicting_rules": [r["rule_id"] for r in scored_rules],
        "winning_rule": winning_rule["rule_id"],
        "scores": scored_rules,
        "timestamp": now_utc()
    })
    
    return {
        "winning_rule": winning_rule,
        "losing_rules": scored_rules[1:],
        "resolution_note": f"Rule '{winning_rule['predicate']}' selected with confidence {winning_rule['confidence']:.2f}. "
                          f"Other options available but lower priority."
    }
```

---

## Performance Optimization Examples

```python
def batch_embed_detections(detections: List[TrackedDetection], batch_size: int = 32):
    """
    Batch embedding computation for efficiency
    """
    crops = [extract_crop(frame, det.bbox) for det in detections]
    
    embeddings = []
    for i in range(0, len(crops), batch_size):
        batch = crops[i:i+batch_size]
        batch_embeddings = embedding_model.forward_batch(batch)
        embeddings.extend(batch_embeddings)
    
    for det, embedding in zip(detections, embeddings):
        det.visual_signature.embedding = embedding
    
    return detections


def async_rule_evaluation(entity_id: str, attributes: dict):
    """
    Run rule evaluation asynchronously to avoid blocking
    """
    future = thread_pool.submit(
        rule_engine.match,
        entity_id,
        attributes
    )
    
    # Returns immediately
    return future  # Can be awaited later


def cache_rule_results(rule_id: str, entity_id: str, result: RuleMatch, ttl_seconds: int = 3600):
    """
    Cache rule evaluation results to avoid redundant computation
    """
    cache_key = f"rule_eval:{rule_id}:{entity_id}"
    redis.setex(
        cache_key,
        ttl_seconds,
        json.dumps(result.to_dict())
    )
```

---

## Summary: Complete End-to-End Flow

```python
def process_frame_end_to_end(camera_id: str, frame_source) -> List[EventLog]:
    """
    Complete pipeline from frame capture to event persistence
    """
    
    # Stage 1: Capture
    frame = capture_frame(camera_id, frame_source)
    if not frame:
        return []
    
    # Stage 2: Preprocess
    preprocessed = preprocess_frame(frame)
    if not preprocessed or not preprocessed.passed_quality_check:
        return []
    
    # Stage 3: Detect & Track
    tracked_detections = run_detection_and_tracking(preprocessed)
    if not tracked_detections:
        return []
    
    # Process each detection
    event_logs = []
    
    for detection in tracked_detections:
        try:
            # Stage 4: Resolve Entity
            entity_resolution = resolve_entity(detection, preprocessed.ocr_results)
            
            # Stage 5-7: Handle Detection (attributes → rules → engagement → persist)
            event_log = handle_detection(
                detection,
                entity_resolution,
                preprocessed.ocr_results,
                preprocessed
            )
            
            event_logs.append(event_log)
            
            # Log metrics
            log_metric("detection_processed", 1)
            log_metric("pipeline_latency_ms", event_log.processing_ms)
            
        except Exception as e:
            log_error(f"Detection processing failed: {e}")
            continue
    
    return event_logs
```

This pseudocode provides complete implementation guidance for your vision pipeline.
