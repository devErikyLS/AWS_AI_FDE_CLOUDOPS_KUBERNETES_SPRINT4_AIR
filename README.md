# Kubernetes Challenge — CloudOps

A practical Kubernetes project demonstrating container orchestration, persistent storage, application configuration, secret management, service discovery, health checks, resource management, API integration with PostgreSQL, and horizontal autoscaling.

The project was developed as a hands-on Kubernetes challenge using **Docker Desktop Kubernetes** and focuses on deploying and validating a PostgreSQL database and a PostgREST API inside a dedicated Kubernetes namespace.

---

## Overview

The project demonstrates how Kubernetes resources can be combined to build a small but complete application platform.

The main workflow is:

```text
                        Kubernetes Cluster
                               │
                               ▼
                    ┌─────────────────────┐
                    │ desafio-kubernetes  │
                    │      Namespace      │
                    └──────────┬──────────┘
                               │
              ┌────────────────┴────────────────┐
              │                                 │
              ▼                                 ▼
    ┌───────────────────┐             ┌───────────────────┐
    │    PostgreSQL     │             │     PostgREST     │
    │    Deployment     │             │    Deployment     │
    │                   │             │                   │
    │    PostgreSQL     │◄────────────│    REST API       │
    │      :5432        │             │      :3000        │
    └─────────┬─────────┘             └─────────┬─────────┘
              │                                 │
              ▼                                 ▼
    ┌───────────────────┐             ┌───────────────────┐
    │ PersistentVolume  │             │    ClusterIP      │
    │      Claim        │             │     Service       │
    └───────────────────┘             └───────────────────┘
                                                │
                                                ▼
                                         External Access
                                         via port-forward
```

The PostgreSQL database stores application data on a PersistentVolumeClaim, while PostgREST exposes the database table through a REST API.

Kubernetes Services provide stable internal service discovery, allowing PostgREST to connect to PostgreSQL using the Kubernetes Service name instead of a Pod IP.

The PostgREST Deployment also includes readiness and liveness probes, resource requests and limits, and multiple replicas. An optional Horizontal Pod Autoscaler was implemented and validated to automatically adjust the number of API replicas according to CPU utilization.

---

## Technologies

- Kubernetes 1.32.2
- Docker Desktop Kubernetes
- PostgreSQL 16
- PostgREST 14.1
- Kubernetes YAML manifests
- SQL
- PersistentVolumeClaim
- ConfigMap
- Secret
- ClusterIP Services
- Readiness and Liveness Probes
- Horizontal Pod Autoscaler
- Metrics Server
- GitHub Actions
- Kubeconform

---

# Kubernetes Architecture

## Namespace

All application resources are isolated inside the dedicated namespace:

```text
desafio-kubernetes
```

Manifest:

```text
k8s/01-namespace.yaml
```

The namespace provides a dedicated boundary for the challenge resources and keeps the application workloads isolated from unrelated Kubernetes resources.

All application manifests are explicitly assigned to this namespace.

---

## Standalone Pod

The challenge requires a standalone Pod created independently from a Deployment.

Manifest:

```text
k8s/00-standalone-pod.yaml
```

The Pod uses:

```text
nginx:alpine
```

and is named:

```text
teste-pod
```

The Pod was inspected using:

```bash
kubectl get pod -n desafio-kubernetes
kubectl describe pod teste-pod -n desafio-kubernetes
kubectl logs teste-pod -n desafio-kubernetes
```

The Pod was then deleted to demonstrate the behavior of a standalone Pod.

A standalone Pod does not recreate itself after deletion. This demonstrates why controller-managed workloads such as Deployments are used when self-healing is required.

---

# PostgreSQL

PostgreSQL runs through a Kubernetes Deployment with a single replica.

Manifest:

```text
k8s/04-postgres-deployment.yaml
```

Image:

```text
postgres:16-alpine
```

The Deployment obtains the database name, username, and password from a Kubernetes Secret.

The PostgreSQL data directory is mounted at:

```text
/var/lib/postgresql/data
```

through the PersistentVolumeClaim:

```text
postgres-pvc
```

---

## Persistent Storage

The PostgreSQL database uses a PersistentVolumeClaim requesting:

```text
1Gi
```

Manifest:

```text
k8s/03-postgres-pvc.yaml
```

Access mode:

```text
ReadWriteOnce
```

The persistence behavior was explicitly validated:

1. Data was inserted into PostgreSQL through the API.
2. The data was retrieved before PostgreSQL Pod deletion.
3. The PostgreSQL Pod was deleted.
4. The Deployment created a replacement Pod.
5. The PVC remained bound.
6. The same data was retrieved again through the API.

