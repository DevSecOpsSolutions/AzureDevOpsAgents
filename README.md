# Azure DevOps Self-Hosted Agents on Kubernetes StatefulSet (With Docker-in-Docker and KEDA)

## Introduction

This project deploys Azure DevOps self-hosted agents as a Kubernetes StatefulSet, using a custom agent image that runs in a Docker-in-Docker model and scales on demand with KEDA.

Why this approach works well for build workloads:

- Docker-in-Docker support allows each agent pod to build and run Docker images directly inside the agent container.
- StatefulSet + per-pod persistent volume keeps Docker workspace and layer cache isolated for each agent replica.
- KEDA can scale replicas based on Azure Pipelines queue demand, so you keep a small baseline and scale out only when jobs arrive.

This repository includes:

- Main Docker image definition: [Dockerfile](Dockerfile)
- Agent entrypoint and lifecycle scripts: [start.sh](start.sh), [service_health.sh](service_health.sh), [dockercleanup.sh](dockercleanup.sh)
- Main Helm chart: [helm-chart/azp-agent](helm-chart/azp-agent)
- Legacy/alternate chart copy: [azp-deploy-agent/helm-chart/azp-agent](azp-deploy-agent/helm-chart/azp-agent)

## Architecture

At runtime, each pod:

1. Starts an Azure DevOps agent and registers into the configured pool.
2. Starts Docker service inside the container (privileged mode).
3. Uses a mounted workspace path for job files and Docker data.
4. Is scaled by a KEDA ScaledObject using the Azure Pipelines trigger.

The StatefulSet headless service is defined in [helm-chart/azp-agent/templates/azp-agent-svc.yaml](helm-chart/azp-agent/templates/azp-agent-svc.yaml), and KEDA resources are defined in [helm-chart/azp-agent/templates/keda.yaml](helm-chart/azp-agent/templates/keda.yaml).

## Prerequisites

- Kubernetes cluster (AKS or any conformant cluster)
- Helm 3+
- kubectl access to your cluster
- Azure DevOps organization and a target Agent Pool
- Personal Access Token (PAT) with Agent Pools Read & Manage permissions
- KEDA installed in the cluster

Install KEDA (example):

```bash
helm repo add kedacore https://kedacore.github.io/charts
helm repo update
helm upgrade --install keda kedacore/keda --namespace keda --create-namespace
```

## 1) Build and push the custom agent image

The main image is defined in [Dockerfile](Dockerfile). It includes:

- Azure CLI
- Docker Engine + Docker Compose (for Docker-in-Docker jobs)
- Node.js and Python tooling
- .NET SDK
- Health and cleanup cron jobs

Build and push:

```bash
docker build -t <registry>/<repo>:<tag> .
docker push <registry>/<repo>:<tag>
```

If you use a private registry, make sure imagePullSecret is configured via Helm values.

## 2) Prepare Azure DevOps values

Collect these values:

- AZP URL, for example: https://dev.azure.com/<your-org>
- Agent Pool name (must exist)
- Agent Pool numeric ID (required by KEDA trigger)
- PAT token

The chart currently stores poolID as a static value in [helm-chart/azp-agent/templates/keda.yaml](helm-chart/azp-agent/templates/keda.yaml), so update that file to your real pool ID before deployment.

## 3) Configure Helm values

Edit [helm-chart/azp-agent/values.yaml](helm-chart/azp-agent/values.yaml) and set at minimum:

- image.repository
- image.tag
- image.pullPolicy
- image.imagePullSecret (if private registry)
- azpUrl
- azpPool
- azpToken
- azpWorkspace (defaults to /var/lib/docker in this repo)
- resources and disk size
- keda.minReplicaCount / maxReplicaCount / pollingInterval

Important value notes from this repository:

- The StatefulSet runs privileged for Docker-in-Docker in [helm-chart/azp-agent/templates/azp-agent.yaml](helm-chart/azp-agent/templates/azp-agent.yaml).
- A PVC template named workspace is created per replica in [helm-chart/azp-agent/templates/azp-agent.yaml](helm-chart/azp-agent/templates/azp-agent.yaml).
- PAT is also templated into Kubernetes Secret objects in [helm-chart/azp-agent/templates/azp-agent-secret.yaml](helm-chart/azp-agent/templates/azp-agent-secret.yaml) and [helm-chart/azp-agent/templates/keda.yaml](helm-chart/azp-agent/templates/keda.yaml).

## 4) Deploy the StatefulSet and KEDA scaler

```bash
kubectl create namespace build-agents

helm upgrade --install azp-agent ./helm-chart/azp-agent \
	--namespace build-agents \
	--set image.repository=<registry>/<repo> \
	--set image.tag=<tag> \
	--set azpUrl=https://dev.azure.com/<your-org> \
	--set azpPool=<your-pool-name> \
	--set azpToken=<your-pat>
```

Check resources:

```bash
kubectl get pods -n build-agents
kubectl get statefulset -n build-agents
kubectl get scaledobject -n build-agents
kubectl get triggerauthentication -n build-agents
```

## 5) Validate agent registration and scaling

1. Open Azure DevOps Agent Pools and confirm agents are online.
2. Queue multiple jobs targeting the configured pool.
3. Watch replicas scale:

```bash
kubectl get pods -n build-agents -w
```

4. Confirm scale-down after queue drains (subject to KEDA behavior and cooldown settings).

## Operational behavior in this image

- Agent bootstrap and registration: [start.sh](start.sh)
- Docker health auto-restart via cron: [service_health.sh](service_health.sh)
- Disk-pressure cleanup for Docker images/containers: [dockercleanup.sh](dockercleanup.sh)

These scripts are designed to keep long-running agents healthy in a StatefulSet deployment where the same pod may process many jobs.

## Security and production hardening recommendations

Before publishing this to production, apply these improvements:

1. Move PAT handling to external secret management (for example, Key Vault + CSI driver or External Secrets).
2. Remove hardcoded registry credential secret from [helm-chart/azp-agent/templates/secret.yaml](helm-chart/azp-agent/templates/secret.yaml).
3. Parameterize KEDA poolID in values.yaml instead of hardcoding in template.
4. Restrict RBAC and namespace access for build agents.
5. Consider rootless/sidecar Docker alternatives if your security policy disallows privileged containers.

## Troubleshooting

Common checks:

```bash
kubectl logs -n build-agents statefulset/azp-agent
kubectl describe scaledobject azure-pipelines-scaledobject -n build-agents
kubectl describe pod <pod-name> -n build-agents
```

If agents do not scale:

- Verify TriggerAuthentication secret and PAT scope.
- Verify poolID in KEDA trigger matches the real Azure DevOps pool ID.
- Verify organization URL and AZP_POOL values are correct.

If Docker builds fail inside agent:

- Check privileged securityContext and Docker service startup logs.
- Verify workspace and PVC capacity (disk pressure can break builds).

## Optional: Deploy the alternate chart

This repo also contains a second chart variant under [azp-deploy-agent/helm-chart/azp-agent](azp-deploy-agent/helm-chart/azp-agent). Use the same deployment process, but confirm values and poolID in that chart before installing.

## Summary

This implementation gives you a practical Azure DevOps self-hosted agent platform on Kubernetes:

- StatefulSet for stable identity and per-agent storage
- Docker-in-Docker for container build pipelines
- KEDA-driven on-demand scaling for queue-based elasticity

It is a strong base for CI workloads, and with secret/RBAC hardening it is ready for production-grade operations.