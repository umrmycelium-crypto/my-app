# Vision Platform: Windows 11 Deployment Runbook

Complete step-by-step guide to deploy the vision platform on Azure using Windows 11 PowerShell.

---

## Prerequisites Checklist

Run these commands in PowerShell (Admin) to verify installation:

```powershell
# Check Azure CLI
az --version

# Check kubectl
kubectl version --client

# Check Helm
helm version

# Check Bicep
bicep --version

# Check Git
git --version

# Check Docker
docker --version

# Check Python
python --version
```

If any are missing, install them:

```powershell
# Install using winget (Windows Package Manager)
winget install --id Microsoft.AzureCLI
winget install --id Kubernetes.kubectl
winget install --id Helm.Helm
winget install --id Microsoft.Bicep
winget install --id Git.Git
winget install --id Docker.DockerDesktop
winget install --id Python.Python.3.11
```

Start Docker Desktop and wait for it to be ready (check system tray).

---

## Step 1: Azure Login and Setup

```powershell
# Login to Azure
az login

# Set your subscription
$subscriptionId = "YOUR_SUBSCRIPTION_ID_HERE"
az account set --subscription $subscriptionId

# Create resource group
$rgName = "vision-platform-rg"
$location = "eastus"
az group create --name $rgName --location $location

# Output confirmation
Write-Host "Resource group created: $rgName"
```

---

## Step 2: Provision Core Infrastructure with Bicep

```powershell
# Ensure you're in the repo root directory
cd C:\projects\my-app

# Deploy Bicep template
az deployment group create `
  --resource-group $rgName `
  --template-file infra/main.bicep `
  --parameters location=$location postgresPassword='YourSecurePassword123!' `
  --output table

# Get output values
$deploymentOutput = az deployment group show `
  --resource-group $rgName `
  --name main `
  --query properties.outputs

Write-Host "Deployment complete. Storage account and databases created."
```

**Expected output:** All resources created successfully (Storage, PostgreSQL, Redis, Event Hubs)

---

## Step 3: Create ACR (Azure Container Registry)

```powershell
# Generate unique ACR name
$acrName = "visionacr$(Get-Random -Maximum 9999)"
Write-Host "ACR Name: $acrName"

# Create ACR
az acr create `
  --resource-group $rgName `
  --name $acrName `
  --sku Standard `
  --output table

Write-Host "ACR created: $acrName"
```

---

## Step 4: Create AKS Cluster

```powershell
# Set AKS variables
$aksName = "vision-aks"
$nodeCount = 3
$nodeSize = "Standard_D4s_v3"

Write-Host "Creating AKS cluster (this takes 5-10 minutes)..."

# Create AKS cluster
az aks create `
  --resource-group $rgName `
  --name $aksName `
  --node-count $nodeCount `
  --node-vm-size $nodeSize `
  --enable-managed-identity `
  --enable-addons monitoring `
  --generate-ssh-keys `
  --output table

Write-Host "AKS cluster created: $aksName"

# Attach ACR to AKS
az aks update `
  --resource-group $rgName `
  --name $aksName `
  --attach-acr $acrName `
  --output table

Write-Host "ACR attached to AKS"
```

---

## Step 5: Get AKS Credentials and Verify

```powershell
# Get credentials
az aks get-credentials `
  --resource-group $rgName `
  --name $aksName `
  --overwrite-existing

# Verify cluster
kubectl cluster-info
kubectl get nodes

Write-Host "AKS cluster connectivity verified"
```

**Expected output:** 3 nodes in Ready state

---

## Step 6: Create Kubernetes Namespace and Secrets

```powershell
# Create namespace
kubectl create namespace vision
kubectl label namespace vision environment=production

# Create secret for database connection
$postgresHost = "vision-pg.postgres.database.azure.com"
$postgresPassword = "YourSecurePassword123!"
$postgresConn = "postgresql://pgadmin:$postgresPassword@$postgresHost`:5432/postgres?sslmode=require"

kubectl create secret generic vision-secrets `
  --from-literal=postgres-conn="$postgresConn" `
  --from-literal=redis-host="vision-redis.redis.cache.windows.net" `
  -n vision

# Verify secrets
kubectl get secrets -n vision

Write-Host "Secrets created in vision namespace"
```

---

## Step 7: Install Milvus Vector Database

```powershell
# Add Milvus Helm repo
helm repo add milvus https://zilliztech.github.io/milvus-helm
helm repo update

# Install Milvus
helm install milvus milvus/milvus `
  --namespace milvus `
  --create-namespace `
  --set persistence.enabled=true `
  --set persistence.size=50Gi `
  --set service.type=LoadBalancer `
  --output table

Write-Host "Milvus installed"

# Wait for Milvus to be ready (check status)
Write-Host "Waiting for Milvus pod to be ready..."
kubectl wait --for=condition=ready pod -l app=milvus -n milvus --timeout=300s 2>$null

# Verify
kubectl get pods -n milvus
kubectl get svc -n milvus

Write-Host "Milvus is ready"
```

