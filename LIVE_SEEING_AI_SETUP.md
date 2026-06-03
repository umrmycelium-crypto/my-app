# Live Seeing AI + Mycelium Integration Setup

## Step 1: Get Baserow API Token

### Option A: From Vault (if available)
```bash
vault kv get secret/baserow/api_token
# Export: export BASEROW_API_TOKEN="your-token"
```

### Option B: Generate New Token
1. Open http://localhost:3000 (Baserow)
2. Admin Settings → API tokens
3. Create new token with access to tables: 191, 196, 200, 201, 515
4. Export: `export BASEROW_API_TOKEN="token-here"`

## Step 2: Configure Live Seeing AI on iPhone

Your **Live Seeing AI** app on your iPhone should be configured to send POST requests to your server.

### Settings in Live Seeing AI
```
Settings → API Integration
─────────────────────────
API Endpoint: http://<your-server-ip>:8080/api/v1/live-seeing-ai/webhook
(or via Tailscale: http://<tailscale-ip>:8080/api/v1/live-seeing-ai/webhook)

Authorization: Bearer {LIVE_SEEING_AI_SECRET}
Capture Format: JSON with image_base64, detected_objects, description
Frame Rate: 1 fps (adjustable)
```

### Payload Format
```json
{
  "timestamp": "2026-06-03T14:30:00Z",
  "description": "Person detected in kitchen",
  "image_base64": "...",
  "image_hash": "sha256:...",
  "detected_objects": [
    {
      "type": "person",
      "confidence": 0.95,
      "location": "center",
      "attributes": {"pose": "standing"}
    },
    {
      "type": "coffee_cup",
      "confidence": 0.87,
      "location": "left_side"
    }
  ],
  "device": "iPhone 14 Pro"
}
```

## Step 3: Data Flow

```
Live Seeing AI (iPhone Camera)
    ↓ (POST to webhook)
Rule Engine (/api/v1/detect)
    ↓ (creates entity)
PostgreSQL + Milvus + Elasticsearch
    ↓ (stores)
Baserow tables (raw_captures table 515)
    ↓ (reads)
"The One" Admin Dashboard
```

## Step 4: Start Integration Service

```bash
cd /Users/marcu/mycelium-core
export BASEROW_API_TOKEN="your-token"
export LIVE_SEEING_AI_SECRET="webhook-secret"

# Run integration service
python services/live_seeing_ai_integration.py
```

Or add to docker-compose-unified.yml:
```yaml
live-seeing-ai-integration:
  build:
    context: .
    dockerfile: services/live_seeing_ai_integration/Dockerfile
  environment:
    BASEROW_API_TOKEN: ${BASEROW_API_TOKEN}
    LIVE_SEEING_AI_SECRET: ${LIVE_SEEING_AI_SECRET}
  ports:
    - "5001:5001"
  depends_on:
    - my-app-rule-engine
    - baserow
  networks:
    - mycelium
```

## Step 5: Verify Integration

```bash
# Check webhook status
curl http://localhost:8080/api/v1/live-seeing-ai/status

# Check Baserow table 515 for captures
curl -H "Authorization: Token $BASEROW_API_TOKEN" \
  http://localhost:3000/api/database/rows/table/515/

# Test with sample frame
curl -X POST http://localhost:8080/api/v1/live-seeing-ai/webhook \
  -H "Content-Type: application/json" \
  -d '{
    "timestamp": "2026-06-03T14:30:00Z",
    "description": "Test capture",
    "detected_objects": [{"type": "test", "confidence": 0.9}],
    "device": "iPhone"
  }'
```

## Step 6: Deploy ghost-talk to iPhone

Your iPhone should already have **ghost-link/ghost-talk** installed.

### To rebuild and deploy:

1. **On the-studio (macOS with Xcode):**
```bash
cd /path/to/ghost-link

# Pull latest
git pull origin main

# Open in Xcode
xcode projects/ghost-talk.xcodeproj

# Select iPhone as target
# Cmd+R to build & run
```

2. **Configure endpoint in ghost-talk:**
   - Settings → API Server
   - Use Tailscale IP: http://100.102.238.109:8080
   - Or local IP if on same network: http://192.168.x.x:8080

### Connect ghost-talk to mycelium-core:
```swift
// In ghost-talk app settings
let apiEndpoint = "http://100.102.238.109:8080"  // Tailscale
let ruleEngineAPI = "/api/v1/detect"

// Send detection from iPhone camera
let detection = Detection(
  type: "live_seeing_ai_capture",
  attributes: ["device": "iPhone", "description": "..."],
  confidence: 0.95
)

await apiClient.submit(detection)
```

## Expected Behavior

After setup:

1. **iPhone camera captures** → Live Seeing AI detects objects
2. **POST webhook** → mycelium-core receives frame
3. **Rule Engine processes** → creates entity, calculates confidence
4. **Baserow stores** → table 515 (raw_captures) updates
5. **"The One" dashboard** → shows new captures in real-time
6. **ghost-talk app** → displays status ✓ "Connected to mycelium-core"

## Baserow Tables

| Table ID | Name | Purpose |
|----------|------|---------|
| 515 | Raw Captures | Video frames from Live Seeing AI |
| 191 | Contacts | Entity references |
| 196 | Opportunities | Detected patterns |
| 200 | Follow-ups | Action items |
| 201 | Projects | Project assignments |

## Troubleshooting

### "We have not set it up yet" message
- [ ] Baserow API token not set → export BASEROW_API_TOKEN
- [ ] Live Seeing AI webhook URL misconfigured → verify endpoint
- [ ] Rule Engine not running → docker ps | grep rule-engine
- [ ] Network unreachable → check firewall/Tailscale

### Frames not appearing in Baserow
```bash
# Check Rule Engine logs
docker logs my-app-rule-engine

# Check Baserow connection
curl -H "Authorization: Token $BASEROW_API_TOKEN" \
  http://localhost:3000/api/user/

# Test webhook directly
curl -X POST http://localhost:8080/api/v1/live-seeing-ai/webhook \
  -d '{"detected_objects": [], "description": "test"}'
```

### iPhone app won't connect
- Use Tailscale IP (100.102.238.109:8080) not localhost
- Check iPhone is on same Tailscale network
- Verify firewall allows port 8080

---

**Status**: Ready for Live Seeing AI integration
**Last Updated**: 2026-06-03
