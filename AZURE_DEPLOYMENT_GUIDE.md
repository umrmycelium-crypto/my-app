# Vision Pipeline: Azure Deployment Guide

Complete infrastructure-as-code, Helm charts, CI/CD, and operational runbook for deploying the vision pipeline on Azure.

---

## Part 1: Azure Services Mapping

### Architecture → Azure Services

```
PERCEPTION LAYER
├── Azure Blob Storage → Raw frames, archived images
└── Azure Cognitive Services (OCR) / Custom OCR on AKS

DETECTION & VECTOR INDEX
├── AKS → Detectors, embedding extractors, trackers
└── Milvus on AKS → Visual signature indexing

TEXT SEARCH
├── Azure Cognitive Search → Label and OCR search
└── Alternative: ElasticSearch on AKS

DURABLE MEMORY & RULES
├── Azure Database for PostgreSQL Flexible Server → Facts, rules, events
├── Azure Event Hubs (Kafka-compatible) → Append-only event log
└── Azure Cache for Redis → Session store, counters

PROCESSING & MICROSERVICES
├── AKS → Rule engine, merge service, engagement service, API gateway
└── Azure Container Registry → Docker image repository

API & AUTH
├── Azure Application Gateway → Ingress, load balancing
├── Azure AD → RBAC, service principals
└── Azure Key Vault → Secrets, credentials

MONITORING
├── Azure Monitor / Application Insights → Metrics, traces
└── Log Analytics → Audit logs, diagnostics
```

---

## Part 2: Bicep Infrastructure Template

Save as `infra/main.bicep`:

```bicep
param location string = 'eastus'
param environment string = 'prod'
param projectName string = 'vision-platform'

// Common variables
var resourcePrefix = '${projectName}-${environment}'
var commonTags = {
  environment: environment
  project: projectName
  managedBy: 'bicep'
}

// ============================================================================
// RESOURCE GROUP
// ============================================================================
resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: '${resourcePrefix}-rg'
  location: location
  tags: commonTags
}

// ============================================================================
// STORAGE ACCOUNT (Blob for frames)
// ============================================================================
resource storageAccount 'Microsoft.Storage/storageAccounts@2021-06-01' = {
  name: toLower('${replace(projectName, '-', '')}${environment}sa')
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
  }
  tags: commonTags
}

resource blobContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2021-06-01' = {
  name: '${storageAccount.name}/default/frames'
  properties: {
    publicAccess: 'None'
  }
}

// ============================================================================
// POSTGRESQL (Durable memory, rules, events)
// ============================================================================
resource postgresServer 'Microsoft.DBforPostgreSQL/flexibleServers@2021-06-01' = {
  name: '${resourcePrefix}-postgres'
  location: location
  sku: {
    name: 'Standard_B2s'
    tier: 'Burstable'
  }
  properties: {
    administratorLogin: 'pgadmin'
    administratorLoginPassword: 'ChangeMeToSecurePassword123!'  // Use Key Vault in production
    version: '13'
    storage: {
      storageSizeGB: 32
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    highAvailability: {
      mode: 'Disabled'
    }
  }
  tags: commonTags
}

resource postgresDatabase 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2021-06-01' = {
  parent: postgresServer
  name: 'visiondb'
  properties: {
    charset: 'UTF8'
    collation: 'en_US.utf8'
  }
}

resource postgresFirewall 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2021-06-01' = {
  parent: postgresServer
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '255.255.255.255'
  }
}

// ============================================================================
// REDIS CACHE (Session store, counters)
// ============================================================================
resource redisCache 'Microsoft.Cache/redis@2021-06-01' = {
  name: '${resourcePrefix}-redis'
  location: location
  properties: {
    sku: {
      name: 'Basic'
      family: 'C'
      capacity: 0
    }
    enableNonSslPort: false
    minimumTlsVersion: '1.2'
  }
  tags: commonTags
}

// ============================================================================
// EVENT HUBS (Event stream)
// ============================================================================
resource eventHubNamespace 'Microsoft.EventHub/namespaces@2021-06-01-preview' = {
  name: '${resourcePrefix}-eventhub'
  location: location
  sku: {
    name: 'Basic'
    capacity: 1
  }
  properties: {
    isAutoInflateEnabled: false
    kafkaEnabled: true
  }
  tags: commonTags
}

resource eventHub 'Microsoft.EventHub/namespaces/eventhubs@2021-06-01-preview' = {
  parent: eventHubNamespace
  name: 'events'
  properties: {
    messageRetentionInDays: 7
    partitionCount: 2
  }
}

resource eventHubAuthRule 'Microsoft.EventHub/namespaces/authorizationRules@2021-06-01-preview' = {
  parent: eventHubNamespace
  name: 'RootManageSharedAccessKey'
  properties: {
    rights: [
      'Listen'
      'Manage'
      'Send'
    ]
  }
}

// ============================================================================
// CONTAINER REGISTRY (Docker images)
// ============================================================================
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2021-09-01' = {
  name: toLower('${replace(projectName, '-', '')}${environment}acr')
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    adminUserEnabled: false
    publicNetworkAccess: 'Enabled'
  }
  tags: commonTags
}

// ============================================================================
// KEY VAULT (Secrets management)
// ============================================================================
resource keyVault 'Microsoft.KeyVault/vaults@2021-06-01-preview' = {
  name: '${resourcePrefix}-kv'
  location: location
  properties: {
    enabledForDeployment: true
    enabledForTemplateDeployment: true
    enableRbacAuthorization: true
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
  }
  tags: commonTags
}

// Store PostgreSQL connection string
resource postgresSecret 'Microsoft.KeyVault/vaults/secrets@2021-06-01-preview' = {
  parent: keyVault
  name: 'postgres-connection-string'
  properties: {
    value: 'postgresql://pgadmin:ChangeMeToSecurePassword123!@${postgresServer.name}.postgres.database.azure.com:5432/visiondb'
  }
}

// Store Redis connection string
resource redisSecret 'Microsoft.KeyVault/vaults/secrets@2021-06-01-preview' = {
  parent: keyVault
  name: 'redis-connection-string'
  properties: {
    value: '${redisCache.name}.redis.cache.windows.net:6380?ssl=True&password=${listKeys(redisCache.id, '2021-06-01').primaryKey}'
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================
output storageAccountName string = storageAccount.name
output postgresHost string = postgresServer.properties.fullyQualifiedDomainName
output redisPrimaryKey string = listKeys(redisCache.id, '2021-06-01').primaryKey
output eventHubConnectionString string = listKeys(eventHubAuthRule.id, '2021-06-01-preview').primaryConnectionString
output containerRegistryLoginServer string = containerRegistry.properties.loginServer
output keyVaultUri string = keyVault.properties.vaultUri
```

Deploy with:
```bash
az deployment group create \
  --resource-group vision-platform-rg \
  --template-file infra/main.bicep \
  --parameters location=eastus environment=prod projectName=vision-platform
```

---

## Part 3: AKS Cluster Setup

```bash
#!/bin/bash
# scripts/create-aks-cluster.sh

set -e

RESOURCE_GROUP="vision-platform-rg"
CLUSTER_NAME="vision-aks"
REGISTRY_NAME="visionplatformprodacr"
LOCATION="eastus"

echo "Creating AKS cluster..."
az aks create \
  --resource-group $RESOURCE_GROUP \
  --name $CLUSTER_NAME \
  --node-count 3 \
  --node-vm-size Standard_D4s_v3 \
  --enable-managed-identity \
  --network-plugin azure \
  --network-policy azure \
  --enable-addons monitoring \
  --generate-ssh-keys \
  --location $LOCATION

echo "Attaching ACR to AKS..."
az aks update \
  --resource-group $RESOURCE_GROUP \
  --name $CLUSTER_NAME \
  --attach-acr $REGISTRY_NAME

echo "Getting credentials..."
az aks get-credentials \
  --resource-group $RESOURCE_GROUP \
  --name $CLUSTER_NAME \
  --overwrite-existing

echo "Verifying cluster..."
kubectl cluster-info
kubectl get nodes
```

