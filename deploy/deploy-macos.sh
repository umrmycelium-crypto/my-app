#!/bin/bash

# Mycelium Ecosystem Deployment for macOS (the-studio)
# Uses Docker Desktop which is pre-installed
# Usage: bash deploy-macos.sh

set -e

echo "======================================"
echo "Mycelium Ecosystem Deployment"
echo "macOS + Docker Desktop"
echo "======================================"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 1. Check Docker
echo -e "${YELLOW}[1/5] Checking Docker...${NC}"

if ! command -v docker &> /dev/null; then
  echo -e "${RED}Docker not found. Install Docker Desktop from https://www.docker.com/products/docker-desktop${NC}"
  exit 1
fi

if ! docker ps &>/dev/null; then
  echo -e "${RED}Docker daemon not running. Start Docker Desktop.${NC}"
  exit 1
fi

echo -e "${GREEN}✓ Docker ready${NC}"
docker --version

# 2. Verify repo
echo -e "${YELLOW}[2/5] Verifying repository...${NC}"

if [ ! -d "./deploy" ]; then
  echo -e "${RED}Error: Run from my-app root directory${NC}"
  exit 1
fi

cd deploy

echo -e "${GREEN}✓ Repository ready${NC}"

# 3. Configure environment
echo -e "${YELLOW}[3/5] Configuring environment...${NC}"

if [ ! -f ".env" ]; then
  POSTGRES_PASS=$(openssl rand -hex 8)
  DB_PASS=$(openssl rand -hex 8)
  REDIS_PASS=$(openssl rand -hex 16)

  cat > .env << EOF
POSTGRES_PASSWORD=$POSTGRES_PASS
DB_USER=admin
DB_PASSWORD=$DB_PASS
REDIS_PASSWORD=$REDIS_PASS
NODE_ENV=production
LOG_LEVEL=info
EOF
fi

echo -e "${GREEN}✓ Environment configured${NC}"

# 4. Create Caddy config
echo -e "${YELLOW}[4/5] Setting up reverse proxy...${NC}"

mkdir -p caddy

cat > caddy/Caddyfile << 'CADDY'
:80 {
  handle /api/v1* {
    reverse_proxy my-app-rule-engine:8080
  }
  handle /gateway* {
    reverse_proxy the-gateway:3012
  }
  handle /switch* {
    reverse_proxy switchisland:3006
  }
  handle /spore* {
    reverse_proxy spore-scribe:3010
  }
  handle /renewal* {
    reverse_proxy renewal-core:3011
  }
  handle /mail* {
    reverse_proxy mailhog:8025
  }
  respond "Mycelium Ecosystem Online"
}
CADDY

echo -e "${GREEN}✓ Reverse proxy configured${NC}"

# 5. Deploy services
echo -e "${YELLOW}[5/5] Deploying services with Docker Compose...${NC}"

if ! docker compose -f docker-compose-production.yml up -d; then
  echo -e "${RED}Deployment failed${NC}"
  echo "Troubleshooting:"
  echo "  1. Check Docker is running: docker ps"
  echo "  2. Check disk space: df -h"
  echo "  3. View logs: docker compose -f docker-compose-production.yml logs"
  exit 1
fi

echo -e "${GREEN}✓ Services deployed${NC}"

# Wait for services
echo ""
echo -e "${YELLOW}Waiting for services to become healthy (1-2 minutes)...${NC}"
sleep 20

# Verify deployment
echo ""
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}Deployment Complete!${NC}"
echo -e "${GREEN}======================================${NC}"
echo ""

echo "Services running:"
docker ps --filter "name=my-app\|postgres\|redis\|marcu\|memsys\|mailhog" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "Checking services..."

echo ""
echo "Access points:"
echo "  • Rule Engine API: http://localhost:8080/health"
echo "  • The-Gateway: http://localhost:3012"
echo "  • SwitchIsland: http://localhost:3006"
echo "  • Spore-Scribe: http://localhost:3010"
echo "  • Renewal-Core: http://localhost:3011"
echo "  • Mailhog: http://localhost:8025"
echo "  • Milvus Vector DB: localhost:19530"
echo "  • Elasticsearch: http://localhost:19200"
echo "  • MongoDB: localhost:27017"
echo ""

echo "Configuration:"
echo "  • Environment: $(pwd)/.env"
echo "  • Caddy Config: $(pwd)/caddy/Caddyfile"
echo ""

echo -e "${YELLOW}Useful commands:${NC}"
echo "  • View status: docker compose -f docker-compose-production.yml ps"
echo "  • View logs: docker compose -f docker-compose-production.yml logs -f"
echo "  • Stop services: docker compose -f docker-compose-production.yml down"
echo "  • Test API: curl http://localhost:8080/health"
echo ""
