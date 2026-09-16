# Deploying LearnMCP-xAPI and Scholar Explorer on Google Cloud Run

This guide explains how to deploy **LearnMCP-xAPI** on **Google Cloud Run** and configure **Scholar Explorer** (or any MCP-compatible client / AI agent) to run on Google Cloud and connect to LearnMCP-xAPI.

---

## Overview

[Google Cloud Run](https://cloud.google.com/run) is a fully managed serverless platform that automatically scales containerized applications.

By deploying LearnMCP-xAPI on Cloud Run, the server exposes an HTTP/SSE interface for MCP tools (`/sse` endpoint) and a health check endpoint (`/health`). AI agents like Scholar Explorer running on Cloud Run or in the cloud can then communicate with LearnMCP-xAPI over HTTPS.

```
+------------------------------------+          +-------------------------------------+          +----------------------+
| Scholar Explorer (Cloud Run)       |  SSE     | LearnMCP-xAPI (Cloud Run)           |  xAPI    | xAPI LRS             |
| (MCP Client / AI Agent)            | -------->| (MCP Server, port 8080)             | -------->| (Veracity/Ralph/LRS) |
| SSE Endpoint: https://.../sse      |          | Health Endpoint: https://.../health |          |                      |
+------------------------------------+          +-------------------------------------+          +----------------------+
```

---

## Prerequisites

Before starting, ensure you have:
1. A **Google Cloud Platform (GCP)** account and project.
2. The [Google Cloud SDK (`gcloud` CLI)](https://cloud.google.com/sdk/docs/install) installed and initialized:
   ```bash
   gcloud auth login
   gcloud config set project YOUR_GCP_PROJECT_ID
   ```
3. Enabled required GCP services:
   ```bash
   gcloud services enable run.googleapis.com artifactregistry.googleapis.com secretmanager.googleapis.com
   ```
4. Access to an xAPI-compliant Learning Record Store (such as Veracity Learning, Ralph LRS, or LRS SQL).

---

## Part 1: Deploying LearnMCP-xAPI to Cloud Run

### 1. Build and Deploy using `gcloud run deploy`

The repository includes a `Dockerfile` optimized for Cloud Run. You can build and deploy directly from source:

```bash
gcloud run deploy learnmcp-xapi \
  --source . \
  --region us-central1 \
  --platform managed \
  --allow-unauthenticated \
  --set-env-vars LRS_PLUGIN=veracity,ACTOR_UUID=student-cloud-user-123,ENV=production
```

*(Note: Replace `us-central1`, `LRS_PLUGIN`, and `ACTOR_UUID` with your desired configuration.)*

### 2. Configure LRS Credentials with GCP Secret Manager

For security in production environments, store sensitive LRS keys and passwords in GCP Secret Manager rather than plain environment variables.

#### Create Secrets:
```bash
# Create secret for LRS username / key
echo -n "your-lrs-username-or-key" | gcloud secrets create learnmcp-lrs-user --data-file=-

# Create secret for LRS password / secret
echo -n "your-lrs-password-or-secret" | gcloud secrets create learnmcp-lrs-password --data-file=-
```

#### Attach Secrets to Cloud Run:
```bash
gcloud run deploy learnmcp-xapi \
  --region us-central1 \
  --set-env-vars LRS_PLUGIN=veracity,VERACITY_ENDPOINT=https://your-lrs.lrs.io,ACTOR_UUID=student-cloud-user-123,ENV=production \
  --set-secrets VERACITY_USERNAME=learnmcp-lrs-user:latest,VERACITY_PASSWORD=learnmcp-lrs-password:latest
```

### 3. Verify Deployment

Once deployed, `gcloud` will output the Service URL (e.g., `https://learnmcp-xapi-xyz-uc.a.run.app`). Verify the deployment by querying the health endpoint:

```bash
curl https://learnmcp-xapi-xyz-uc.a.run.app/health
```

Expected JSON response:
```json
{
  "status": "healthy",
  "version": "1.0.0",
  "actor_uuid": "student-cloud-user-123",
  "environment": "production"
}
```

The MCP Server SSE endpoint will be available at:
`https://learnmcp-xapi-xyz-uc.a.run.app/sse`

---

## Part 2: Running Scholar Explorer on Cloud Run & Connecting to LearnMCP-xAPI

Scholar Explorer (or any MCP client agent) needs to connect to LearnMCP-xAPI's Server-Sent Events (SSE) URL.

### 1. Container Configuration for Scholar Explorer

When deploying Scholar Explorer to Cloud Run, set an environment variable pointing to the deployed LearnMCP-xAPI SSE URL:

```bash
gcloud run deploy scholar-explorer \
  --image gcr.io/YOUR_GCP_PROJECT_ID/scholar-explorer:latest \
  --region us-central1 \
  --platform managed \
  --set-env-vars LEARNMCP_XAPI_URL=https://learnmcp-xapi-xyz-uc.a.run.app/sse
```

### 2. Client Connection Configuration

In Scholar Explorer or MCP client configurations, specify the SSE connection transport:

```json
{
  "mcpServers": {
    "learnmcp-xapi": {
      "url": "https://learnmcp-xapi-xyz-uc.a.run.app/sse",
      "transport": "sse"
    }
  }
}
```

---

## Part 3: Securing Cloud Run Service-to-Service Communication

If you wish to restrict public access so that only Scholar Explorer can call LearnMCP-xAPI:

1. Deploy `learnmcp-xapi` with `--no-allow-unauthenticated`:
   ```bash
   gcloud run deploy learnmcp-xapi --no-allow-unauthenticated ...
   ```
2. Grant Scholar Explorer's service account the **Cloud Run Invoker** role:
   ```bash
   gcloud run services add-iam-policy-binding learnmcp-xapi \
     --region us-central1 \
     --member="serviceAccount:SCHOLAR_EXPLORER_SA@YOUR_GCP_PROJECT_ID.iam.gserviceaccount.com" \
     --role="roles/run.invoker"
   ```
3. Ensure Scholar Explorer includes GCP ID identity tokens in HTTP request headers when invoking LearnMCP-xAPI endpoints.

---

## Environmental Variable Reference for Cloud Run

| Variable | Description | Example |
|---|---|---|
| `PORT` | Container HTTP port (injected automatically by Cloud Run) | `8080` |
| `LRS_PLUGIN` | LRS Plugin choice (`lrsql`, `ralph`, `veracity`) | `veracity` |
| `ACTOR_UUID` | Unique identifier for student / learner | `student-12345` |
| `ENV` | Deployment environment | `production` |
| `LOG_LEVEL` | Logging verbosity | `INFO` |
| `VERACITY_ENDPOINT` | Veracity LRS endpoint URL | `https://my-lrs.lrs.io` |
| `RALPH_ENDPOINT` | Ralph LRS endpoint URL | `https://ralph.example.com` |
| `LRSQL_ENDPOINT` | LRS SQL endpoint URL | `https://lrsql.example.com` |