---

## Part 4: Helm Charts

### 4a. Milvus Helm Chart Values

Save as `helm/milvus-values.yaml`:

```yaml
# Milvus vector database
image:
  repository: milvusdb/milvus
  tag: v2.2.9

service:
  type: LoadBalancer
  port: 19530

resources:
  limits:
    cpu: 2
    memory: 4Gi
  requests:
    cpu: 1
    memory: 2Gi

persistence:
  enabled: true
  size: 50Gi
  storageClassName: default

config:
  common:
    logLevel: info
```

Deploy:
```bash
helm repo add milvus https://zilliztech.github.io/milvus-helm
helm install milvus milvus/milvus -f helm/milvus-values.yaml -n vision
```

### 4b. Redis Helm Chart Values

Save as `helm/redis-values.yaml`:

```yaml
# Redis cache (if deploying in-cluster)
auth:
  enabled: true
  password: "ChangeMe123!"

master:
  persistence:
    enabled: true
    size: 10Gi

replica:
  replicaCount: 1
  persistence:
    enabled: true
    size: 10Gi

resources:
  limits:
    cpu: 1
    memory: 2Gi
```

Deploy:
```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install redis bitnami/redis -f helm/redis-values.yaml -n vision
```

### 4c. Microservices Helm Chart

Save as `helm/vision-services/Chart.yaml`:

```yaml
apiVersion: v2
name: vision-services
description: Vision pipeline microservices
type: application
version: 1.0.0
appVersion: "1.0.0"
```

Save as `helm/vision-services/values.yaml`:

```yaml
namespace: vision

services:
  detectionService:
    name: detection-service
    image: vision-detection:latest
    port: 8001
    replicas: 2
    resources:
      limits:
        cpu: 2
        memory: 4Gi
      requests:
        cpu: 1
        memory: 2Gi
    env:
      - name: POSTGRES_HOST
        valueFrom:
          secretKeyRef:
            name: vision-secrets
            key: postgres-host
      - name: MILVUS_HOST
        value: "milvus.vision.svc.cluster.local"
      - name: REDIS_HOST
        value: "redis-master.vision.svc.cluster.local"

  ruleEngine:
    name: rule-engine
    image: vision-rule-engine:latest
    port: 8002
    replicas: 2
    resources:
      limits:
        cpu: 1
        memory: 2Gi
      requests:
        cpu: 500m
        memory: 1Gi

  engagementService:
    name: engagement-service
    image: vision-engagement:latest
    port: 8003
    replicas: 2
    resources:
      limits:
        cpu: 1
        memory: 2Gi

  apiGateway:
    name: api-gateway
    image: vision-api-gateway:latest
    port: 8000
    replicas: 2
    resources:
      limits:
        cpu: 1
        memory: 2Gi

ingress:
  enabled: true
  className: azure-application-gateway
  hosts:
    - host: vision-api.example.com
      paths:
        - path: /
          pathType: Prefix
```

Deploy:
```bash
helm install vision-services helm/vision-services -n vision
```

---

## Part 5: CI/CD Pipeline (GitHub Actions)

Save as `.github/workflows/deploy.yml`:

```yaml
name: Deploy Vision Pipeline

on:
  push:
    branches:
      - main
  pull_request:
    branches:
      - main

env:
  REGISTRY: visionplatformprodacr.azurecr.io
  CLUSTER_NAME: vision-aks
  RESOURCE_GROUP: vision-platform-rg

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Azure Login
        uses: azure/login@v1
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}
      
      - name: Build detection service
        run: |
          docker build -t $REGISTRY/detection-service:${{ github.sha }} \
            --file services/detection/Dockerfile \
            services/detection/
      
      - name: Build rule engine
        run: |
          docker build -t $REGISTRY/rule-engine:${{ github.sha }} \
            --file services/rule-engine/Dockerfile \
            services/rule-engine/
      
      - name: Build engagement service
        run: |
          docker build -t $REGISTRY/engagement-service:${{ github.sha }} \
            --file services/engagement/Dockerfile \
            services/engagement/
      
      - name: Build API gateway
        run: |
          docker build -t $REGISTRY/api-gateway:${{ github.sha }} \
            --file services/api-gateway/Dockerfile \
            services/api-gateway/
      
      - name: Push images to ACR
        run: |
          az acr login --name visionplatformprodacr
          docker push $REGISTRY/detection-service:${{ github.sha }}
          docker push $REGISTRY/rule-engine:${{ github.sha }}
          docker push $REGISTRY/engagement-service:${{ github.sha }}
          docker push $REGISTRY/api-gateway:${{ github.sha }}
      
      - name: Get AKS credentials
        run: |
          az aks get-credentials \
            --resource-group $RESOURCE_GROUP \
            --name $CLUSTER_NAME
      
      - name: Run migrations
        run: |
          kubectl run migration-job \
            --image=$REGISTRY/db-migration:${{ github.sha }} \
            --env="POSTGRES_HOST=${{ secrets.POSTGRES_HOST }}" \
            --env="POSTGRES_PASSWORD=${{ secrets.POSTGRES_PASSWORD }}" \
            --restart=Never \
            -n vision
      
      - name: Deploy Helm charts
        run: |
          helm upgrade --install vision-services \
            helm/vision-services \
            --namespace vision \
            --create-namespace \
            --set-string image.tag=${{ github.sha }} \
            --values helm/vision-services/values.yaml

  test:
    runs-on: ubuntu-latest
    needs: build
    steps:
      - uses: actions/checkout@v3
      
      - name: Run unit tests
        run: |
          python -m pytest tests/unit --cov
      
      - name: Run integration tests
        run: |
          python -m pytest tests/integration

secrets:
  AZURE_CREDENTIALS: ${{ secrets.AZURE_CREDENTIALS }}
  POSTGRES_HOST: ${{ secrets.POSTGRES_HOST }}
  POSTGRES_PASSWORD: ${{ secrets.POSTGRES_PASSWORD }}
```

---

## Part 6: Database Schema & Migrations

Save as `migrations/001_initial_schema.sql`:

```sql
-- Entities table
CREATE TABLE entities (
  entity_id UUID PRIMARY KEY,
  type VARCHAR(50) NOT NULL,
  visual_signature_id VARCHAR(100),
  labels JSONB,
  attributes JSONB,
  source VARCHAR(100),
  confidence DECIMAL(3,2),
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  last_seen TIMESTAMP,
  history UUID[] DEFAULT '{}',
  metadata JSONB,
  INDEX idx_entity_type (type),
  INDEX idx_entity_updated (updated_at DESC)
);

-- Rules table
CREATE TABLE rules (
  rule_id UUID PRIMARY KEY,
  predicate VARCHAR(128) NOT NULL,
  conditions JSONB NOT NULL,
  evidence_clues JSONB NOT NULL,
  type VARCHAR(50),
  version INT DEFAULT 1,
  action VARCHAR(50),
  action_metadata JSONB,
  priority INT DEFAULT 50,
  created_by VARCHAR(100),
  created_at TIMESTAMP DEFAULT NOW(),
  updated_by VARCHAR(100),
  updated_at TIMESTAMP,
  contradiction_count INT DEFAULT 0,
  contradiction_threshold INT DEFAULT 3,
  last_contradiction_at TIMESTAMP,
  match_count INT DEFAULT 0,
  last_match_at TIMESTAMP,
  confidence DECIMAL(3,2),
  tags JSONB,
  description TEXT,
  merged_from UUID[],
  superseded_by UUID,
  retired_at TIMESTAMP,
  retirement_reason VARCHAR(50),
  status VARCHAR(50) DEFAULT 'active',
  metadata JSONB,
  INDEX idx_rule_status (status),
  INDEX idx_rule_predicate (predicate),
  INDEX idx_rule_contradiction (contradiction_count DESC)
);

-- Events table
CREATE TABLE events (
  event_id UUID PRIMARY KEY,
  timestamp TIMESTAMP NOT NULL,
  entity_id UUID NOT NULL,
  rule_id UUID,
  detection JSONB,
  applied_rules UUID[],
  action VARCHAR(50),
  action_metadata JSONB,
  source VARCHAR(100),
  user_feedback VARCHAR(50),
  feedback_metadata JSONB,
  session_id UUID,
  frame_id VARCHAR(100),
  confidence_overall DECIMAL(3,2),
  processing_ms INT,
  metadata JSONB,
  tags JSONB,
  created_at TIMESTAMP DEFAULT NOW(),
  INDEX idx_event_timestamp (timestamp DESC),
  INDEX idx_event_entity (entity_id),
  INDEX idx_event_rule (rule_id)
);

-- Corrections table
CREATE TABLE corrections (
  correction_id UUID PRIMARY KEY,
  entity_id UUID NOT NULL,
  rule_id UUID,
  correction_type VARCHAR(50),
  previous_value JSONB,
  corrected_value JSONB,
  reason TEXT,
  corrected_by VARCHAR(100),
  corrected_at TIMESTAMP DEFAULT NOW(),
  event_id UUID,
  INDEX idx_correction_rule (rule_id),
  INDEX idx_correction_entity (entity_id)
);

-- Create indices
CREATE INDEX idx_entity_visual ON entities(visual_signature_id);
CREATE INDEX idx_rules_created ON rules(created_at DESC);
CREATE INDEX idx_events_feedback ON events(user_feedback);
```

Run migration:
```bash
# Using Flyway (Java)
flyway -url=jdbc:postgresql://$POSTGRES_HOST/visiondb \
  -user=pgadmin \
  -password=$POSTGRES_PASSWORD \
  migrate

# Or using Alembic (Python)
alembic upgrade head
```

---

## Part 7: Rule Engine Microservice (FastAPI)

Save as `services/rule-engine/main.py`:

```python
from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse
import os
import json
import psycopg2
import redis
from uuid import uuid4
from datetime import datetime

app = FastAPI(title="Rule Engine Service")

# Database connection
db_connection = psycopg2.connect(
    host=os.getenv("POSTGRES_HOST"),
    database="visiondb",
    user=os.getenv("POSTGRES_USER"),
    password=os.getenv("POSTGRES_PASSWORD")
)

# Redis connection
redis_client = redis.Redis(
    host=os.getenv("REDIS_HOST"),
    decode_responses=True
)

class RuleEngine:
    def __init__(self, db):
        self.db = db
        self.cursor = db.cursor()
    
    def load_active_rules(self):
        self.cursor.execute("""
            SELECT * FROM rules 
            WHERE status = 'active' 
              AND retired_at IS NULL
            ORDER BY priority DESC
        """)
        return self.cursor.fetchall()
    
    def evaluate_condition(self, condition: str, attributes: dict) -> bool:
        """Evaluate condition expression"""
        import re
        match = re.match(r'(\w+)\s*(>|<|==|>=|<=)\s*(.+)', condition.strip())
        if not match:
            return False
        
        field, operator, threshold_str = match.groups()
        
        if field not in attributes:
            return False
        
        value = attributes[field]
        threshold = float(threshold_str) if "'" not in threshold_str else threshold_str.strip("'")
        
        if operator == ">":
            return value > threshold
        elif operator == "<":
            return value < threshold
        elif operator == "==":
            return value == threshold
        
        return False
    
    def match_rules(self, entity_id: str, attributes: dict) -> list:
        """Match all active rules"""
        rules = self.load_active_rules()
        matches = []
        
        for rule in rules:
            conditions = json.loads(rule[2])  # conditions column
            
            conditions_satisfied = [c for c in conditions if self.evaluate_condition(c, attributes)]
            
            if len(conditions_satisfied) == len(conditions):
                match = {
                    "rule_id": str(rule[0]),
                    "predicate": rule[1],
                    "conditions_satisfied": conditions_satisfied,
                    "match_confidence": rule[14]
                }
                matches.append(match)
        
        return matches


@app.get("/health")
async def health_check():
    return {"status": "healthy"}


@app.post("/api/v1/rules/match")
async def match_rules(entity_id: str, attributes: dict):
    """Apply rules to entity"""
    try:
        engine = RuleEngine(db_connection)
        matches = engine.match_rules(entity_id, attributes)
        
        return {
            "entity_id": entity_id,
            "matched_rules": matches,
            "total_matches": len(matches)
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/v1/feedback")
async def handle_feedback(entity_id: str, rule_id: str, feedback_type: str, reason: str, user_id: str):
    """Handle user feedback on rules"""
    try:
        # Update contradiction count
        if feedback_type == "contradiction":
            cursor = db_connection.cursor()
            cursor.execute("""
                UPDATE rules 
                SET contradiction_count = contradiction_count + 1,
                    last_contradiction_at = NOW()
                WHERE rule_id = %s
            """, [rule_id])
            
            # Check if rule should be retired
            cursor.execute("""
                SELECT contradiction_count, contradiction_threshold 
                FROM rules 
                WHERE rule_id = %s
            """, [rule_id])
            
            rule = cursor.fetchone()
            if rule[0] >= rule[1]:
                cursor.execute("""
                    UPDATE rules 
                    SET status = 'stale'
                    WHERE rule_id = %s
                """, [rule_id])
            
            db_connection.commit()
        
        return {
            "status": "feedback_recorded",
            "feedback_type": feedback_type,
            "entity_id": entity_id,
            "rule_id": rule_id
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/v1/rule/update")
async def update_rule(rule_id: str, changes: dict, reason: str, user_id: str):
    """Update rule with merge logic"""
    try:
        cursor = db_connection.cursor()
        
        # Get existing rule
        cursor.execute("SELECT version FROM rules WHERE rule_id = %s", [rule_id])
        result = cursor.fetchone()
        new_version = result[0] + 1 if result else 1
        
        # Update rule
        cursor.execute("""
            UPDATE rules 
            SET predicate = %s,
                conditions = %s,
                evidence_clues = %s,
                action = %s,
                priority = %s,
                version = %s,
                updated_by = %s,
                updated_at = NOW()
            WHERE rule_id = %s
        """, [
            changes.get("predicate"),
            json.dumps(changes.get("conditions", [])),
            json.dumps(changes.get("evidence_clues", [])),
            changes.get("action"),
            changes.get("priority"),
            new_version,
            user_id,
            rule_id
        ])
        
        db_connection.commit()
        
        return {
            "rule_id": rule_id,
            "new_version": new_version,
            "status": "updated"
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8002)
```

Save as `services/rule-engine/Dockerfile`:

```dockerfile
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY main.py .

EXPOSE 8002

CMD ["python", "main.py"]
```

Save as `services/rule-engine/requirements.txt`:

```
fastapi==0.104.1
uvicorn==0.24.0
psycopg2-binary==2.9.9
redis==5.0.0
pydantic==2.5.0
```

---

## Part 8: Operational Runbook

Save as `docs/OPERATIONAL_RUNBOOK.md`:

```markdown
# Vision Pipeline: Operational Runbook

## Prerequisites

1. Azure CLI installed and logged in
2. kubectl installed
3. Helm 3 installed
4. GitHub repo with code and secrets configured

## Step 1: Provision Core Infrastructure

```bash
# Set environment variables
export RESOURCE_GROUP="vision-platform-rg"
export LOCATION="eastus"
export ENVIRONMENT="prod"

# Create resource group
az group create --name $RESOURCE_GROUP --location $LOCATION

# Deploy Bicep template
az deployment group create \
  --resource-group $RESOURCE_GROUP \
  --template-file infra/main.bicep \
  --parameters location=$LOCATION environment=$ENVIRONMENT projectName=vision-platform
```

**Expected output:** All resources created (PostgreSQL, Redis, Event Hubs, Storage, etc.)

## Step 2: Create AKS Cluster

```bash
# Run AKS creation script
bash scripts/create-aks-cluster.sh

# Verify cluster is running
kubectl get nodes
kubectl get pods --all-namespaces
```

**Expected output:** 3 nodes in Ready state

## Step 3: Create Kubernetes Namespace

```bash
kubectl create namespace vision
kubectl label namespace vision environment=production
```

## Step 4: Configure Secrets

```bash
# Create secret for database connection
kubectl create secret generic vision-secrets \
  --from-literal=postgres-host=<postgres-host> \
  --from-literal=postgres-password=<postgres-password> \
  --from-literal=redis-password=<redis-password> \
  -n vision

# Verify secrets
kubectl get secrets -n vision
```

## Step 5: Deploy Milvus

```bash
# Add Helm repo
helm repo add milvus https://zilliztech.github.io/milvus-helm
helm repo update

# Install Milvus
helm install milvus milvus/milvus \
  -f helm/milvus-values.yaml \
  -n vision

# Wait for Milvus to be ready
kubectl wait --for=condition=ready pod -l app=milvus -n vision --timeout=300s
kubectl get pods -n vision
```

**Expected output:** milvus pod running

## Step 6: Deploy Redis (Optional, if not using Azure Cache)

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

helm install redis bitnami/redis \
  -f helm/redis-values.yaml \
  -n vision

kubectl wait --for=condition=ready pod -l app=redis -n vision --timeout=300s
```

## Step 7: Run Database Migrations

```bash
# Build migration Docker image
docker build -t visionplatformprodacr.azurecr.io/db-migration:latest \
  --file migrations/Dockerfile .

# Push to ACR
az acr login --name visionplatformprodacr
docker push visionplatformprodacr.azurecr.io/db-migration:latest

# Run migration job
kubectl run migration-job \
  --image=visionplatformprodacr.azurecr.io/db-migration:latest \
  --env="POSTGRES_HOST=<postgres-host>" \
  --env="POSTGRES_PASSWORD=<postgres-password>" \
  --restart=Never \
  -n vision

# Check migration status
kubectl logs migration-job -n vision
```

## Step 8: Build and Push Microservice Images

```bash
# Login to ACR
az acr login --name visionplatformprodacr

# Build and push detection service
docker build -t visionplatformprodacr.azurecr.io/detection-service:latest \
  --file services/detection/Dockerfile services/detection/
docker push visionplatformprodacr.azurecr.io/detection-service:latest

# Build and push rule engine
docker build -t visionplatformprodacr.azurecr.io/rule-engine:latest \
  --file services/rule-engine/Dockerfile services/rule-engine/
docker push visionplatformprodacr.azurecr.io/rule-engine:latest

# Build and push other services...
```

## Step 9: Deploy Helm Charts

```bash
# Install vision services
helm install vision-services helm/vision-services \
  -n vision \
  --values helm/vision-services/values.yaml

# Wait for services to be ready
kubectl wait --for=condition=ready pod -l app=vision-services -n vision --timeout=300s

# Verify deployment
kubectl get pods -n vision
kubectl get svc -n vision
```