This demonstrates that the application data survives the PostgreSQL Pod lifecycle because the data is stored on persistent storage.

---

## PostgreSQL Service

PostgreSQL is exposed internally through a Kubernetes ClusterIP Service:

```text
postgres-service
```

Manifest:

```text
k8s/05-postgres-service.yaml
```

The Service listens on:

```text
5432
```

PostgREST connects to PostgreSQL through the Kubernetes Service name:

```text
postgres-service
```

This provides stable service discovery even when the PostgreSQL Pod is recreated.

---

# Configuration and Secrets

## ConfigMap

Non-sensitive PostgREST configuration is stored in:

```text
postgrest-config
```

Manifest:

```text
k8s/06-postgrest-configmap.yaml
```

The ConfigMap contains:

```text
PGRST_DB_SCHEMAS
PGRST_DB_ANON_ROLE
PGRST_SERVER_PORT
```

These values are non-sensitive configuration and therefore are stored in a ConfigMap rather than a Secret.

---

## Secret

Database credentials are stored in:

```text
postgres-secret
```

The repository intentionally contains only an example manifest:

```text
k8s/02-postgres-secret.example.yaml
```

The example does not contain a real password:

```text
POSTGRES_PASSWORD: CHANGE_ME
```

The actual Secret is created locally:

```bash
kubectl create secret generic postgres-secret \
  --from-literal=POSTGRES_DB=app_db \
  --from-literal=POSTGRES_USER=app_user \
  --from-literal=POSTGRES_PASSWORD=app_password \
  --namespace=desafio-kubernetes
```

The real credentials are therefore not committed to the repository.

Both PostgreSQL and PostgREST obtain the required password through Kubernetes Secret references.

---

# PostgREST API

PostgREST runs through a Kubernetes Deployment with two replicas.

Manifest:

```text
k8s/07-postgrest-deployment.yaml
```

Image:

```text
postgrest/postgrest:v14.1
```

The PostgreSQL connection string is:

```text
postgres://app_user@postgres-service:5432/app_db
```

The important part of the integration is:

```text
postgres-service
```

PostgREST does not connect directly to a PostgreSQL Pod IP. It connects through the Kubernetes Service.

The database password is injected from the Secret, while the remaining non-sensitive PostgREST configuration is injected from the ConfigMap.

---

# Database Setup

The database initialization script is located at:

```text
sql/01-setup.sql
```

It creates the `items` table:

```sql
CREATE TABLE IF NOT EXISTS items (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL
);
```

The script also creates the `anon` role when necessary and grants the permissions required by PostgREST.

The database initialization logic is kept separate from the Kubernetes manifests.

---

# API Service and External Access

PostgREST is exposed internally through:

```text
postgrest-service
```

Manifest:

```text
k8s/08-postgrest-service.yaml
```

The Service exposes:

```text
3000
```

For local external access, the Service can be exposed through port forwarding:

```bash
kubectl port-forward \
  svc/postgrest-service \
  3000:3000 \
  -n desafio-kubernetes
```

The API is then available at:

```text
http://localhost:3000
```

This provides external access to the API without exposing the Kubernetes Service through a LoadBalancer or Ingress, keeping the implementation proportional to the challenge requirements.

---

# API Integration Validation

The `items` table is exposed through PostgREST.

## Retrieve data

```bash
curl http://localhost:3000/items
```

Example response:

```json
[
  {
    "id": 1,
    "name": "produto teste"
  }
]
```

## Insert data

```bash
curl -X POST \
  http://localhost:3000/items \
  -H "Content-Type: application/json" \
  -d '{"name":"produto teste"}'
```

The item is persisted in PostgreSQL through PostgREST.

The integration was validated by inserting data through the API and subsequently retrieving the same data through the API.

---

# Persistence Validation

Persistence was validated through the complete API-to-database workflow.

The validation sequence was:

```text
POST /items
     │
     ▼
 PostgREST
     │
     ▼
 PostgreSQL
     │
     ▼
 PersistentVolumeClaim
```

The PostgreSQL Pod was then deleted.

Kubernetes recreated the Pod through the Deployment:

```text
PostgreSQL Pod
      │
      │ deleted
      ▼
  Deployment
      │
      ▼
New PostgreSQL Pod
      │
      ▼
Same PVC
      │
      ▼
Original data available
      │
      ▼
GET /items
```

The same item inserted through the API was successfully retrieved through the API after the PostgreSQL Pod was recreated.

This proves the required persistence behavior rather than only verifying that a PVC exists.

