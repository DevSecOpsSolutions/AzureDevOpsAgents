## Introduction

This repo provides a [Helm](https://helm.sh) chart to deploy [Azure Pipelines agents](https://docs.microsoft.com/en-us/azure/devops/pipelines/agents/agents) as containers to an [Azure Kubernetes Service](https://azure.microsoft.com/en-us/services/kubernetes-service) (AKS) cluster. A Dockerfile for the Azure Pipelines agent is also provided as well as guidance on how to create the AKS cluster.

## Prerequisites
 - [Docker](https://docs.docker.com/install)
 - [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
 - [Helm](https://github.com/helm/helm/releases)
 - [An Azure DevOps organization](https://docs.microsoft.com/en-us/azure/devops/organizations/accounts/create-organization)
 - [An Azure subscription](https://azure.microsoft.com/en-us/free)

## Create an Azure DevOps personal access token (PAT)
Create a personal access token with the **Agent Pools(read, manage)** scope following [these instructions](https://docs.microsoft.com/en-us/azure/devops/organizations/accounts/use-personal-access-tokens-to-authenticate). You will have to provide later this token to the `azpToken` value of the helm chart.

## Create an Azure Pipelines agent pool
Create a new agent pool foolowing [these instructions](https://docs.microsoft.com/en-us/azure/devops/pipelines/agents/pools-queues?#managing-pools-and-queues). Your azure pipelines agents will join this pool later on.

## Customize, build and publish the docker image
The Dockerfile available at `dockeragent\ubuntu\16.04\` contains the basic tools needed to run the Azure Pipelines agent on Linux (as documented [here](https://docs.microsoft.com/en-us/azure/devops/pipelines/agents/docker?#linux)) but feel free to customize it with any aditional tools you might need. Then, you will build and publish the image to Docker Hub (if you don't have a Docker ID you can create one for free [here](https://hub.docker.com)).

Run the following commands in a command prompt to build and publish your image, replacing `yourdockerid` with your Docker ID:

```
docker build -t yourdockerid/azpagent:ubuntu-16.04 ./dockeragent/ubuntu/16.04
docker login
docker push yourdockerid/azpagent:ubuntu-16.04
```

You could also publish your image to a private docker registry like [Azure Container Registry](https://docs.microsoft.com/en-us/azure/container-registry) but you'll need to update the helm chart to pass the appropriate image pull secret.

## Create the AKS cluster
Run the following Azure CLI commands in a command prompt replacing `<Azure subscription name>`, `<resource group name>`, `<resource group location>` and `<cluster name>` with appropriate values for your subscription, resource group, location and kubernetes cluster:
```
az login
az account set --subscription <Azure subscription name>
az group create --name <resource group name> --location <resource group location>
az aks create -g <resource group name> -n <cluster name> --generate-ssh-keys
```

## Chart parameters
The following table lists the configurable parameters of the `azp-agent` chart and their default values.

| Parameter                         | Description                            | Default                                                                   |
| --------------------------------- | ---------------------------------------| ---------------------------------------------------------                 |
| `image.repository`                | azp-agent image                        | `nil` (must be provided during installation)                              |
| `image.tag`                       | Specify image tag                      | `nil` (must be provided during installation)                              |
| `image.pullSecrets`               | Specify image pull secrets             | `nil` (does not add image pull secrets to deployed pods)                  |
| `image.pullPolicy`                | Image pull policy                      | `Always`                                                                  |
| `replicas`                        | Number of azp-agent instaces started   | `3`                                                                       |
| `resources.disk`                  | Size of the disk attached to the agent | `50Gi`                                                                    |
| `resources.storageclass`          | Specify storageclass used in kubernetes| `default`                                                                 |
| `resources.requests`              | CPU/Memory requests                    | `nil`                                                                     |
| `resources.limits`                | CPU/Memory limits                      | `nil`                                                                     |
| `azpUrl`                          | The URL of the Azure DevOps instance   | `nil` (must be provided during installation)                              |
| `azpToken`                        | Azure DevOps personal access token     | `nil` (must be provided during installation)                              |
| `azpPool`                         | Azure Pipelines agent pool name        | `nil` (must be provided during installation)                              |
| `azpAgentName`                    | Azure Pipelines agent name             | `azp-agent`                                                               |
| `azpWorkspace`                    | Azure Pipelines agent workspace        | `/workspace`                                                              |
| `extraEnv`                        | Extra environment variables on the azp-agent container | `nil`                                                     |
| `cleanRun`                        | Kill and restart azp-agent container on completion of a pipeline run (completely resets the environment)  | `true` |
| `volumes`                         | An array of custom volumes to attach to the azp-agent pod | `nil`                                                  |
| `volumeMounts`                    | volumeMounts to the azp-agent container as referenced in `volumes` | `nil`                                         |
| `nodeSelector`                    | assign pods to nodes based on this label | `nil`                                                                   |



## Installing the chart

The chart can be installed with the following command:

```
helm install --set image.repository=<IMAGE REPO> --set image.tag:<IMAGE TAG> --set azpToken=<AZP TOKEN> --set azpUrl=<AZP URL> --set azpPool=<AZP POOL> -f helm-chart\azp-agent\values.yaml helm-chart\azp-agent azp-agent helm-chart\azp-agent
```

Example:
```
helm install --set image.repository=julioc/azpagent --set image.tag=ubuntu-16.04 --set azpToken=<TOKEN HERE> --set azpUrl=https://dev.azure.com/julioc --set azpPool=MyPool -f helm-chart\azp-agent\values.yaml azp-agent helm-chart\azp-agent
```

It may take some time to stand up the pods but eventually your deployment should look like this:

```
kubectl get pods
NAME           READY     STATUS    RESTARTS   AGE
azp-agent-0   1/1       Running   0          1m
azp-agent-1   1/1       Running   0          1m
azp-agent-2   1/1       Running   0          1m
```

## Scaling up the number of agents

You can scale up (or down) the number of pipeline agents by either using `kubectl scale`:

```
kubectl scale statefulset/azp-agent --replicas 10
```

Or by running a helm upgrade with the `replicas` parameter:

```
helm upgrade --install --set image.repository=julioc/azpagent --set image.tag=ubuntu-16.04 --set azpToken=<TOKEN HERE> --set azpUrl=https://dev.azure.com/julioc --set azpPool=MyPool --set replicas=10 -f helm-chart\azp-agent\values.yaml azp-agent helm-chart\azp-agent
```
