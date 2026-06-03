"""
Live Seeing AI → Mycelium Integration
Processes video input from Live Seeing AI and stores in Baserow + Rule Engine
"""

import requests
import json
import os
from datetime import datetime
from typing import Dict, Optional

class LiveSeeingAIIntegration:
    def __init__(self):
        # Baserow configuration
        self.baserow_url = "http://localhost:3000/api"
        self.baserow_token = os.getenv("BASEROW_API_TOKEN", "your-token-here")
        
        # Rule Engine configuration
        self.rule_engine_url = "http://localhost:8080"
        
        # Baserow table IDs (from "The One" dashboard)
        self.tables = {
            "raw_captures": 515,
            "contacts": 191,
            "opportunities": 196,
            "follow_ups": 200,
            "projects": 201
        }
        
        # Live Seeing AI webhook secret
        self.webhook_secret = os.getenv("LIVE_SEEING_AI_SECRET", "webhook-secret")

    def setup_baserow_token(self, email: str, password: str) -> str:
        """
        Generate Baserow API token from credentials
        """
        response = requests.post(
            f"{self.baserow_url}/auth/login/",
            json={"email": email, "password": password}
        )
        
        if response.status_code == 200:
            token = response.json().get("auth_token")
            print(f"✓ Baserow token acquired: {token[:20]}...")
            return token
        else:
            raise Exception(f"Failed to authenticate with Baserow: {response.text}")

    def process_live_seeing_ai_frame(self, frame_data: Dict) -> Dict:
        """
        Process video frame from Live Seeing AI
        
        frame_data expected:
        {
            "image_base64": "...",
            "detected_objects": [{"type": "...", "confidence": 0.95}],
            "description": "...",
            "timestamp": "2026-06-03T14:30:00Z"
        }
        """
        try:
            # 1. Send to Rule Engine for processing
            rule_engine_response = self._process_with_rule_engine(frame_data)
            
            # 2. Store in Baserow raw_captures table
            baserow_response = self._store_in_baserow(frame_data, rule_engine_response)
            
            # 3. Extract entities and store separately
            entities = self._extract_entities(frame_data, rule_engine_response)
            
            return {
                "success": True,
                "rule_engine_id": rule_engine_response.get("entity_id"),
                "baserow_id": baserow_response.get("id"),
                "entities": entities,
                "timestamp": datetime.utcnow().isoformat()
            }
        
        except Exception as e:
            print(f"✗ Error processing frame: {str(e)}")
            return {
                "success": False,
                "error": str(e),
                "timestamp": datetime.utcnow().isoformat()
            }

    def _process_with_rule_engine(self, frame_data: Dict) -> Dict:
        """
        Send frame to Rule Engine for entity detection and classification
        """
        payload = {
            "type": "live_seeing_ai_capture",
            "attributes": {
                "description": frame_data.get("description", ""),
                "detected_objects": json.dumps(frame_data.get("detected_objects", [])),
                "image_hash": frame_data.get("image_hash", ""),
                "device": frame_data.get("device", "iPhone")
            },
            "confidence": self._calculate_confidence(frame_data)
        }
        
        response = requests.post(
            f"{self.rule_engine_url}/api/v1/detect",
            json=payload,
            headers={"Content-Type": "application/json"}
        )
        
        if response.status_code == 200:
            return response.json()
        else:
            raise Exception(f"Rule Engine error: {response.text}")

    def _store_in_baserow(self, frame_data: Dict, rule_engine_response: Dict) -> Dict:
        """
        Store frame data in Baserow raw_captures table
        """
        headers = {
            "Authorization": f"Token {self.baserow_token}",
            "Content-Type": "application/json"
        }
        
        payload = {
            "Timestamp": frame_data.get("timestamp", datetime.utcnow().isoformat()),
            "Description": frame_data.get("description", ""),
            "Detected Objects": json.dumps(frame_data.get("detected_objects", [])),
            "Confidence": self._calculate_confidence(frame_data),
            "Device": frame_data.get("device", "iPhone"),
            "Rule Engine ID": rule_engine_response.get("entity_id", ""),
            "Source": "Live Seeing AI",
            "Status": "captured"
        }
        
        response = requests.post(
            f"{self.baserow_url}/database/rows/table/{self.tables['raw_captures']}/",
            json=payload,
            headers=headers
        )
        
        if response.status_code in [200, 201]:
            return response.json()
        else:
            raise Exception(f"Baserow error: {response.text}")

    def _extract_entities(self, frame_data: Dict, rule_engine_response: Dict) -> list:
        """
        Extract individual entities from detected objects
        """
        entities = []
        
        for obj in frame_data.get("detected_objects", []):
            entity = {
                "type": obj.get("type", "unknown"),
                "confidence": obj.get("confidence", 0.0),
                "rule_engine_id": rule_engine_response.get("entity_id"),
                "captured_at": frame_data.get("timestamp", datetime.utcnow().isoformat())
            }
            entities.append(entity)
        
        return entities

    def _calculate_confidence(self, frame_data: Dict) -> float:
        """
        Calculate overall confidence from detected objects
        """
        objects = frame_data.get("detected_objects", [])
        if not objects:
            return 0.0
        
        avg_confidence = sum(obj.get("confidence", 0) for obj in objects) / len(objects)
        return min(avg_confidence, 0.99)

    def setup_webhook(self) -> str:
        """
        Generate webhook URL for Live Seeing AI to POST frames
        """
        webhook_url = "http://localhost:8080/api/v1/live-seeing-ai/webhook"
        print(f"\n✓ Configure Live Seeing AI to POST to: {webhook_url}")
        print(f"  Use header: Authorization: Bearer {self.webhook_secret}")
        return webhook_url

    def get_dashboard_data(self) -> Dict:
        """
        Retrieve data for "The One" admin dashboard
        """
        headers = {
            "Authorization": f"Token {self.baserow_token}"
        }
        
        # Get recent captures
        captures_response = requests.get(
            f"{self.baserow_url}/database/rows/table/{self.tables['raw_captures']}/?limit=10",
            headers=headers
        )
        
        data = {
            "total_captures": captures_response.json().get("count", 0) if captures_response.status_code == 200 else 0,
            "recent_captures": captures_response.json().get("results", []) if captures_response.status_code == 200 else [],
            "status": "active" if captures_response.status_code == 200 else "degraded"
        }
        
        return data