---

# Health Checks and Resource Management

The PostgREST Deployment defines both readiness and liveness probes.

## Readiness Probe

The readiness probe determines whether a PostgREST Pod is ready to receive traffic:

```yaml
readinessProbe:
  httpGet:
    path: /
    port: 3000
  initialDelaySeconds: 5
  periodSeconds: 10
  timeoutSeconds: 2
  failureThreshold: 3
```

## Liveness Probe

The liveness probe allows Kubernetes to detect an unhealthy PostgREST container:

```yaml
livenessProbe:
  httpGet:
    path: /
    port: 3000
  initialDelaySeconds: 15
  periodSeconds: 20
  timeoutSeconds: 2
  failureThreshold: 3
```

## Resource Requests and Limits

Each PostgREST replica defines:

```yaml
resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    cpu: "500m"
    memory: "256Mi"
```

These settings provide Kubernetes with resource information for scheduling and establish resource boundaries for the application container.

---

# Bonus: Horizontal Pod Autoscaler

The project also implements the optional HPA bonus.

Manifest:

```text
k8s/09-postgrest-hpa.yaml
```

The HPA targets:

```text
Deployment/postgrest
```

Configuration:

```text
Minimum replicas: 2
Maximum replicas: 4
CPU target: 70%
```

The HPA uses CPU metrics provided by Metrics Server.

The scaling behavior was explicitly tested by generating traffic against the PostgREST Service.

Observed behavior:

```text
2 replicas
    │
    │ Increased CPU load
    ▼
4 replicas
    │
    │ Load removed
    ▼
2 replicas
```

Both scale-up and scale-down behavior were successfully observed and captured in the project evidence.

---

# Metrics Server

Metrics Server was used to provide CPU metrics required by the HPA.

The local Docker Desktop Kubernetes environment required the following environment-specific configuration:

```bash
kubectl patch deployment metrics-server \
  -n kube-system \
  --type='json' \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
```

After the adjustment, resource metrics were available through:

```bash
kubectl top nodes
kubectl top pods -n desafio-kubernetes
```

This configuration is specific to the local Docker Desktop environment and is not part of the application manifests.

---

# Project Structure

```text
kubernetes-challenge/
├── .github/
│   └── workflows/
│       └── validate-manifests.yml
│
├── evidence/
│   ├── stage_01/
│   ├── stage_02/
│   ├── stage_03/
│   ├── stage_04/
│   ├── stage_05/
│   ├── stage_06/
│   ├── stage_07/
│   ├── stage_08/
│   ├── stage_09/
│   ├── stage_10/
│   ├── stage_11/
│   ├── stage_12/
│   └── stage_13/
│
├── k8s/
│   ├── 00-standalone-pod.yaml
│   ├── 01-namespace.yaml
│   ├── 02-postgres-secret.example.yaml
│   ├── 03-postgres-pvc.yaml
│   ├── 04-postgres-deployment.yaml
│   ├── 05-postgres-service.yaml
│   ├── 06-postgrest-configmap.yaml
│   ├── 07-postgrest-deployment.yaml
│   ├── 08-postgrest-service.yaml
│   └── 09-postgrest-hpa.yaml
│
├── sql/
│   └── 01-setup.sql
│
├── .gitignore
└── README.md
```

All Kubernetes resources are versioned as declarative YAML manifests under `k8s/`.

The numbered filenames make the intended resource order clear and provide an organized structure for review and deployment.

---

# Local Development

## Requirements

The project requires:

- Docker Desktop
- Kubernetes enabled in Docker Desktop
- `kubectl`
- Git

The cluster used during development was:

```text
Kubernetes v1.32.2
Docker Desktop Kubernetes
```

---

## 1. Create the Namespace

```bash
kubectl apply -f k8s/01-namespace.yaml
```

---

## 2. Create the Local Secret

The real Secret is intentionally created outside version-controlled YAML files:

```bash
kubectl create secret generic postgres-secret \
  --from-literal=POSTGRES_DB=app_db \
  --from-literal=POSTGRES_USER=app_user \
  --from-literal=POSTGRES_PASSWORD=app_password \
  --namespace=desafio-kubernetes
```

If the Secret already exists, do not recreate it unnecessarily.

---

## 3. Apply the Kubernetes Manifests

Once the namespace and Secret exist, the versioned manifests can be applied together:

```bash
kubectl apply -f k8s/
```

The numbered filenames provide a clear logical application order.

The Secret example file is intentionally not used as the real credential source.

---

## 4. Verify the Workloads

```bash
kubectl get all -n desafio-kubernetes
```