---

## Step 8: Run Database Migrations

```powershell
# Connect to PostgreSQL and run migrations
# Using Azure Cloud Shell or local psql client

$postgresHost = "vision-pg.postgres.database.azure.com"
$postgresUser = "pgadmin"
$postgresPassword = "YourSecurePassword123!"
$postgresDb = "postgres"

# If you have psql installed locally:
# psql -h $postgresHost -U $postgresUser -d $postgresDb -f migrations/001_init.sql

# Alternative: Use Azure Cloud Shell or run via kubectl
Write-Host "Running SQL migrations..."
Write-Host "Use Azure Portal > Cloud Shell or local psql to run: psql -h $postgresHost -U $postgresUser -d $postgresDb -f migrations/001_init.sql"
Write-Host "Password: $postgresPassword"
```

---

## Step 9: Build and Push Docker Images to ACR

```powershell
# Login to ACR
az acr login --name $acrName

# Build rule-engine Docker image
$imageName = "rule-engine"
$imageTag = "latest"

Write-Host "Building $imageName image..."
docker build -t "$acrName.azurecr.io/$imageName`:$imageTag" `
  --file services/rule_engine/Dockerfile `
  services/rule_engine/

Write-Host "Pushing image to ACR..."
docker push "$acrName.azurecr.io/$imageName`:$imageTag"

Write-Host "Image pushed: $acrName.azurecr.io/$imageName`:$imageTag"

# Verify image in ACR
az acr repository list --name $acrName
az acr repository show-tags --name $acrName --repository $imageName
```

---

## Step 10: Deploy Helm Chart for Rule Engine

```powershell
# Update Helm values with ACR repository
$valuesFile = "charts/rule-engine/values.yaml"

# Update values.yaml image.repository
(Get-Content $valuesFile) -replace `
  'visionacr.azurecr.io', `
  "$acrName.azurecr.io" | Set-Content $valuesFile

# Install rule-engine Helm chart
helm install rule-engine charts/rule-engine `
  --namespace vision `
  -f charts/rule-engine/values.yaml `
  --set image.repository="$acrName.azurecr.io/rule-engine" `
  --set image.tag="latest" `
  --output table

Write-Host "Rule engine Helm chart deployed"

# Wait for deployment
kubectl wait --for=condition=available deployment/rule-engine -n vision --timeout=300s

# Verify pods
kubectl get pods -n vision
kubectl get svc -n vision
```

---

## Step 11: Smoke Tests (Post-Deployment)

```powershell
# Port-forward to rule-engine service
Write-Host "Setting up port-forward to rule-engine..."
kubectl port-forward svc/rule-engine 8080:8080 -n vision &
Start-Sleep -Seconds 3

# Test health endpoint
Write-Host "Testing /health endpoint..."
try {
    $response = Invoke-RestMethod -Uri http://localhost:8080/health -ErrorAction Stop
    Write-Host "✓ Health check passed: $($response | ConvertTo-Json)"
} catch {
    Write-Host "✗ Health check failed: $_"
}

# Test detection endpoint
Write-Host "Testing /detect endpoint..."
try {
    $detectionBody = @{
        type = "battery_pack"
        attributes = @{
            scuffing_score = 0.2
            wear_score = 0.7
            color = "black"
        }
        confidence = 0.92
    } | ConvertTo-Json

    $response = Invoke-RestMethod `
        -Method Post `
        -Uri http://localhost:8080/detect `
        -Body $detectionBody `
        -ContentType "application/json" `
        -ErrorAction Stop
    
    Write-Host "✓ Detection endpoint passed: $($response | ConvertTo-Json)"
} catch {
    Write-Host "✗ Detection endpoint failed: $_"
}

# Test feedback endpoint
Write-Host "Testing /feedback endpoint..."
try {
    $feedbackBody = @{
        rule_id = "00000000-0000-0000-0000-000000000000"
        feedback = "contradiction"
        entity_id = "00000000-0000-0000-0000-000000000000"
    } | ConvertTo-Json

    $response = Invoke-RestMethod `
        -Method Post `
        -Uri http://localhost:8080/feedback `
        -Body $feedbackBody `
        -ContentType "application/json" `
        -ErrorAction Stop
    
    Write-Host "✓ Feedback endpoint passed: $($response | ConvertTo-Json)"
} catch {
    Write-Host "✗ Feedback endpoint failed: $_"
}

Write-Host "Smoke tests complete"
```

---

## Step 12: Verify Deployment Status

```powershell
# Check all resources
Write-Host "=== Kubernetes Cluster Status ==="
kubectl get nodes
kubectl get namespaces

Write-Host "=== Vision Namespace ==="
kubectl get pods -n vision
kubectl get svc -n vision
kubectl get secrets -n vision

