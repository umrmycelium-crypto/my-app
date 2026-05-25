# Tailscale Integration Guide - Vision Platform

## Overview
Tailscale provides secure, zero-trust VPN access to your Vision Platform services. This guide covers:
1. Setting up Tailscale for local remote access
2. Connecting to services from remote machines
3. Securing internal communication
4. Kubernetes integration (future)

---

## Prerequisites

1. **Tailscale Account**: https://tailscale.com/start
   - Sign up with GitHub, Google, Microsoft, or email
   - Creates a private network (tailnet) for you

2. **Tailscale CLI** (optional, for auth key generation):
   - Windows: `choco install tailscale` or download from tailscale.com
   - macOS: `brew install tailscale`
   - Linux: `curl -fsSL https://tailscale.com/install.sh | sh`

---

## Option 1: Using Tailscale Sidecar with Docker Compose (Recommended)

### Step 1: Generate Tailscale Auth Key

**Via Web UI** (Easiest):
1. Go to https://login.tailscale.com/
2. Navigate to **Settings → Auth Keys**
3. Click **Generate auth key**
4. Configure:
   - Expiration: 90 days
   - Ephemeral: OFF (so it persists)
   - Pre-approved: ON (auto-approves new devices)
5. Copy the auth key

**Via Tailscale CLI**:
```bash
tailscale login  # First time only
tailscale auth-key --reusable
```

### Step 2: Set Environment Variable

**Windows PowerShell**:
```powershell
$env:TAILSCALE_AUTHKEY = "tskey-auth-XXXXX"
```

**Windows Command Prompt**:
```cmd
set TAILSCALE_AUTHKEY=tskey-auth-XXXXX
```

**macOS/Linux**:
```bash
export TAILSCALE_AUTHKEY=tskey-auth-XXXXX
```

Or add to `.env`:
```
TAILSCALE_AUTHKEY=tskey-auth-XXXXX
```

### Step 3: Start with Tailscale

```bash
cd C:\projects\my-app

# Option A: Use docker-compose-tailscale.yml
docker compose -f docker-compose-tailscale.yml up -d

# Option B: Export env var and use standard compose (if using .env)
docker compose up -d
```

### Step 4: Verify Tailscale Connection

```bash
# Check if Tailscale container is running
docker ps | grep tailscale

# View Tailscale logs
docker compose logs tailscale

# Inside the container:
docker exec my-app-tailscale tailscale status

# You should see output like:
# 100.x.x.x    vision-platform-local    you@example.com  linux   -
```

### Step 5: Access Services Remotely

Once Tailscale is connected, you can access services from ANY machine on your tailnet:

**From another machine on Tailscale**:

```bash
# Health check
curl http://vision-platform-local:8080/health

# Detection API
curl -X POST http://vision-platform-local:8080/api/v1/detect \
  -H "Content-Type: application/json" \
  -d '{"type":"battery_pack","attributes":{"scuffing_score":0.72},"confidence":0.92}'

# PostgreSQL (if exposed - not recommended)
# psql -h vision-platform-local -U pgadmin -d visiondb

# Redis (if exposed - not recommended)
# redis-cli -h vision-platform-local
```

---

## Option 2: Tailscale on Host Machine (Alternative)

If you prefer NOT to use Docker sidecar:

### Step 1: Install Tailscale on Host

**Windows**: Download from https://tailscale.com/download/windows
**macOS**: `brew install tailscale`
**Linux**: `curl -fsSL https://tailscale.com/install.sh | sh`

### Step 2: Authenticate

```bash
tailscale login
```

A browser window opens. Log in with your account.

### Step 3: Get Your Tailscale IP

```bash
tailscale status

# Output example:
# 100.x.x.x    your-computer-name     you@example.com  windows  -
```

### Step 4: Access Services Locally

Services are accessible on `localhost` as usual:
```bash
curl http://localhost:8080/health
```

Remote machines can access via your Tailscale IP or hostname:
```bash
# From another machine on tailnet
curl http://your-computer-name:8080/health
curl http://100.x.x.x:8080/health
```

---

## Network Architecture

