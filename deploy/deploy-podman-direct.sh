#!/bin/bash

# Mycelium Ecosystem Deployment for Fedora - Direct Podman
# Uses native podman commands instead of podman-compose
# Usage: sudo bash deploy-podman-direct.sh

set -e

echo "======================================"
echo "Mycelium Ecosystem Deployment"
echo "Fedora + Podman (Direct)"
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

# 1. Start Podman
echo -e "${YELLOW}[1/5] Starting Podman...${NC}"
systemctl start podman.socket 2>/dev/null || true
systemctl start podman 2>/dev/null || true

if ! command -v podman &> /dev/null; then
  echo -e "${RED}Podman not found${NC}"
  exit 1
fi

echo -e "${GREEN}✓ Podman ready${NC}"

# 2. Verify repo
echo -e "${YELLOW}[2/5] Verifying repository...${NC}"

if [ ! -d "/opt/mycelium/my-app" ]; then
  echo -e "${RED}Repository not found${NC}"
  exit 1
fi

cd /opt/mycelium/my-app/deploy

echo -e "${GREEN}✓ Repository ready${NC}"

# 3. Configure environment
echo -e "${YELLOW}[3/5] Configuring environment...${NC}"

if [ ! -f ".env" ]; then
  cat > .env << 'EOF'
POSTGRES_PASSWORD=mycelium-prod-123456
DB_USER=admin
DB_PASSWORD=mycelium-db-789012
REDIS_PASSWORD=redis-password-345678
NODE_ENV=production
LOG_LEVEL=info
EOF
fi

echo -e "${GREEN}✓ Environment configured${NC}"

# 4. Create network
echo -e "${YELLOW}[4/5] Setting up network...${NC}"

podman network create mycelium 2>/dev/null || true

mkdir -p caddy
cat > caddy/Caddyfile << 'CADDY'
:80 {
  respond "Mycelium Online"
}
CADDY

echo -e "${GREEN}✓ Network ready${NC}"

# 5. Deploy services
echo -e "${YELLOW}[5/5] Deploying services...${NC}"

# Source env
set -a
source .env
set +a

# Build Rule Engine
echo "Building Rule Engine..."
cd /opt/mycelium/my-app
podman build -t my-app-rule-engine:latest \
  -f services/rule_engine/Dockerfile \
  .
cd deploy

# Start databases
echo "Starting PostgreSQL (my-app)..."
podman run -d \
  --name my-app-postgres \
  --network mycelium \
  -e POSTGRES_USER=pgadmin \
  -e POSTGRES_PASSWORD=$POSTGRES_PASSWORD \
  -e POSTGRES_DB=visiondb \
  -v pgdata:/var/lib/postgresql/data \
  -p 5432:5432 \
  postgres:15-alpine

echo "Starting Redis (my-app)..."
podman run -d \
  --name my-app-redis \
  --network mycelium \
  -v redis_data:/data \
  -p 6379:6379 \
  redis:7.2-alpine

# Wait for databases
echo "Waiting for databases to start..."
sleep 5

# Start Rule Engine
echo "Starting Rule Engine..."
podman run -d \
  --name my-app-rule-engine \
  --network mycelium \
  -e POSTGRES_CONN="postgresql://pgadmin:$POSTGRES_PASSWORD@my-app-postgres:5432/visiondb" \
  -e REDIS_HOST="my-app-redis" \
  -e RULE_ENGINE_PORT="8080" \
  -e LOG_LEVEL="INFO" \
  -p 8080:8080 \
  my-app-rule-engine:latest

# Start central databases
echo "Starting PostgreSQL (central)..."
podman run -d \
  --name postgres-central \
  --network mycelium \
  -e POSTGRES_USER=$DB_USER \
  -e POSTGRES_PASSWORD=$DB_PASSWORD \
  -e POSTGRES_DB=mycelium \
  -v postgres_central_data:/var/lib/postgresql/data \
  postgres:15-alpine

echo "Starting Redis (central)..."
podman run -d \
  --name redis-central \
  --network mycelium \
  -v redis_central_data:/data \
  -p 6380:6379 \
  redis:7.2-alpine

echo "Starting Mailhog..."
podman run -d \
  --name mailhog \
  --network mycelium \
  -p 1025:1025 \
  -p 8025:8025 \
  mailhog/mailhog:latest

echo "Starting Milvus..."
podman run -d \
  --name memsys-milvus-standalone \
  --network mycelium \
  -e COMMON_STORAGETYPE=local \
  -v milvus_data:/var/lib/milvus \
  -p 19530:19530 \
  -p 9091:9091 \
  milvusdb/milvus:v2.5.2

echo "Starting Elasticsearch..."
podman run -d \
  --name memsys-elasticsearch \
  --network mycelium \
  -e discovery.type=single-node \
  -e xpack.security.enabled=false \
  -v elasticsearch_data:/usr/share/elasticsearch/data \
  -p 19200:9200 \
  docker.elastic.co/elasticsearch/elasticsearch:8.11.0

echo "Starting MongoDB..."
podman run -d \
  --name memsys-mongodb \
  --network mycelium \
  -v mongodb_data:/data/db \
  -p 27017:27017 \
  mongo:7.0

echo ""
echo -e "${GREEN}✓ Services deployed${NC}"

# Wait for services
echo ""
echo -e "${YELLOW}Waiting for services to start (30 seconds)...${NC}"
sleep 30

# Verify deployment
echo ""
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}Deployment Complete!${NC}"
echo -e "${GREEN}======================================${NC}"
echo ""

echo "Services running:"
podman ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "my-app|postgres|redis|milvus|elasticsearch|mongodb|mailhog" || echo "Checking services..."

echo ""
echo "Access points:"
echo "  • Rule Engine API: http://localhost:8080/health"
echo "  • Mailhog: http://localhost:8025"
echo "  • Milvus Vector DB: localhost:19530"
echo "  • Elasticsearch: http://localhost:19200"
echo "  • MongoDB: localhost:27017"
echo ""

echo "Useful commands:"
echo "  • View logs: podman logs <container>"
echo "  • Stop all: podman stop -a"
echo "  • Remove all: podman rm -a"
echo "  • Test API: curl http://localhost:8080/health"
echo ""
