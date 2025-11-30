# ECP Data Platform

## Terraform

Below are the prerequisites for deploying the infrastructure for the ECP Data Platform:
1. A GCP project and a user with [Owner](https://docs.cloud.google.com/iam/docs/roles-overview#legacy-basic) permissions on the project. You must copy the project ID and set the local variable `product_id` in [constructor.tf](./terraform/constructor.tf) to the project ID.
2. The latest Terraform version installed, which can be downloaded [here](https://developer.hashicorp.com/terraform/tutorials/gcp-get-started/install-cli).
3. A Service account within the project with the relevent permissions to deploy resources e.g. Editor, IAM Policy Admin and Service Account Admin. You must create and download a key in JSON format and reference the path to the JSON file in the local variable `credentials` in [constructor.tf](./terraform/constructor.tf). 
4. The Cloud Resource Manager API must be enabled on the project before deploying resources with terraform.
5. Billing must be enabled on the project.


Once the prerequisites are satisfied, navigate to the [terraform](/terraform/) folder and run `terraform init`, `terraform plan -out=tfplan` and `terraform apply tfplan` to deploy the infrastructure. 


## CI/CD 
There is a full CI/CD pipeline for building, testing, containerising, and deploying a Python-based data processing application to Google Kubernetes Engine (GKE).
The pipeline is implemented using GitLab CI/CD and runs across four stages:
1. Lint
2. Test
3. Build
4. Deploy

The pipeline outputs a containerised version of the application and automatically deploys it to a GKE cluster using kubectl apply.

### Stage 1: Lint
Purpose: Maintain code quality and formatting across the Python application.

The stage performs the following:
 - Installs Google Cloud SDK (for consistency with later stages)
 - Creates a Python virtual environment
 - Installs application dependencies
 - Runs code format and style checks using:
    - Black (formatting)
    - Ruff (linting)
#### Tools used:
black, ruff, Python venv, google-cloud-sdk

### Stage 2: Test

Purpose: Execute the unit test suite before building or deploying.

The stage performs the following:
- Sets `PYTHONPATH` to ensure the project modules resolve correctly.
- Installs Google Cloud SDK.
- Creates a Python virtual environment.
- Installs dependencies from `requirements.txt`.
- Runs the test suite using `pytest -q`.

#### Tools used:
pytest, Python venv

### Stage 3: Build

Purpose: Build and push the Docker image to Google Artifact Registry.


The stage performs the following:
- Uses the google/cloud-sdk image.
- Enables Docker-in-Docker for building images.
- Installs Docker inside the runner.

- Authenticates to GCP:
    - Activates the service account using the JSON key provided via GitLab CI variable.
    - Configures Docker authentication for Artifact Registry.
- Builds and pushes the Docker image:

#### Tools used:
docker, gcloud, Artifact Registry

#### Improvements:
If more time was available, I would find an image that had all the prerequisite tools installed instead of manually installing docker. I would also use workload identity federation instead of a service account key.

### Stage 4: Deploy
Purpose: Deploy the newly built image to the GKE cluster.

The stage performs the following:
- Authenticates to GCP using the service account key.
- Sets the GCP project.
- Retrieves Kubernetes cluster credentials using: `gcloud container clusters get-credentials $GKE_CLUSTER --zone $GKE_ZONE`
- Rewrites the kube-manifest.yml deployment file to inject the built image: `IMAGE_PLACEHOLDER -> IMAGE_NAME:CI_COMMIT_SHA`
- Applies the updated Kubernetes manifest: `kubectl apply -f -`

#### Tools used:
gcloud, kubectl, Artifact Registry, GKE

### Environment / Pipeline Variables Required

| Variable                    | Description                                                          |
| --------------------------- | -------------------------------------------------------------------- |
| `GCP_PROJECT_ID`            | Google Cloud project ID                                              |
| `GKE_CLUSTER_NAME`          | Name of the GKE cluster to deploy to                                 |
| `GKE_CLUSTER_ZONE`          | Zone of the GKE cluster (e.g. europe-north2-a)                       |
| `CONTAINER_REGISTRY_REGION` | Artifact Registry region (e.g. europe-north2-docker.pkg.dev)         |
| `CONTAINER_REGISTRY`        | Name of the repository (e.g. my-repo)                                |
| `GCP_SERVICE_ACCOUNT_KEY`   | File type variable with JSON key for a service account with deploy privileges |

### Permissions
The permissions required for the CI runner are:
- roles/artifactregistry.writer
- roles/container.developer

### Manifest Replacement Logic
The pipeline expects the [Kubernetes manifest](./kube-manifest.yml) to contain `IMAGE_PLACEHOLDER` which is dynamically replaced with `$IMAGE_NAME:$CI_COMMIT_SHA` by `sed "s|IMAGE_PLACEHOLDER|$IMAGE_NAME:$CI_COMMIT_SHA|g" kube-manifest.yml`


### Run the pipeline stages locally

You can run the pipeline stages locally using the following commands:
1. `pip install -r beam_pipeline/requirements.txt`
2. `black --check .`
3. `ruff check .`
4. `pytest -q`
5. Auth with GCP:
    - `gcloud auth configure-docker europe-north2-docker.pkg.dev`
    - `gcloud components install gke-gcloud-auth-plugin`
    - `gcloud container clusters get-credentials "gke-ecp-data-cluster" --region "europe-north2" --project "<REPLACE WITH PROJECT ID>"`
6. `docker build -t europe-north2-docker.pkg.dev/<REPLACE WITH PROJECT ID>/ecp-registry/beam-app:latest .`
7. `docker push europe-north2-docker.pkg.dev/<REPLACE WITH PROJECT ID>/ecp-registry/beam-app:latest`
8. `sed "s|IMAGE_PLACEHOLDER|beam-app:latest|g" kube-manifest.yml | kubectl apply -f -` if on bash OR `(Get-Content kube-manifest.yml) -replace 'IMAGE_PLACEHOLDER', 'beam-app:latest' | kubectl apply -f -` if on Powershell.

### Demo
Below is a link showing a demo of the application working:
[DEMO](https://drive.google.com/file/d/1PeIgGxL_HWrR9PTpYD84Okzp3k397Sez/view?usp=sharing)

## Monitoring and Alerting

There are several alerts configured to monitor the health of the cluster:

### GKE Node CPU Threshold alert

**Purpose**: Detect when any GKE node exceeds a CPU threshold, indicating resource pressure or mis-sized workloads.

**Metric used**: `compute.googleapis.com/instance/cpu/utilization`

**Condition**: CPU usage is >80% for 5 minutes

**Filter**: `resource.type = gce_instance` and `metadata.user_labels.goog-k8s-cluster-name = "<CLUSTER NAME>"`

**Alert Json**: [Node CPU Usage Over 80%](./Monitoring%20Policies/Node%20CPU%20Usage%20Over%2080%25.json)

### GKE Node Memory Threshold alert

**Purpose**: Detect when any GKE node exceeds a Memory usage threshold, indicating resource pressure or mis-sized workloads.

**Metric used**: `compute.googleapis.com/instance/memory/balloon/ram_used`

**Condition**: CPU usage is >1.5GB for 5 minutes

**Filter**: `resource.type = gce_instance` and `metadata.user_labels.goog-k8s-cluster-name = "<CLUSTER NAME>"`

**Alert Json**: [Node Memory Usage Over 1.5GB](./Monitoring%20Policies/Node%20Memory%20Usage%20Over%201.5GB.json)

### GKE Failed Deployment alert

**Purpose**: Detect GKE cluster events indicating that a Kubernetes deployment has failed.

**Metric used**: `jsonPayload.involvedObject.kind="Deployment"`

**Condition**:  Matches logs on the below condition
```
(
  jsonPayload.reason="Failed" OR
  jsonPayload.reason="FailedCreate" OR
  jsonPayload.reason="FailedScheduling" OR
  jsonPayload.reason="ProgressDeadlineExceeded" OR
  jsonPayload.reason="DeploymentFailed"
)
```

**Filter**: `resource.type = gce_instance` and `metadata.user_labels.goog-k8s-cluster-name = "<CLUSTER NAME>"`

**Alert Json**: [Failed Deployment - ecp-data-cluster](./Monitoring%20Policies/Failed%20Deployment%20-%20ecp-data-cluster.json)

### Application Error alert
**Purpose**: Detect application error events indicating that a there is an issue with the application running in the cluster.

**Metric used**: `resource.type="k8s_container""`

**Condition**: `severity="ERROR"` and `metadata.user_labels.goog-k8s-cluster-name = "<CLUSTER NAME>"`

**Alert Json**: [Beam Application Errors](./Monitoring%20Policies/Beam%20Application%20Errors.json)


## Security Measures

### IAM
IAM is mostly managed by terraform using the local variables in [constructor.tf](./terraform/constructor.tf), specifically `beam_roles` and `gitlab-runner` for the application and gitlab runner service accounts respectively. These follow the principle of least privilege, ensuring that each service account is granted only the minimum permissions required to perform its intended actions.

If using a service account to deploy the infrastucture via terraform the following roles are required by that service account before deploying the infrastructure, this will need to be done via the CLI or console. 

```
Editor
IAM Policy Admin
Service Account Admin
```
Below is the snippet of terraform that applies the IAM roles on the service principles: 
```terraform
resource "google_project_iam_member" "gitlab_roles" {
  for_each = toset(local.gitrunner-roles)

  project = local.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.gitlab-runner.email}"
}

resource "google_project_iam_member" "beam_roles" {
  for_each = toset(local.beam-roles)

  project = local.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.data-app.email}"
}

```

There are some other roles required which cannot be provisioned by the `google_project_iam_member` resource. These are located in [main.tf](/terraform/main.tf), under the `IAM` comment.

### Encryption

The services used in this example provide encryption at rest and transit by default by GCP. However, if more time was avaiable, I would provision or retrieve an encryption key and encrypt the storage services with a customer managed key.
