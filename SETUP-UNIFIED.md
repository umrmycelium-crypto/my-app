# Mycelium Unified Setup Guide

## Overview

This unified setup consolidates all services (my-app, Marcu microservices, WordPress, Baserow, search/vector DBs) into a single `mycelium` network with proper service discovery and connection management.

**What's included:**
- Rule Engine API (Vision Pipeline)
- PostgreSQL (central + my-app)
- Redis (central + my-app)
- Milvus (vector search)
- Elasticsearch (full-text search)
- MongoDB (document store)
- 4x Marcu microservices (Gateway, SwitchIsland, Spore-Scribe, Renewal-Core)
- WordPress (CMS)
- Baserow (Database UI)
- Mailhog (email testing)
- Forge-Chat
- Caddy (reverse proxy)

## Step 1: Cleanup Old Services

```bash
cd /path/to/my-app
bash scripts/cleanup-old-services.sh
```

This removes fragmented networks and orphaned containers from previous deployments.

## Step 2: Configure Environment

```bash
cp .env.unified.example .env.unified
# Edit with your passwords:
# - POSTGRES_PASSWORD
# - DB_PASSWORD
# - WORDPRESS_DB_PASSWORD (and root password)
# - BASEROW admin password (if using)
nano .env.unified
```

Load environment:
```bash
set -a
source .env.unified
set +a
```

## Step 3: Setup Caddy (Reverse Proxy)

```bash
cd deploy/caddy
cp Caddyfile-unified Caddyfile
# Edit Caddyfile if you have a domain (uncomment HTTPS section)
nano Caddyfile
```

## Step 4: Deploy Unified Stack

```bash
cd ..
docker compose -f ../docker-compose-unified.yml up -d
```

Wait for all services to become healthy:
```bash
docker compose -f ../docker-compose-unified.yml ps
```

## Step 5: Verify Connections

All services are now on the `mycelium` network and can communicate by hostname:

### Rule Engine
```bash
curl http://localhost:8080/health
```

### WordPress
```bash
open http://localhost:8081
# Admin: wp-admin
```

### Baserow
```bash
open http://localhost:3000
```

### Mailhog (email testing)
```bash
open http://localhost:8025
```

### Gateway status
```bash
curl http://localhost:3012/health
```

## Step 6: Access via Reverse Proxy

Once Caddy is running, all services are available via Caddy routes:

| Service | Route | Port |
|---------|-------|------|
| Rule Engine API | http://localhost/api/v1/* | 8080 |
| Gateway | http://localhost/gateway/* | 3012 |
| SwitchIsland | http://localhost/switch/* | 3006 |
| Spore-Scribe | http://localhost/scribe/* | 3010 |
| Renewal-Core | http://localhost/renewal/* | 3011 |
| WordPress | http://localhost/wordpress | 8081 |
| Baserow | http://localhost/baserow | 3000 |
| Chat | http://localhost/chat | 5000 |
| Mailhog | http://localhost/mail | 8025 |

## Service Connectivity

All services share the `mycelium` network and can connect via:
- **Hostname**: `service-name:port`
- **Example**: PostgreSQL → `postgres-central:5432`

### Service-to-Service Communication

**Rule Engine → PostgreSQL:**
```
postgresql://pgadmin:$POSTGRES_PASSWORD@my-app-postgres:5432/visiondb
```

**Marcu Services → PostgreSQL:**
```
postgresql://$DB_USER:$DB_PASSWORD@postgres-central:5432/mycelium
```

**All Services → Redis:**
```
redis://redis-central:6379
```

**All Services → Milvus (vector):**
```
localhost:19530
```

**All Services → Elasticsearch:**
```
http://memsys-elasticsearch:9200
```

**All Services → MongoDB:**
```
mongodb://memsys-mongodb:27017
```

## Troubleshooting

### Service not connecting to PostgreSQL
1. Verify both are on `mycelium` network:
   ```bash
   docker network inspect mycelium | grep -A 5 "Containers"
   ```
2. Check PostgreSQL is healthy:
   ```bash
   docker logs postgres-central
   ```
3. Verify hostname in connection string uses service name (not localhost)

### WordPress can't connect to database
1. Check WordPress DB environment variables:
   ```bash
   docker inspect wordpress | grep -A 20 "Env"
   ```
2. Verify `wordpress-db` container is healthy:
   ```bash
   docker logs wordpress-db
   ```
3. Verify both are on `mycelium` network

### Baserow not starting
1. Verify PostgreSQL is ready:
   ```bash
   docker logs postgres-central
   ```
2. Verify Redis is running:
   ```bash
   docker logs redis-central
   ```
3. Check Baserow logs:
   ```bash
   docker logs baserow
   ```

### Caddy not routing services
1. Check Caddyfile syntax:
   ```bash
   docker logs mdgt-public-ingress
   ```
2. Verify all backends are on `mycelium` network
3. Check port bindings: `docker ps | grep caddy`

## Monitoring

Monitor all services:
```bash
docker compose -f docker-compose-unified.yml logs -f
```

Monitor specific service:
```bash
docker logs -f service-name
```

List all running services:
```bash
docker compose -f docker-compose-unified.yml ps
```

## Cleanup

Stop all services:
```bash
docker compose -f docker-compose-unified.yml down
```

Remove volumes (WARNING: deletes data):
```bash
docker compose -f docker-compose-unified.yml down -v
```

## Production Deployment

For production (forged-intent or the-studio):

1. Use environment file with production secrets:
   ```bash
   docker compose -f docker-compose-unified.yml --env-file .env.production up -d
   ```

2. Enable SSL in Caddy:
   ```
   example.com {
     # Routes...
   }
   ```

3. Set up automated backups for volumes
4. Configure log rotation: `docker run --log-driver json-file --log-opt max-size=10m`
5. Set resource limits in docker-compose for each service

## Next Steps

- [ ] Verify WordPress connects to database
- [ ] Verify Baserow connects to PostgreSQL
- [ ] Test Rule Engine API: `curl -X POST http://localhost:8080/api/v1/detect -H "Content-Type: application/json" -d '{"type":"test","attributes":{},"confidence":0.9}'`
- [ ] Configure domain in Caddy for production
- [ ] Set up SSL certificates (Caddy auto-renews with Let's Encrypt)
- [ ] Configure backups for all volumes