# Flask endpoint wrapper for Live Seeing AI webhook
def create_flask_app():
    from flask import Flask, request, jsonify
    
    app = Flask(__name__)
    integration = LiveSeeingAIIntegration()
    
    @app.route("/api/v1/live-seeing-ai/webhook", methods=["POST"])
    def live_seeing_ai_webhook():
        """
        Receive video frames from Live Seeing AI on iPhone
        """
        try:
            frame_data = request.json
            result = integration.process_live_seeing_ai_frame(frame_data)
            return jsonify(result), 200 if result.get("success") else 400
        except Exception as e:
            return jsonify({"error": str(e)}), 500
    
    @app.route("/api/v1/live-seeing-ai/status", methods=["GET"])
    def live_seeing_ai_status():
        """
        Get integration status
        """
        return jsonify({
            "status": "ready",
            "baserow_connected": True,
            "rule_engine_connected": True,
            "webhook_url": integration.setup_webhook()
        })
    
    return app


if __name__ == "__main__":
    integration = LiveSeeingAIIntegration()
    
    # Setup (run once)
    print("Live Seeing AI Integration Setup")
    print("=" * 50)
    
    # Option 1: Use stored token
    print("\n1. Using stored BASEROW_API_TOKEN from environment")
    
    # Option 2: Generate new token
    print("\n2. Or generate new token:")
    print("   export BASEROW_API_TOKEN=$(python -c ...)")
    
    # Show webhook URL
    print("\n3. Configure Live Seeing AI:")
    integration.setup_webhook()
    
    # Start Flask server
    print("\n4. Starting webhook server...")
    app = create_flask_app()
    app.run(host="0.0.0.0", port=5001, debug=False)
