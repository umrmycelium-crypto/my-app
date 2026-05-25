#!/bin/bash

# Mycelium Ecosystem One-Shot Deployment Script
# For fresh Fedora installation on forged-intent
# Usage: ./deploy.sh

set -e

echo "======================================"
echo "Mycelium Ecosystem Deployment"
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

# 1. Install Docker & Docker Compose
echo -e "${YELLOW}[1/5] Installing Docker & Docker Compose...${NC}"
dnf update -y > /dev/null 2>&1
dnf install -y dnf-plugins-core > /dev/null 2>&1
dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo > /dev/null 2>&1
dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin > /dev/null 2>&1
systemctl enable docker > /dev/null 2>&1
systemctl start docker > /dev/null 2>&1
echo -e "${GREEN}✓ Docker installed${NC}"

# 2. Clone or update repository
echo -e "${YELLOW}[2/5] Cloning my-app repository...${NC}"
if [ ! -d "/opt/mycelium/my-app" ]; then
  mkdir -p /opt/mycelium
  cd /opt/mycelium
  git clone https://github.com/umrmycelium-crypto/my-app.git
else
  cd /opt/mycelium/my-app
  git pull origin main
fi
echo -e "${GREEN}✓ Repository ready${NC}"

# 3. Configure environment
echo -e "${YELLOW}[3/5] Configuring environment...${NC}"
cd /opt/mycelium/my-app/deploy
cp .env.example .env 2>/dev/null || cat > .env << EOF
# Mycelium Ecosystem Configuration
POSTGRES_PASSWORD=mycelium-secure-password-$(openssl rand -hex 8)
DB_USER=admin
DB_PASSWORD=mycelium-db-password-$(openssl rand -hex 8)
REDIS_PASSWORD=$(openssl rand -hex 16)
NODE_ENV=production
LOG_LEVEL=info
EOF
echo -e "${GREEN}✓ Environment configured${NC}"

# 4. Create Caddy config
echo -e "${YELLOW}[4/5] Setting up reverse proxy...${NC}"
mkdir -p caddy
cat > caddy/Caddyfile << 'EOF'
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
EOF
echo -e "${GREEN}✓ Reverse proxy configured${NC}"

# 5. Deploy services
echo -e "${YELLOW}[5/5] Deploying services...${NC}"
docker compose -f docker-compose-production.yml up -d
echo -e "${GREEN}✓ Services deployed${NC}"

# Wait for health checks
echo ""
echo -e "${YELLOW}Waiting for services to become healthy...${NC}"
sleep 10

# Verify deployment
echo ""
echo -e "${GREEN}======================================"
echo "Deployment Complete!"
echo "======================================${NC}"
echo ""
echo "Services running:"
docker ps --filter "label=com.docker.compose.project" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || docker ps -f "name=my-app|postgres|redis|marcu|memsys|mailhog" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

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
echo "  • Environment: /opt/mycelium/my-app/deploy/.env"
echo "  • Caddy Config: /opt/mycelium/my-app/deploy/caddy/Caddyfile"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Update .env with production secrets"
echo "  2. Configure Caddy for your domain"
echo "  3. Set up SSL certificates"
echo "  4. Configure backups for volumes"
echo ""
