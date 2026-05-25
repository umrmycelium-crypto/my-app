"""
Enhanced Rule Engine Microservice with Rule Matching Logic
Supports condition evaluation, contradiction tracking, and feedback handling
"""

from fastapi import FastAPI, HTTPException, BackgroundTasks
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
from typing import List, Dict, Optional
import psycopg2
from psycopg2.extras import RealDictCursor
import redis
import os
import json
import logging
import re
from uuid import uuid4
from datetime import datetime, timedelta
from contextlib import contextmanager

# Setup logging
logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))
logger = logging.getLogger(__name__)

# FastAPI app
app = FastAPI(
    title="Vision Rule Engine",
    version="1.0.0",
    description="Rule matching, contradiction tracking, and engagement decisions"
)

# ============================================================================
# Database and Cache Configuration
# ============================================================================

POSTGRES_CONN = os.getenv("POSTGRES_CONN")
REDIS_HOST = os.getenv("REDIS_HOST", "redis-master")
REDIS_PORT = int(os.getenv("REDIS_PORT", 6379))

@contextmanager
def get_db():
    """Database connection context manager"""
    conn = psycopg2.connect(POSTGRES_CONN)
    try:
        yield conn
    finally:
        conn.close()

def get_redis():
    """Get Redis connection"""
    return redis.Redis(
        host=REDIS_HOST,
        port=REDIS_PORT,
        decode_responses=True
    )

# ============================================================================
# Data Models
# ============================================================================

class Detection(BaseModel):
    entity_id: Optional[str] = None
    type: str
    attributes: Dict = Field(default_factory=dict)
    confidence: float

class Feedback(BaseModel):
    rule_id: str
    feedback: str  # confirm | contradiction | ignore
    entity_id: Optional[str] = None
    reason: Optional[str] = None

class RuleUpdate(BaseModel):
    rule_id: str
    changes: Dict
    reason: str
    user_id: str

class RuleMatch(BaseModel):
    rule_id: str
    predicate: str
    conditions_satisfied: List[str]
    evidence_found: List[str]
    match_confidence: float
    explanation: str

# ============================================================================
# Rule Engine Logic
# ============================================================================

class RuleEngine:
    """Evaluates rules against entity attributes"""
    
    def __init__(self):
        self.rule_cache = {}
        self.cache_expiry = 3600  # 1 hour
    
    def load_active_rules(self, force_refresh=False) -> List[Dict]:
        """Load active rules from database with caching"""
        cache_key = "active_rules"
        redis_conn = get_redis()
        
        # Try cache first
        if not force_refresh:
            cached = redis_conn.get(cache_key)
            if cached:
                return json.loads(cached)
        
        # Load from database
        with get_db() as conn:
            cur = conn.cursor(cursor_factory=RealDictCursor)
            cur.execute("""
                SELECT * FROM rules 
                WHERE status = 'active' 
                  AND retired_at IS NULL
                ORDER BY priority DESC
            """)
            rules = cur.fetchall()
        
        # Cache results
        rules_list = [dict(r) for r in rules]
        redis_conn.setex(cache_key, self.cache_expiry, json.dumps(rules_list, default=str))
        
        return rules_list
    
    def evaluate_condition(self, condition: str, attributes: Dict) -> tuple:
        """
        Evaluate a single condition expression
        Returns: (result: bool, field: str, value: float, threshold: float)
        
        Examples:
            "age > 730" → (930 > 730) = True
            "scuffing_score > 0.5" → (0.72 > 0.5) = True
            "color == 'black'" → ("black" == "black") = True
        """
        try:
            # Parse condition: "field operator value"
            match = re.match(r'(\w+)\s*(>|<|==|>=|<=|!=)\s*(.+)', condition.strip())
            if not match:
                logger.warning(f"Invalid condition format: {condition}")
                return False, "", None, None
            
            field, operator, threshold_str = match.groups()
            
            # Get field value
            if field not in attributes:
                logger.debug(f"Field '{field}' not in attributes")
                return False, field, None, None
            
            value = attributes[field]
            
            # Parse threshold
            if "'" in threshold_str or '"' in threshold_str:
                # String comparison
                threshold = threshold_str.strip("'\"")
            else:
                # Numeric comparison
                try:
                    threshold = float(threshold_str)
                except ValueError:
                    threshold = threshold_str
            
            # Evaluate
            if operator == ">":
                result = value > threshold
            elif operator == "<":
                result = value < threshold
            elif operator == "==":
                result = value == threshold
            elif operator == ">=":
                result = value >= threshold
            elif operator == "<=":
                result = value <= threshold
            elif operator == "!=":
                result = value != threshold
            else:
                result = False
            
            return result, field, value, threshold
        
        except Exception as e:
            logger.error(f"Error evaluating condition '{condition}': {e}")
            return False, "", None, None
    
    def match_rules(self, entity_id: str, attributes: Dict) -> List[RuleMatch]:
        """Match all active rules against entity attributes"""
        matches = []
        rules = self.load_active_rules()
        
        for rule in rules:
            try:
                # Get rule data
                rule_id = rule['rule_id']
                predicate = rule['predicate']
                conditions = rule['conditions']
                evidence_clues = rule['evidence_clues']
                confidence = rule['confidence']
                
                # Parse JSON fields
                if isinstance(conditions, str):
                    conditions = json.loads(conditions)
                if isinstance(evidence_clues, str):
                    evidence_clues = json.loads(evidence_clues)
                
                # Evaluate all conditions (AND logic)
                conditions_satisfied = []
                for condition in conditions:
                    result, field, value, threshold = self.evaluate_condition(condition, attributes)
                    if result:
                        conditions_satisfied.append(condition)
                    else:
                        # One condition failed, rule doesn't match
                        break
                
                if len(conditions_satisfied) != len(conditions):
                    # Not all conditions satisfied
                    continue
                
                # Check evidence clues (supporting signals)
                evidence_found = []
                for clue in evidence_clues:
                    result, _, _, _ = self.evaluate_condition(clue, attributes)
                    if result:
                        evidence_found.append(clue)
                
                # Compute match confidence
                if not evidence_found:
                    match_confidence = 0.5  # Conditions met but no supporting evidence
                else:
                    # Confidence increases with number of supporting clues
                    evidence_ratio = len(evidence_found) / max(len(evidence_clues), 1)
                    match_confidence = min(confidence * evidence_ratio, 1.0)
                
                # Generate explanation
                explanation = f"Rule '{predicate}' matched: conditions {conditions_satisfied}. "
                if evidence_found:
                    explanation += f"Supporting evidence: {evidence_found}"
                else:
                    explanation += "No supporting evidence."
                
                # Create match
                match = RuleMatch(
                    rule_id=str(rule_id),
                    predicate=predicate,
                    conditions_satisfied=conditions_satisfied,
                    evidence_found=evidence_found,
                    match_confidence=match_confidence,
                    explanation=explanation
                )
                
                matches.append(match)
                logger.info(f"Rule {predicate} matched for entity {entity_id}")
            
            except Exception as e:
                logger.error(f"Error evaluating rule {rule.get('rule_id')}: {e}")
                continue
        
        # Sort by confidence
        matches.sort(key=lambda m: m.match_confidence, reverse=True)
        return matches