Check persistent storage:

```bash
kubectl get pvc -n desafio-kubernetes
```

Check Services:

```bash
kubectl get svc -n desafio-kubernetes
```

---

## 5. Initialize the Database

The SQL setup script is:

```text
sql/01-setup.sql
```

It creates the `items` table and the required PostgREST role and permissions.

The script can be executed against the PostgreSQL instance after the database Pod is ready.

---

## 6. Access the API

Forward the PostgREST Service port:

```bash
kubectl port-forward \
  svc/postgrest-service \
  3000:3000 \
  -n desafio-kubernetes
```

Then test:

```bash
curl http://localhost:3000/items
```

---

# Validation Commands

## Cluster Resources

```bash
kubectl get all -n desafio-kubernetes
```

## Persistent Storage

```bash
kubectl get pvc -n desafio-kubernetes
```

## PostgreSQL Service Endpoints

```bash
kubectl get endpoints postgres-service \
  -n desafio-kubernetes
```

## PostgREST Service Endpoints

```bash
kubectl get endpoints postgrest-service \
  -n desafio-kubernetes
```

## HPA

```bash
kubectl get hpa -n desafio-kubernetes
```

## Resource Metrics

```bash
kubectl top pods -n desafio-kubernetes
kubectl top nodes
```

## PostgreSQL Logs

```bash
kubectl logs deployment/postgres \
  -n desafio-kubernetes
```

## PostgREST Logs

```bash
kubectl logs deployment/postgrest \
  -n desafio-kubernetes
```

## Pod Details and Events

```bash
kubectl describe pod <pod-name> \
  -n desafio-kubernetes
```

These commands provide the primary tools used to inspect workloads, events, logs, storage, services, metrics, and autoscaling behavior.

---

# Continuous Integration

The repository includes a lightweight GitHub Actions workflow for Kubernetes manifest validation:

```text
.github/workflows/validate-manifests.yml
```

The workflow runs on:

- Pushes to `main`
- Pull requests targeting `main`

It uses Kubeconform to validate the manifests against Kubernetes `1.32.2`.

The validation is intentionally limited to manifest correctness. It does not create a temporary Kubernetes cluster, deploy PostgreSQL, run PostgREST integration tests, or execute HPA load tests.

This keeps CI fast and proportional to the scope of the challenge while providing an automated quality check for version-controlled Kubernetes manifests.

The manifests were also validated locally using the same validator:

```text
10 resources found in 10 files
Valid: 10
Invalid: 0
Errors: 0
Skipped: 0
```

The CI workflow itself was successfully executed through GitHub Actions.

---

# Required Evidence

The project contains organized evidence under `evidence/`.

The main required evidence from the challenge is covered by the following stages.

| Required Evidence                             | Location                                                 |
| --------------------------------------------- | -------------------------------------------------------- |
| Kubernetes resources running in the namespace | `evidence/stage_07/` and related stages                  |
| API returning data from PostgreSQL            | `evidence/stage_08/` and `evidence/stage_09/`            |
| Data before PostgreSQL Pod deletion           | `evidence/stage_10/01-data-before-postgres-delete.png`   |
| PostgreSQL Pod recreated                      | `evidence/stage_10/02-postgres-pod-recreated.png`        |
| PVC still bound                               | `evidence/stage_10/03-pvc-still-bound.png`               |
| Same data after PostgreSQL Pod recreation     | `evidence/stage_10/04-data-after-postgres-recreated.png` |

Additional evidence covers configuration, health checks, resource management, scaling, and HPA behavior.

---

# Evidence by Stage

| Stage    | Validation                                     |
| -------- | ---------------------------------------------- |
| Stage 01 | Standalone Pod lifecycle                       |
| Stage 02 | PostgreSQL Deployment and Secret               |
| Stage 03 | PersistentVolumeClaim and database persistence |
| Stage 04 | PostgreSQL Service and service discovery       |
| Stage 05 | PostgREST ConfigMap                            |
| Stage 06 | PostgreSQL and PostgREST database setup        |
| Stage 07 | PostgREST Deployment                           |
| Stage 08 | PostgREST Service and API access               |
| Stage 09 | External API operations                        |
| Stage 10 | Persistence after PostgreSQL Pod recreation    |
| Stage 11 | Health checks and resource configuration       |
| Stage 12 | PostgREST scaling and multiple requests        |
| Stage 13 | HPA scale-up and scale-down                    |

---

# Troubleshooting

## Pod in `Pending`

Inspect the Pod:

```bash
kubectl describe pod <pod-name> \
  -n desafio-kubernetes
```