Write-Host "=== Milvus Status ==="
kubectl get pods -n milvus
kubectl get svc -n milvus

Write-Host "=== Logs ==="
kubectl logs -f deployment/rule-engine -n vision --tail=50

Write-Host "=== Azure Resources ==="
az resource list --resource-group $rgName --output table
```

---

## Step 13: Configure Monitoring and Alerts

```powershell
# Get Application Insights key (if deployed)
Write-Host "Note: Set up monitoring in Azure Portal:"
Write-Host "1. Navigate to Application Insights resource"
Write-Host "2. Set up alerts for:"
Write-Host "   - High error rate (>5%)"
Write-Host "   - High latency (p99 > 500ms)"
Write-Host "   - Rule contradiction rate (>20%)"
Write-Host "3. Configure Log Analytics workspace queries"

# Example: List all events with rule_stale action
Write-Host "To query rule stale events, run in Cloud Shell:"
Write-Host "SELECT * FROM events WHERE action='rule_stale' ORDER BY timestamp DESC LIMIT 10;"
```

---

## Troubleshooting Guide

### Issue: Pod CrashLoopBackOff

```powershell
# Check pod logs
kubectl logs <pod-name> -n vision --previous

# Check pod events
kubectl describe pod <pod-name> -n vision

# Check resource limits
kubectl top pods -n vision
```

### Issue: Database Connection Failed

```powershell
# Verify database is running
az postgres server list --resource-group $rgName

# Check firewall rules
az postgres server firewall-rule list --resource-group $rgName --server-name vision-pg

# Test connection from pod
kubectl exec -it <pod-name> -n vision -- psql -h vision-pg.postgres.database.azure.com -U pgadmin -d postgres
```

### Issue: Image Pull Errors

```powershell
# Verify ACR login
az acr login --name $acrName

# Check image exists
az acr repository show-tags --name $acrName --repository rule-engine

# Re-pull image
docker pull "$acrName.azurecr.io/rule-engine:latest"
```

### Issue: Milvus Not Ready

```powershell
# Check Milvus pod status
kubectl describe pod -n milvus -l app=milvus

# Check PVC status
kubectl get pvc -n milvus

# Check events
kubectl get events -n milvus --sort-by='.lastTimestamp'
```

---

## Common Operations

### Scale Deployment

```powershell
# Scale rule-engine to 3 replicas
kubectl scale deployment/rule-engine --replicas=3 -n vision

# Check scaling status
kubectl get deployment/rule-engine -n vision
```

### View Service Endpoints

```powershell
# Get internal endpoints
kubectl get svc -n vision

# Get external endpoints
kubectl get ingress -n vision

# Port-forward for local testing
kubectl port-forward svc/rule-engine 8080:8080 -n vision
```

### Check Resource Usage

```powershell
# Node resources
kubectl top nodes

# Pod resources
kubectl top pods -n vision

# Full resource report
kubectl describe nodes
```

### Delete Deployment

```powershell
# Uninstall Helm release
helm uninstall rule-engine -n vision

# Delete namespace (warning: deletes all resources)
kubectl delete namespace vision
```

### Rollback Deployment

```powershell
# Rollback to previous Helm release
helm rollback rule-engine -n vision

# View release history
helm history rule-engine -n vision
```

---

## Post-Deployment Checklist

- [ ] All pods running (`kubectl get pods -n vision`)
- [ ] Services accessible (`kubectl get svc -n vision`)
- [ ] Database migrations completed
- [ ] Smoke tests passed
- [ ] Milvus vector database ready
- [ ] Monitoring and alerts configured
- [ ] Application Insights configured
- [ ] DNS/ingress configured (if using custom domain)
- [ ] HTTPS/TLS certificates installed
- [ ] RBAC policies applied
- [ ] Backup and disaster recovery plan tested
- [ ] Security scanning enabled (Azure Defender)

---

## Next Steps

1. **Set up CI/CD Pipeline**: Configure GitHub Actions to automatically build and deploy on push to main branch
2. **Implement Rule Matching Logic**: Update rule engine to evaluate actual rule conditions
3. **Connect Milvus Vector Index**: Integrate vector similarity search for entity resolution
4. **Configure Event Streaming**: Set up Azure Event Hubs for event log streaming
5. **Add Observability**: Configure detailed metrics collection and dashboards
6. **Load Testing**: Performance test with realistic detection workloads
7. **Production Hardening**: Enable additional security features (WAF, private endpoints, etc.)

---

## Support and Documentation

- Azure CLI docs: https://learn.microsoft.com/cli/azure/
- Kubernetes docs: https://kubernetes.io/docs/
- Helm docs: https://helm.sh/docs/
- AKS docs: https://learn.microsoft.com/azure/aks/
- Vision Platform Design: See VISION_SYSTEM_DESIGN.md
