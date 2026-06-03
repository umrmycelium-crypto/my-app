#!/bin/bash
# Quick setup for Live Seeing AI + Baserow integration

echo "🍄 Mycelium Live Seeing AI Setup"
echo "================================="
echo ""

# 1. Check Baserow
echo "1. Checking Baserow..."
if curl -s http://localhost:3000 > /dev/null; then
  echo "   ✓ Baserow running on http://localhost:3000"
else
  echo "   ✗ Baserow not accessible"
  exit 1
fi

# 2. Check Rule Engine
echo "2. Checking Rule Engine..."
if curl -s http://localhost:8080/health | grep -q "healthy"; then
  echo "   ✓ Rule Engine running on http://localhost:8080"
else
  echo "   ✗ Rule Engine not healthy"
  exit 1
fi

# 3. Get or generate token
echo ""
echo "3. Baserow API Token:"
if [ -z "$BASEROW_API_TOKEN" ]; then
  echo "   ⚠ BASEROW_API_TOKEN not set"
  echo "   "
  echo "   Generate token:"
  echo "   1. Open http://localhost:3000"
  echo "   2. Settings → API tokens"
  echo "   3. Create token"
  echo "   4. Run: export BASEROW_API_TOKEN='your-token'"
  echo ""
  read -p "   Enter your Baserow API token: " token
  export BASEROW_API_TOKEN=$token
else
  echo "   ✓ Token set: ${BASEROW_API_TOKEN:0:20}..."
fi

# 4. Start integration
echo ""
echo "4. Starting Live Seeing AI integration..."
echo "   Webhook: http://localhost:8080/api/v1/live-seeing-ai/webhook"
echo ""

cd "$(dirname "$0")"
python services/live_seeing_ai_integration.py

echo ""
echo "✓ Setup complete!"
echo ""
echo "Next: Configure Live Seeing AI on iPhone to POST to webhook URL"
