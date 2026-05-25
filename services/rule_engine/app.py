from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import psycopg2
import os
import json
import uuid
from datetime import datetime

app = FastAPI(title="Rule Engine")

# Database connection
POSTGRES_CONN = os.getenv("POSTGRES_CONN", "postgresql://pgadmin:examplepassword@postgres:5432/visiondb")

def get_db():
    try:
        return psycopg2.connect(POSTGRES_CONN)
    except Exception as e:
        print(f"DB Connection error: {e}")
        return None

class Detection(BaseModel):
    entity_id: str = None
    type: str
    attributes: dict
    confidence: float

class Feedback(BaseModel):
    rule_id: str
    feedback: str
    entity_id: str = None

@app.get("/health")
async def health():
    try:
        conn = get_db()
        if conn:
            conn.close()
            return {"status": "healthy"}
        raise HTTPException(status_code=503, detail="Database connection failed")
    except Exception as e:
        raise HTTPException(status_code=503, detail=str(e))

@app.post("/api/v1/detect")
async def detect(detection: Detection):
    try:
        conn = get_db()
        if not conn:
            raise HTTPException(status_code=500, detail="Database connection failed")
        
        cur = conn.cursor()
        entity_id = detection.entity_id or str(uuid.uuid4())
        
        cur.execute("""
            INSERT INTO entities (entity_id, type, attributes, confidence, last_seen)
            VALUES (%s, %s, %s, %s, NOW())
            ON CONFLICT (entity_id) DO UPDATE SET
                attributes = EXCLUDED.attributes,
                confidence = EXCLUDED.confidence,
                last_seen = NOW()
        """, (entity_id, detection.type, json.dumps(detection.attributes), detection.confidence))
        
        conn.commit()
        conn.close()
        
        return {"entity_id": entity_id, "status": "created"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/v1/feedback")
async def feedback(feedback: Feedback):
    try:
        conn = get_db()
        if not conn:
            raise HTTPException(status_code=500, detail="Database connection failed")
        
        cur = conn.cursor()
        
        if feedback.feedback == "contradiction":
            cur.execute("""
                UPDATE rules 
                SET contradiction_count = contradiction_count + 1,
                    last_contradiction_at = NOW()
                WHERE rule_id = %s
            """, (feedback.rule_id,))
        
        conn.commit()
        conn.close()
        
        return {"status": "recorded"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
