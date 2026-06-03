# mycelium-core

The public-safe core of the Mycelium system: rule engine, schemas, infrastructure templates, and sanitized documentation for turning private knowledge work into reusable systems.

## Overview

**mycelium-core** is designed as a modular system with:
- **iOS Client** - Native iOS application (see `ios/` submodule)
- **Rule Engine Service** - Python-based microservice for event processing and entity management
- **Infrastructure** - Azure-based cloud deployment with Bicep IaC
- **Kubernetes Integration** - Helm charts for container orchestration
- **Truth-to-Output Flow** - A protected path from private context to public concepts, examples, and working systems

## Repository Boundaries

This repository is the public/shareable application layer of the Mycelium system. Keep code, schemas, infrastructure templates, tests, and sanitized documentation here.

- See `REPO_FLOW.md` for how this repo connects to the internal system bundle, operator docs, synced copies, and backups.
- See `PUBLIC_PRIVATE_SECRET.md` for what belongs in public, private, and secret lanes.
- See `TRUTH_TO_OUTPUT.md` for the main mushroom architecture: private truth, messy capture, processing, public concepts, examples, and enterprise systems.
- Use `.env.example` as the committed template; keep real `.env` values local and uncommitted.

## Project Structure

```
mycelium-core/
├── concepts/                     # Public-safe philosophy, patterns, and architecture
├── examples/                     # Runnable examples with fake or sanitized data
├── enterprise/                   # Hardened reference systems and deployment patterns
├── ios/                          # iOS mobile application (git submodule)
│   ├── README.md
│   ├── .gitignore
│   └── [Xcode project files]
├── services/
│   └── rule_engine/              # Python microservice for event processing
│       ├── app.py
│       ├── requirements.txt
│       └── [service code]
├── charts/
│   └── rule-engine/              # Helm chart for Kubernetes deployment
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
├── infra/                         # Azure Infrastructure as Code (Bicep)
│   ├── main.bicep
│   ├── variables.bicep
│   └── [additional Bicep files]
├── migrations/                    # Database migration scripts
│   └── [migration files]
├── tests/                         # Test suite
│   └── [test files]
├── .github/workflows/             # CI/CD pipelines
│   └── [workflow YAML files]
├── docker-compose.yml             # Local development environment
├── docker-compose-tailscale.yml   # Development with Tailscale networking
├── main.json                      # Configuration manifest
├── QUICKSTART.txt                 # Quick start guide
└── [Schema and documentation files]
```

## Prerequisites

Before setting up mycelium-core, ensure you have:

### For Local Development
- **Python 3.10+** - For rule engine service
- **Docker & Docker Compose** - For containerized development
- **Git** - For version control and submodule management
- **Xcode** (macOS only) - For iOS development

### For Cloud Deployment
- **Azure CLI** - `az` command-line tool
- **Bicep CLI** - For infrastructure code
- **kubectl** - For Kubernetes management (if using AKS)

### For Networking
- **Tailscale** - For secure mesh networking between environments
- SSH keys configured for Mycelium network access

## Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/umrmycelium-crypto/my-app.git mycelium-core
cd mycelium-core
git submodule update --init --recursive
```

### 2. Initialize the iOS Submodule

```bash
cd ios
# Follow iOS-specific setup in ios/README.md
```

### 3. Set Up Local Environment

```bash
# Copy environment template
cp .env.example .env

# Configure your environment variables
vim .env
```

### 4. Start Docker Compose

#### Standard Development Setup
```bash
docker-compose up -d
```

#### With Tailscale Networking
```bash
docker-compose -f docker-compose-tailscale.yml up -d
```

### 5. Verify Services Are Running

```bash
# Check service health
curl http://localhost:8000/health

# View logs
docker-compose logs -f rule-engine
```

## Development Workflow

### Rule Engine Service

The rule engine handles:
- Event log processing (see `EVENT_LOG_SCHEMA.json`)
- Entity fact management (see `ENTITY_FACT_SCHEMA.json`)
- Rule execution and event object transformation (see `RULE_OBJECT_SCHEMA.json`)

**To develop locally:**

```bash
# Install dependencies
pip install -r services/rule_engine/requirements.txt

# Run tests
pytest tests/

