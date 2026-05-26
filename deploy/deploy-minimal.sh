#!/bin/bash

# Minimal Mycelium Deployment - No system updates
# Use this if deploy.sh fails due to system issues

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then 
  echo -e "${RED}Error: Please run as root (use sudo)${NC}"
  exit 1
fi

echo -e "${YELLOW}Minimal Mycelium Deployment${NC}"
echo ""

# Step 1: Start Docker
echo -e "${YELLOW}Starting Docker...${NC}"
systemctl start docker 2>/dev/null || {
  echo -e "${RED}Docker not running and cannot start${NC}"
  echo "Manual fix:"
  echo "  sudo dnf install docker-ce"
  echo "  sudo systemctl start docker"
  exit 1
}

# Wait for Docker
for i in {1..10}; do
  if docker ps &>/dev/null; then
    echo -e "${GREEN}✓ Docker ready${NC}"
    break
  fi
  sleep 1
done

# Step 2: Navigate to repo
if [ -d "/opt/mycelium/my-app/deploy" ]; then
  cd /opt/mycelium/my-app/deploy
elif [ -d "./deploy" ]; then
  cd ./deploy
else
  echo -e "${RED}Cannot find deploy directory${NC}"
  echo "Please run from my-app root or ensure /opt/mycelium/my-app exists"
  exit 1
fi

# Step 3: Create .env if missing
if [ ! -f ".env" ]; then
  echo -e "${YELLOW}Creating .env...${NC}"
  cat > .env << 'EOF'
POSTGRES_PASSWORD=mycelium-prod-$(date +%s)
DB_USER=admin
DB_PASSWORD=mycelium-db-$(date +%s)
REDIS_PASSWORD=redis-$(date +%s)
NODE_ENV=production
LOG_LEVEL=info
EOF
fi

# Step 4: Deploy
echo -e "${YELLOW}Deploying services...${NC}"
docker compose -f docker-compose-production.yml up -d

echo ""
echo -e "${GREEN}✓ Deployment started${NC}"
echo "Check status: docker compose -f docker-compose-production.yml ps"
echo "View logs: docker compose -f docker-compose-production.yml logs -f"
