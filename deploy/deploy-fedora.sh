#!/bin/bash

# Mycelium Ecosystem Deployment for Fedora
# Uses Podman instead of Docker (pre-installed on Fedora)
# Usage: sudo bash deploy-fedora.sh

set -e

echo "======================================"
echo "Mycelium Ecosystem Deployment (Fedora)"
echo "======================================"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
  echo -e "${RED}Error: Please run as root (use sudo)${NC}"
  exit 1
fi

# 1. Install Podman & Podman Compose
echo -e "${YELLOW}[1/5] Setting up Podman...${NC}"

if command -v podman &> /dev/null; then
  echo -e "${GREEN}✓ Podman already installed${NC}"
else
  echo "Installing Podman..."
  dnf install -y podman podman-compose 2>&1 | tail -5 || true
  
  if ! command -v podman &> /dev/null; then
    echo -e "${RED}Failed to install Podman${NC}"
    exit 1
  fi
fi

# Enable Podman socket for compose
systemctl enable podman.socket 2>/dev/null || true
systemctl start podman.socket 2>/dev/null || true

echo -e "${GREEN}✓ Podman ready${NC}"
podman --version

# 2. Clone or update repository
echo -e "${YELLOW}[2/5] Verifying repository...${NC}"

if [ ! -d "/opt/mycelium/my-app" ]; then
  echo -e "${RED}Repository not found at /opt/mycelium/my-app${NC}"
  exit 1
fi

cd /opt/mycelium/my-app/deploy

echo -e "${GREEN}✓ Repository ready${NC}"

# 3. Configure environment
echo -e "${YELLOW}[3/5] Configuring environment...${NC}"

if [ ! -f ".env" ]; then
  POSTGRES_PASS=$(openssl rand -hex 8 2>/dev/null || echo "changeme123")
  DB_PASS=$(openssl rand -hex 8 2>/dev/null || echo "changeme456")
  REDIS_PASS=$(openssl rand -hex 16 2>/dev/null || echo "redispass789")

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

# 5. Deploy services using Podman
echo -e "${YELLOW}[5/5] Deploying services with Podman...${NC}"

# Use docker-compose but with podman backend
export COMPOSE_PODMAN_COMPOSE_BIN=podman

# Convert docker-compose to podman format and deploy
podman-compose -f docker-compose-production.yml up -d

if [ $? -eq 0 ]; then
  echo -e "${GREEN}✓ Services deployed${NC}"
else
  echo -e "${RED}Deployment failed${NC}"
  exit 1
fi

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
podman ps -f "name=my-app\|postgres\|redis\|marcu\|memsys\|mailhog" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "Checking services..."

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
echo "  • View status: podman-compose -f docker-compose-production.yml ps"
echo "  • View logs: podman-compose -f docker-compose-production.yml logs -f"
echo "  • Stop services: podman-compose -f docker-compose-production.yml down"
echo "  • Test API: curl http://localhost:8080/health"
echo ""