# Start development server
python services/rule_engine/app.py
```

### iOS Development

See `ios/README.md` for iOS-specific setup and development instructions.

### Database Migrations

Run migrations before deploying:

```bash
# Apply all pending migrations
docker-compose exec rule-engine python -m alembic upgrade head
```

## Deployment

### Local Testing

```bash
# Full stack on localhost
docker-compose up

# With debugging
docker-compose up --build
```

### Azure Deployment

Detailed instructions in `AZURE_DEPLOYMENT_GUIDE.md`.

**Quick deploy:**

```bash
# Validate infrastructure
az deployment group validate \
  --resource-group mycelium-core-rg \
  --template-file infra/main.bicep

# Deploy infrastructure
az deployment group create \
  --resource-group mycelium-core-rg \
  --template-file infra/main.bicep \
  --parameters @infra/parameters.json
```

### Kubernetes Deployment (AKS)

```bash
# Add Helm chart repository (if needed)
helm repo add mycelium https://helm.example.com

# Deploy rule engine service
helm install rule-engine ./charts/rule-engine \
  --namespace mycelium-core \
  --values charts/rule-engine/values.yaml
```

## Configuration Files

- **main.json** - Central configuration manifest
- **.env** - Environment variables (local development)
- **docker-compose.yml** - Container orchestration
- **docker-compose-tailscale.yml** - Networking variant with Tailscale

## Schemas

The system uses JSON schemas to define data contracts:

- **EVENT_LOG_SCHEMA.json** - Event log structure
- **EVENT_OBJECT_SCHEMA.json** - Event object format
- **ENTITY_FACT_SCHEMA.json** - Entity fact representation
- **RULE_OBJECT_SCHEMA.json** - Rule definition format

Reference these schemas when:
- Writing event processors
- Creating rules
- Designing database migrations
- Building API contracts

## Documentation

Key documentation files:

- **QUICKSTART.txt** / **QUICK_START_REFERENCE.md** - Quick reference guide
- **AZURE_DEPLOYMENT_GUIDE.md** - Cloud deployment walkthrough
- **VISION_SYSTEM_DESIGN.md** - System architecture overview
- **VISION_PIPELINE_INTEGRATION.md** - Pipeline integration details
- **RUNBOOK.md** - Operational runbook
- **TAILSCALE_SETUP_GUIDE.md** - Networking setup instructions

## Networking

### Tailscale Integration

For development and deployment across the Mycelium network:

1. Install Tailscale: https://tailscale.com/download
2. Authenticate: `tailscale login`
3. Use `docker-compose-tailscale.yml` for networked deployments

See `TAILSCALE_SETUP_GUIDE.md` for detailed setup.

## Troubleshooting

### Service Won't Start

```bash
# Check service logs
docker-compose logs rule-engine

# Rebuild container
docker-compose build --no-cache rule-engine

# Full reset
docker-compose down -v
docker-compose up --build
```

### Database Connection Issues

Verify `.env` configuration and migrations:

```bash
# Check migration status
docker-compose exec rule-engine python -m alembic current

# Reset database
docker-compose exec db psql -U admin -c "DROP DATABASE myapp; CREATE DATABASE myapp;"
```

### Network Connectivity

Test Tailscale connectivity:

```bash
# Check Tailscale status
tailscale status

# Ping a peer
tailscale ping <peer-name>
```

## Contributing

1. Clone and set up as above
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Make changes and test locally
4. Push to GitHub and open a PR
5. Ensure CI/CD pipeline passes

## Deployment Package Summary

See `DEPLOYMENT_PACKAGE_SUMMARY.md` for complete deployment artifact details.

## File Inventory

See `FILE_INVENTORY.md` for comprehensive file listing and purposes.

## Related Resources

- **the-studio** (Tailscale IP: `100.105.50.88`) - Development environment
- **forged-intent** (Tailscale IP: `100.121.123.18`) - Build/test node
- GitHub: https://github.com/umrmycelium-crypto/my-app

## License

[To be determined]

## Support

For issues or questions:
1. Check documentation files listed above
2. Review the Runbook: `RUNBOOK.md`
3. Inspect logs: `docker-compose logs`
4. Open a GitHub issue
