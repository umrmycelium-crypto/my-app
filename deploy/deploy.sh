#!/bin/bash

# Mycelium Ecosystem One-Shot Deployment Script
# For fresh Fedora installation on forged-intent
# Usage: sudo ./deploy.sh

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
echo -e "${YELLOW}[1/5] Setting up Docker...${NC}"

# Check if Docker is already installed
if command -v docker &> /dev/null; then
  echo -e "${GREEN}✓ Docker already installed${NC}"
else
  echo "Installing Docker..."
  dnf install -y dnf-plugins-core 2>&1 | grep -v "^$" || true
  dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo 2>&1 | grep -v "^$" || true
  dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>&1 | grep -v "^$" || true
  
  if ! command -v docker &> /dev/null; then
    echo -e "${RED}Failed to install Docker${NC}"
    echo "Troubleshooting:"
    echo "  1. Check system resources: free -h, df -h"
    echo "  2. Try manual install: dnf install docker-ce"
    echo "  3. Check Fedora version: cat /etc/os-release"
    exit 1
  fi
fi

# Enable and start Docker
systemctl enable docker 2>/dev/null || true
systemctl start docker 2>/dev/null || true

# Wait for Docker daemon
echo "Waiting for Docker daemon..."
for i in {1..30}; do
  if docker ps &>/dev/null; then
    echo -e "${GREEN}✓ Docker is running${NC}"
    break
  fi
  echo -n "."
  sleep 1
done

if ! docker ps &>/dev/null; then
  echo -e "${RED}Docker daemon failed to start${NC}"
  systemctl status docker
  exit 1
fi

# 2. Clone or update repository
echo -e "${YELLOW}[2/5] Cloning my-app repository...${NC}"

if ! command -v git &> /dev/null; then
  echo "Installing git..."
  dnf install -y git 2>&1 | grep -v "^$" || true
fi

if [ ! -d "/opt/mycelium/my-app" ]; then
  mkdir -p /opt/mycelium
  cd /opt/mycelium
  git clone https://github.com/umrmycelium-crypto/my-app.git
  if [ ! -d "/opt/mycelium/my-app" ]; then
    echo -e "${RED}Failed to clone repository${NC}"
    exit 1
  fi
else
  cd /opt/mycelium/my-app
  git pull origin main || echo "Warning: git pull failed, using existing repo"
fi

echo -e "${GREEN}✓ Repository ready${NC}"

# 3. Configure environment
echo -e "${YELLOW}[3/5] Configuring environment...${NC}"

if [ ! -d "deploy" ]; then
  echo -e "${RED}Error: deploy directory not found${NC}"
  exit 1
fi

cd deploy

# Generate secure passwords
POSTGRES_PASS=$(openssl rand -hex 8 2>/dev/null || echo "changeme123")
DB_PASS=$(openssl rand -hex 8 2>/dev/null || echo "changeme456")
REDIS_PASS=$(openssl rand -hex 16 2>/dev/null || echo "redispass789")

cat > .env << EOF
# Mycelium Ecosystem Configuration
POSTGRES_PASSWORD=$POSTGRES_PASS
DB_USER=admin
DB_PASSWORD=$DB_PASS
REDIS_PASSWORD=$REDIS_PASS
NODE_ENV=production
LOG_LEVEL=info
EOF

if [ ! -f ".env" ]; then
  echo -e "${RED}Failed to create .env file${NC}"
  exit 1
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

if [ ! -f "caddy/Caddyfile" ]; then
  echo -e "${RED}Failed to create Caddyfile${NC}"
  exit 1
fi

echo -e "${GREEN}✓ Reverse proxy configured${NC}"

# 5. Deploy services
echo -e "${YELLOW}[5/5] Deploying services...${NC}"

# Check for docker-compose file
if [ ! -f "docker-compose-production.yml" ]; then
  echo -e "${RED}Error: docker-compose-production.yml not found${NC}"
  exit 1
fi

# Start services
if ! docker compose -f docker-compose-production.yml up -d; then
  echo -e "${RED}Failed to deploy services${NC}"
  echo "Troubleshooting:"
  echo "  1. Check Docker is running: systemctl status docker"
  echo "  2. Check disk space: df -h"
  echo "  3. View logs: docker compose -f docker-compose-production.yml logs"
  exit 1
fi

echo -e "${GREEN}✓ Services deployed${NC}"

# Wait for health checks
echo ""
echo -e "${YELLOW}Waiting for services to become healthy (this may take 1-2 minutes)...${NC}"
sleep 15

# Verify deployment
echo ""
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}Deployment Complete!${NC}"
echo -e "${GREEN}======================================${NC}"
echo ""

echo "Services running:"
docker ps -f "name=my-app\|postgres\|redis\|marcu\|memsys\|mailhog" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "Unable to list containers"

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

echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Test an endpoint: curl http://localhost:8080/health"
echo "  2. Review logs: docker compose -f docker-compose-production.yml logs -f"
echo "  3. Update .env with production secrets"
echo "  4. Configure Caddy for your domain"
echo "  5. Set up SSL certificates (Caddy auto-renews with Let's Encrypt)"
echo ""