# ============================================================================
# API Endpoints
# ============================================================================

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    try:
        with get_db() as conn:
            conn.cursor().execute("SELECT 1")
        return {"status": "healthy", "database": "connected"}
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        return {"status": "unhealthy", "database": "disconnected"}, 503

@app.post("/api/v1/detect")
async def detect(detection: Detection, background_tasks: BackgroundTasks):
    """
    Submit a detection: insert/update entity and apply rules
    """
    try:
        entity_id = detection.entity_id or str(uuid4())
        
        with get_db() as conn:
            cur = conn.cursor()
            
            # Insert or update entity
            cur.execute("""
                INSERT INTO entities (entity_id, type, attributes, confidence, last_seen)
                VALUES (%s, %s, %s, %s, NOW())
                ON CONFLICT (entity_id) DO UPDATE SET
                    attributes = EXCLUDED.attributes,
                    confidence = EXCLUDED.confidence,
                    last_seen = NOW()
            """, (entity_id, detection.type, json.dumps(detection.attributes), detection.confidence))
            
            conn.commit()
        
        # Apply rules in background
        background_tasks.add_task(apply_rules_task, entity_id, detection.attributes)
        
        logger.info(f"Detection created: entity_id={entity_id}, type={detection.type}")
        
        return {
            "entity_id": entity_id,
            "status": "created",
            "attributes": detection.attributes
        }
    
    except Exception as e:
        logger.error(f"Detection failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))

async def apply_rules_task(entity_id: str, attributes: Dict):
    """Background task: apply rules and handle engagement decisions"""
    try:
        engine = RuleEngine()
        matches = engine.match_rules(entity_id, attributes)
        
        # Store matches in database
        with get_db() as conn:
            cur = conn.cursor()
            for match in matches:
                cur.execute("""
                    INSERT INTO events (entity_id, action, applied_rules, detection, user_feedback)
                    VALUES (%s, %s, %s, %s, %s)
                """, (
                    entity_id,
                    "rule_matched",
                    json.dumps([match.rule_id]),
                    json.dumps({"explanation": match.explanation, "confidence": match.match_confidence}),
                    None
                ))
            conn.commit()
        
        logger.info(f"Applied {len(matches)} rules for entity {entity_id}")
    
    except Exception as e:
        logger.error(f"Rule application failed: {e}")

@app.post("/api/v1/rules/match")
async def match_rules(entity_id: str, attributes: Dict):
    """
    Synchronously match rules for an entity
    """
    try:
        engine = RuleEngine()
        matches = engine.match_rules(entity_id, attributes)
        
        return {
            "entity_id": entity_id,
            "matched_rules": [match.dict() for match in matches],
            "total_matches": len(matches)
        }
    
    except Exception as e:
        logger.error(f"Rule matching failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/v1/feedback")
async def handle_feedback(feedback: Feedback):
    """
    Handle user feedback on rules
    """
    try:
        with get_db() as conn:
            cur = conn.cursor()
            
            if feedback.feedback == "contradiction":
                # Increment contradiction counter
                cur.execute("""
                    UPDATE rules 
                    SET contradiction_count = contradiction_count + 1,
                        last_contradiction_at = NOW()
                    WHERE rule_id = %s
                    RETURNING contradiction_count, contradiction_threshold
                """, (feedback.rule_id,))
                
                result = cur.fetchone()
                if result:
                    contradiction_count, threshold = result
                    
                    # Check if rule should be retired
                    if contradiction_count >= threshold:
                        cur.execute("""
                            UPDATE rules 
                            SET status = 'stale', flagged_for_retirement = true
                            WHERE rule_id = %s
                        """, (feedback.rule_id,))
                        
                        logger.info(f"Rule {feedback.rule_id} flagged as stale (contradictions: {contradiction_count})")
                        
                        conn.commit()
                        return {
                            "status": "stale_flagged",
                            "contradiction_count": contradiction_count,
                            "rule_status": "stale"
                        }
                
                conn.commit()
            
            # Log feedback event
            cur.execute("""
                INSERT INTO events (entity_id, action, applied_rules, user_feedback)
                VALUES (%s, %s, %s, %s)
            """, (feedback.entity_id, "feedback_received", json.dumps([feedback.rule_id]), feedback.feedback))
            
            conn.commit()
        
        logger.info(f"Feedback recorded: entity_id={feedback.entity_id}, rule_id={feedback.rule_id}, feedback={feedback.feedback}")
        
        return {"status": "feedback_recorded", "feedback_type": feedback.feedback}
    
    except Exception as e:
        logger.error(f"Feedback handling failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/v1/rule/update")
async def update_rule(update: RuleUpdate):
    """
    Update rule with merge logic
    """
    try:
        with get_db() as conn:
            cur = conn.cursor()
            
            # Get existing rule
            cur.execute("SELECT version, predicate FROM rules WHERE rule_id = %s", (update.rule_id,))
            result = cur.fetchone()
            
            if not result:
                raise HTTPException(status_code=404, detail="Rule not found")
            
            old_version = result[0]
            new_version = old_version + 1
            
            # Update rule
            cur.execute("""
                UPDATE rules 
                SET predicate = %s,
                    conditions = %s,
                    evidence_clues = %s,
                    action = %s,
                    priority = %s,
                    version = %s,
                    updated_by = %s,
                    updated_at = NOW()
                WHERE rule_id = %s
            """, (
                update.changes.get("predicate"),
                json.dumps(update.changes.get("conditions", [])),
                json.dumps(update.changes.get("evidence_clues", [])),
                update.changes.get("action"),
                update.changes.get("priority", 50),
                new_version,
                update.user_id,
                update.rule_id
            ))
            
            conn.commit()
        
        logger.info(f"Rule {update.rule_id} updated to version {new_version}")
        
        # Invalidate cache
        redis_conn = get_redis()
        redis_conn.delete("active_rules")
        
        return {
            "rule_id": update.rule_id,
            "new_version": new_version,
            "status": "updated"
        }
    
    except Exception as e:
        logger.error(f"Rule update failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/v1/rules/pending")
async def get_pending_rules():
    """
    Get rules pending retirement or update
    """
    try:
        with get_db() as conn:
            cur = conn.cursor(cursor_factory=RealDictCursor)
            
            # Get stale rules
            cur.execute("""
                SELECT rule_id, predicate, contradiction_count, match_count,
                       (contradiction_count::float / NULLIF(match_count, 0)) as contradiction_ratio
                FROM rules
                WHERE contradiction_count >= contradiction_threshold
                  AND status != 'retired'
                  AND retired_at IS NULL
                ORDER BY contradiction_count DESC
            """)
            
            stale_rules = [dict(r) for r in cur.fetchall()]
        
        return {
            "stale_rules": stale_rules,
            "total_stale": len(stale_rules)
        }
    
    except Exception as e:
        logger.error(f"Failed to get pending rules: {e}")
        raise HTTPException(status_code=500, detail=str(e))

# ============================================================================
# Startup and Shutdown
# ============================================================================

@app.on_event("startup")
async def startup_event():
    """Startup tasks"""
    logger.info("Rule Engine starting up")
    try:
        with get_db() as conn:
            conn.cursor().execute("SELECT 1")
        logger.info("Database connection successful")
    except Exception as e:
        logger.error(f"Database connection failed: {e}")
        raise

@app.on_event("shutdown")
async def shutdown_event():
    """Shutdown tasks"""
    logger.info("Rule Engine shutting down")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