```
┌─────────────────────────────────────────────────────────┐
│              Your Tailscale Network (Tailnet)            │
│                                                         │
│  ┌──────────────────────────────────────────────────┐  │
│  │  Docker Compose Host (100.x.x.x)                │  │
│  │  ┌──────────────────────────────────────────┐   │  │
│  │  │  vision-network                          │   │  │
│  │  │  ├─ postgres:5432                        │   │  │
│  │  │  ├─ redis:6379                           │   │  │
│  │  │  ├─ rule-engine:8080 ◄────────┐          │   │  │
│  │  │  └─ tailscale (sidecar)        │          │   │  │
│  │  └──────────────────────────────────────────┘   │  │
│  │                                                 │  │
│  └─────────────────────┬──────────────────────────┘  │
│                        │                             │
│              Encrypted Tailscale VPN               │
│                        │                             │
│  ┌────────────────┬────┘                             │
│  │                │                                 │
│  │  Developer Laptop         │  Another Team Member  │
│  │  (On Tailnet)             │  (On Tailnet)         │
│  │  100.y.y.y                │  100.z.z.z            │
│  │                           │                       │
│  │  Can access:              │  Can access:          │
│  │  - localhost:8080         │  - vision-platform    │
│  │  - postgres via sidecar   │  - :8080              │
│  │    (if exposed)           │                       │
│  │                           │                       │
│  └───────────────────────────┘                       │
│                                                     │
└──────────────────────────────────────────────────────┘
```

---

## Security Best Practices

### DO:
- ✅ Use **pre-approved auth keys** for automated deployments
- ✅ Set auth key **expiration** (e.g., 90 days)
- ✅ Limit **port exposure** — only open what's needed (8080 for API)
- ✅ Use **Access Control Lists (ACLs)** to restrict which devices can reach services
- ✅ Keep Tailscale client **updated** (auto-updates by default)
- ✅ Use **ephemeral auth keys** for temporary access (CI/CD)

### DON'T:
- ❌ Expose PostgreSQL (port 5432) publicly — keep it internal only
- ❌ Expose Redis (port 6379) — keep it internal only
- ❌ Share auth keys — generate one per environment
- ❌ Use long-lived reusable keys for temporary deployments
- ❌ Disable **funnel** / **serve** unless explicitly needed

---

## Tailscale ACL (Access Control List)

By default, all devices on your tailnet can reach all services. To restrict:

1. Go to https://login.tailscale.com/ → **Settings → ACLs**
2. Edit policy. Example:

```hcl
// Allow all to all (default permissive policy)
{
  "Groups": {
    "group:dev": ["your-github-login"],
    "group:prod": ["you@example.com"],
  },
  "Acls": [
    // Dev machines can access Rule Engine
    {"Action": "accept", "Principal": "group:dev", "Resources": ["100.x.x.x:8080"]},
    
    // Prod only can access everything
    {"Action": "accept", "Principal": "group:prod", "Resources": ["100.x.x.x:*"]},
    
    // Deny all by default
    {"Action": "reject", "Principal": "*", "Resources": ["*:*"},
  ],
}
```

---

## Troubleshooting

### Tailscale Container Won't Start
```bash
docker compose logs tailscale

# Common issues:
# 1. Auth key expired → generate new key
# 2. Auth key not in env → set TAILSCALE_AUTHKEY
# 3. Network issues → check docker network
```

### Can't Connect from Remote Machine

**Check 1**: Is Tailscale running on remote?
```bash
tailscale status
```
Should show both your machine and remote machine.

**Check 2**: Can you ping?
```bash
# From remote machine
ping vision-platform-local
# or
ping 100.x.x.x
```

**Check 3**: Check firewall (docker-compose ports)
```bash
docker compose ps  # Verify ports are published

# 8080 should be listed
```

**Check 4**: Check Tailscale web console
```
https://login.tailscale.com/admin/machines
```
Both machines should be listed and marked "Online" and "Connected".

### Performance Issues

If connection is slow:
1. Check if on same network (local) — should be <1ms latency
2. Try a closer Tailscale exit node (in console)
3. Restart tailscale: `docker compose restart tailscale`

---

## Removing Tailscale

**Temporary disable**:
```bash
docker compose stop tailscale
```

**Permanent removal**:
```bash
# Remove device from tailnet
https://login.tailscale.com/admin/machines

# Or from command line (if Tailscale installed on host):
tailscale logout

# Or stop Docker container:
docker compose -f docker-compose-tailscale.yml down
```

---

## Next Steps

1. **Set auth key**: Generate at https://login.tailscale.com/admin/settings/keys
2. **Start stack**: `docker compose -f docker-compose-tailscale.yml up -d`
3. **Verify**: `docker exec my-app-tailscale tailscale status`
4. **Test**: `curl http://vision-platform-local:8080/health` from another tailnet machine
5. **Restrict ports**: Only expose what's needed (8080 for API, not 5432/6379)

---

## References

- **Tailscale Docs**: https://tailscale.com/kb/
- **Docker Tailscale Image**: https://hub.docker.com/r/tailscale/tailscale
- **ACL Docs**: https://tailscale.com/kb/1018/acls/
- **MagicDNS**: https://tailscale.com/kb/1081/magicdns/