Check whether the PVC is bound:

```bash
kubectl get pvc -n desafio-kubernetes
```

A `Pending` Pod may indicate insufficient resources or an unavailable volume.

---

## Pod in `CrashLoopBackOff`

Check the container logs:

```bash
kubectl logs <pod-name> \
  -n desafio-kubernetes
```

Then inspect Kubernetes events:

```bash
kubectl describe pod <pod-name> \
  -n desafio-kubernetes
```

Common causes include incorrect configuration, missing environment variables, or application startup failures.

---

## PostgREST Cannot Connect to PostgreSQL

Verify that the connection string uses the Kubernetes Service name:

```text
postgres-service
```

Check the PostgreSQL Service:

```bash
kubectl get svc postgres-service \
  -n desafio-kubernetes
```

Check the PostgreSQL Pod:

```bash
kubectl get pods \
  -l app=postgres \
  -n desafio-kubernetes
```

Also verify that the credentials in the Secret match the credentials expected by PostgreSQL.

---

## Inspect Logs and Events

For application-level problems:

```bash
kubectl logs <pod-name> \
  -n desafio-kubernetes
```

For Kubernetes-level problems:

```bash
kubectl describe pod <pod-name> \
  -n desafio-kubernetes
```

The Events section at the end of `kubectl describe` is particularly useful for identifying scheduling, image, volume, and configuration problems.

---

# Cleanup

Because the application resources are isolated inside the dedicated namespace, the entire challenge environment can be removed with:

```bash
kubectl delete namespace desafio-kubernetes
```

Deleting the namespace removes the resources belonging to the challenge.

This provides a simple way to clean up the local environment after testing.

---

# Challenge Acceptance Criteria

| Requirement                                                | Status                               |
| ---------------------------------------------------------- | ------------------------------------ |
| Dedicated Kubernetes namespace                             | ✅ Implemented and validated         |
| All application resources isolated in the namespace        | ✅ Implemented                       |
| Standalone Pod                                             | ✅ Implemented and validated         |
| PostgreSQL running with PersistentVolumeClaim              | ✅ Implemented and validated         |
| Database credentials stored in a Secret                    | ✅ Implemented                       |
| Credentials not hardcoded in versioned YAML                | ✅ Verified                          |
| Non-sensitive configuration stored in ConfigMap            | ✅ Implemented                       |
| PostgREST connected through PostgreSQL Service name        | ✅ Implemented and validated         |
| API accessible from outside the cluster                    | ✅ Validated through port-forward    |
| API serving data from PostgreSQL                           | ✅ Validated                         |
| Data inserted through API survives PostgreSQL Pod deletion | ✅ Proven with before/after evidence |
| Liveness probe configured                                  | ✅ Implemented and validated         |
| Readiness probe configured                                 | ✅ Implemented and validated         |
| Resource requests defined                                  | ✅ Implemented                       |
| Resource limits defined                                    | ✅ Implemented                       |
| Kubernetes manifests organized and versioned               | ✅ Implemented                       |
| README documents application and validation procedures     | ✅ Completed                         |
| Required evidence collected                                | ✅ Completed                         |
| HPA bonus                                                  | ✅ Implemented and validated         |
| Automated manifest validation                              | ✅ Implemented and validated         |

---

# Final Result

The project delivers a complete Kubernetes-based application workflow combining:

```text
Namespace
   │
   ├── PostgreSQL Deployment
   │      │
   │      └── PersistentVolumeClaim
   │
   ├── PostgreSQL Service
   │
   ├── Secret
   │
   ├── ConfigMap
   │
   ├── PostgREST Deployment
   │      │
   │      ├── 2 replicas
   │      ├── Readiness Probe
   │      ├── Liveness Probe
   │      └── Resource Requests/Limits
   │
   ├── PostgREST Service
   │
   └── HPA
          │
          └── 2–4 replicas
```

The implementation satisfies the core challenge requirements for:

- Kubernetes namespace isolation;
- PostgreSQL deployment;
- persistent storage;
- Secret-based credentials;
- ConfigMap-based configuration;
- Service-based database discovery;
- PostgREST API integration;
- external API access;
- verified database persistence;
- health checks;
- resource management;
- organized and versioned manifests.

The optional HPA requirement was also implemented and validated, including both scale-up and scale-down behavior.

Finally, the repository includes organized evidence and a lightweight GitHub Actions workflow that automatically validates the Kubernetes manifests, providing an additional layer of consistency and maintainability.

The result is a reproducible Kubernetes implementation with clear resource organization, documented deployment and validation procedures, and evidence supporting the required functionality.