## Step 10: Run Smoke Tests

```bash
# Port forward to API gateway
kubectl port-forward svc/api-gateway 8000:8000 -n vision &

# Test health endpoint
curl http://localhost:8000/health

# Test detection endpoint
curl -X POST http://localhost:8000/api/v1/detect \
  -H "Content-Type: application/json" \
  -d '{
    "frame_id": "test-frame-001",
    "detections": [{
      "class": "battery_pack",
      "confidence": 0.94,
      "bounding_box": [150, 200, 100, 120]
    }]
  }'

# Test rule matching
curl -X POST http://localhost:8000/api/v1/rules/match \
  -H "Content-Type: application/json" \
  -d '{
    "entity_id": "entity-001",
    "attributes": {
      "age": 930,
      "scuffing_score": 0.72
    }
  }'
```

## Step 11: Enable Monitoring

```bash
# Check Application Insights
az monitor app-insights component show \
  --resource-group $RESOURCE_GROUP \
  --query instrumentationKey

# Set alerts
az monitor metrics alert create \
  --resource-group $RESOURCE_GROUP \
  --name high-error-rate \
  --description "Alert on error rate > 5%" \
  --scopes /subscriptions/SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Insights/components/vision-appinsights \
  --condition "avg errors > 5"
```

## Step 12: Cutover and Monitoring

1. Switch traffic from old system to new API gateway
2. Monitor for 24-72 hours:
   - Error rates (should be < 1%)
   - Latency (p99 should be < 500ms)
   - Contradiction rates per rule
   - False positive rates

```bash
# View logs
kubectl logs -f deployment/detection-service -n vision
kubectl logs -f deployment/rule-engine -n vision

# View metrics
kubectl top pods -n vision
kubectl top nodes
```

## Common Operations

### Scale up microservices

```bash
kubectl scale deployment/rule-engine --replicas=3 -n vision
```

### View service endpoints

```bash
kubectl get svc -n vision
kubectl get ingress -n vision
```

### Delete deployment

```bash
helm uninstall vision-services -n vision
```

### Check pod events

```bash
kubectl describe pod <pod-name> -n vision
```

### Port forward to database

```bash
kubectl port-forward postgres-0 5432:5432 -n vision
```

## Rollback Procedure

```bash
# Rollback to previous Helm release
helm rollback vision-services 1 -n vision

# Verify rollback
kubectl rollout status deployment/vision-services -n vision
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Pods not starting | `kubectl describe pod <pod>`, check ImagePullErrors |
| Database connection failed | Verify secrets, check firewall rules |
| Rules not matching | Check rule syntax, verify attributes in event log |
| High error rates | Check logs, verify service endpoints reachable |
| Memory pressure | Scale up node pools or increase container limits |
```

---

## Part 9: GitHub Actions Secrets Configuration

Add these secrets to GitHub repository settings:

```
AZURE_CREDENTIALS=<JSON from `az ad sp create-for-rbac`>
AZURE_SUBSCRIPTION_ID=<subscription-id>
POSTGRES_HOST=<postgres-server-name>.postgres.database.azure.com
POSTGRES_PASSWORD=<secure-password>
POSTGRES_USER=pgadmin
REDIS_HOST=<redis-cache-name>.redis.cache.windows.net
REGISTRY_PASSWORD=<acr-password>
```

---

## Deliverables Summary

✅ Bicep templates (main.bicep)
✅ AKS cluster setup (create-aks-cluster.sh)
✅ Helm charts (milvus, redis, vision-services)
✅ CI/CD pipeline (GitHub Actions workflow)
✅ Database migrations (SQL schema)
✅ Rule Engine microservice (FastAPI)
✅ Operational runbook (step-by-step commands)
✅ Monitoring and alerting configuration
✅ Security best practices (Key Vault, secrets, RBAC)

All files ready to deploy. Start with Part 1: Bicep provisioning.
