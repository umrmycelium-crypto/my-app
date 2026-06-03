#!/bin/bash
# cleanup-old-services.sh - Remove fragmented networks and orphaned containers

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}🧹 Cleaning up fragmented Docker services...${NC}"
echo ""

# Stop all containers
echo -e "${YELLOW}Stopping all containers...${NC}"
docker stop $(docker ps -q) 2>/dev/null || true

# Remove orphaned/fragmented containers
echo -e "${YELLOW}Removing fragmented containers...${NC}"
docker container prune -f

# Remove unused networks
echo -e "${YELLOW}Removing fragmented networks...${NC}"
docker network rm marcu_default 2>/dev/null || true
docker network rm marcu_memsys-network 2>/dev/null || true
docker network rm mushroomos_mushroom-network 2>/dev/null || true
docker network rm evermemos_memsys-network 2>/dev/null || true
docker network rm evermemos-main_memsys-network 2>/dev/null || true
docker network rm my-app_default 2>/dev/null || true
docker network rm vision-network 2>/dev/null || true

# Remove unused volumes (optional - ask user)
echo ""
echo -e "${YELLOW}Unused volumes:${NC}"
docker volume ls -q | while read vol; do
  if ! docker ps -a --format '{{json .Mounts}}' | grep -q "$vol"; then
    echo "  - $vol (orphaned)"
  fi
done

echo ""
echo -e "${GREEN}✓ Cleanup complete${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. cd deploy/"
echo "  2. cp caddy/Caddyfile-unified caddy/Caddyfile"
echo "  3. docker compose -f ../docker-compose-unified.yml up -d"
echo ""
