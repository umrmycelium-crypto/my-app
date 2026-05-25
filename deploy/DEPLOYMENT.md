# Mycelium Ecosystem Deployment Guide

## Quick Start (Fedora)

```bash
sudo chmod +x deploy.sh
sudo ./deploy.sh
```

This one-shot script handles:
- Docker installation
- Repository cloning
- Environment setup
- Service deployment
- Reverse proxy configuration

## Architecture Overview

**My-App Stack:**
- PostgreSQL 15 (visiondb)
- Redis 7.2 (cache)
- Rule Engine (FastAPI, vision pipeline)

**Mycelium Ecosystem:**
- PostgreSQL 15 (central database)
- Redis 7.2 (central cache)
- 4x Marcu Microservices:
  - SwitchIsland (3006) — routing
  - The-Gateway (3012) — API gateway
  - Spore-Scribe (3010) — data scribe
  - Renewal-Core (3011) — lifecycle management

**Data Layer:**
- Milvus v2.5.2 (vector embeddings)
- Elasticsearch 8.11.0 (search)
- MongoDB 7.0 (document store)

**Utilities:**
- Mailhog (email testing, :8025)
- Caddy (reverse proxy/ingress)

## Network

All services run on a dedicated `mycelium` bridge network for internal communication.

## Exposed Ports

| Service | Port | Purpose |
|---------|------|---------|
| Rule Engine | 8080 | Vision API |
| The-Gateway | 3012 | API Gateway |
| SwitchIsland | 3006 | Routing |
| Spore-Scribe | 3010 | Data Scribe |
| Renewal-Core | 3011 | Lifecycle |
| Mailhog Web | 8025 | Email UI |
| Milvus | 19530 | Vector DB |
| Elasticsearch | 19200 | Search |
| MongoDB | 27017 | Documents |
| Caddy HTTP | 80 | Ingress |
| Caddy HTTPS | 443 | Secure Ingress |

## Production Checklist

- [ ] Update `.env` with real secrets (use `openssl rand -hex 16` for passwords)
- [ ] Configure Caddy with your domain in `caddy/Caddyfile`
- [ ] Set up SSL certificates (Caddy auto-renews with Let's Encrypt)
- [ ] Configure persistent backups for volumes
- [ ] Set resource limits on containers
- [ ] Enable Docker logs rotation
- [ ] Configure monitoring/alerting
- [ ] Test disaster recovery

## Last Week's Context

**What was running:**
- My-app deployed and operational
- Full Mycelium ecosystem active
- Milvus + Elasticsearch for vector/search capabilities
- All 4 Marcu services online
- Codex sessions heavily used for development

**Status:** System is stable and production-ready for Fedora deployment.

## Troubleshooting

**Services not starting:**
```bash
docker compose -f docker-compose-production.yml logs <service>
```

**Port conflicts:**
```bash
# Check what's using a port
sudo lsof -i :<port>
# Update docker-compose-production.yml port mappings
```

**Database connection errors:**
```bash
# Verify database is healthy
docker compose -f docker-compose-production.yml ps
# Check logs
docker logs postgres-central
```

## Cleanup

```bash
# Stop all services
docker compose -f docker-compose-production.yml down

# Remove volumes (WARNING: deletes data)
docker compose -f docker-compose-production.yml down -v
```
