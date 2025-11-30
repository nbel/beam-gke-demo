# enable APIs
resource "google_project_service" "services" {
  for_each = toset(local.gcp_services)

  service = each.value

  disable_on_destroy = false
}

data "google_project" "current" {}


#VPC
resource "google_compute_network" "vpc-network" {
  depends_on              = [google_project_service.services]
  project                 = local.project_id
  name                    = "vpc-network"
  auto_create_subnetworks = false

}


resource "google_compute_subnetwork" "gke_subnet" {
  name          = "gke-subnet"
  network       = google_compute_network.vpc-network.id
  region        = local.region
  ip_cidr_range = "10.10.10.0/24" # node IPs

  # secondary range for Pod IPs
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.20.0.0/14"
  }

  # secondary range for Service IPs
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.30.0.0/20"
  }
}

resource "google_service_account" "data-app" {
  account_id   = "gke-data-app-account"
  display_name = "GKE Data Application"
}

resource "google_service_account" "gitlab-runner" {
  account_id   = "gitlab-runner"
  display_name = "Gitlab Runner"
}

# GKE
resource "google_container_cluster" "primary" {
  depends_on               = [google_project_service.services]
  name                     = "gke-ecp-data-cluster"
  location                 = local.region
  initial_node_count       = 1
  remove_default_node_pool = true
  network                  = google_compute_network.vpc-network.id
  subnetwork               = google_compute_subnetwork.gke_subnet.id
  monitoring_service       = "monitoring.googleapis.com/kubernetes"
  logging_service          = "logging.googleapis.com/kubernetes"
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }
  workload_identity_config {
    workload_pool = "${local.project_id}.svc.id.goog"
  }
  deletion_protection = false
  allow_net_admin     = false
  node_config {
    disk_type    = "pd-standard"
    disk_size_gb = 30 
    machine_type = "e2-small"

  }

  cluster_autoscaling {
    enabled = false
   
    resource_limits {
      resource_type = "cpu"
      minimum       = 1
      maximum       = 3
    }
    resource_limits {
      resource_type = "memory"
      minimum       = 1
      maximum       = 3
    }
  }
}

resource "google_container_node_pool" "ne-pool" {
  name       = "ne-pool"
  cluster    = google_container_cluster.primary.id
  node_count = 1
  node_locations = [
    "${local.region}-a",
    "${local.region}-b",
    "${local.region}-c",
  ]
  node_config {
    service_account = google_service_account.data-app.email
    preemptible     = false # spot
    machine_type    = "e2-small"
    disk_type       = "pd-standard" 
    disk_size_gb    = 30            
  }

  autoscaling {
    min_node_count  = 1
    max_node_count  = 2
    location_policy = "BALANCED" # for HA or ANY for cost optimisation 
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}


# storage

resource "google_storage_bucket" "primary" {
  for_each                    = local.buckets
  name                        = each.key
  location                    = local.region
  storage_class               = upper(each.value.class)
  uniform_bucket_level_access = each.value.uniform_bucket_level_access
  force_destroy               = true
}


# BigQuery

resource "google_bigquery_dataset" "ecp" {
  dataset_id                 = "ecp_dataset"
  location                   = local.region
  description                = "Analytics data storage"
  delete_contents_on_destroy = true

  access {
    role          = "roles/bigquery.dataOwner"
    user_by_email = google_service_account.data-app.email
  }
}

resource "google_bigquery_table" "sensor_table" {
  dataset_id          = google_bigquery_dataset.ecp.dataset_id
  table_id            = "sensor_readings"
  deletion_protection = false
  schema = jsonencode([
    {
      name = "sensor_id"
      type = "STRING"
      mode = "REQUIRED"
    },
    {
      name = "temperature"
      type = "FLOAT"
      mode = "NULLABLE"
    },
    {
      name = "humidity"
      type = "FLOAT"
      mode = "NULLABLE"
    },
    {
      name = "timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
    }
  ])
}


# IAM
# allows K8S account to user GCP service account
resource "google_service_account_iam_member" "ksa_impersonation" {
  service_account_id = google_service_account.data-app.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${local.project_id}.svc.id.goog[beam/app-data-sa]"
}

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

resource "google_storage_bucket_iam_member" "beam_bucket_admin" {
  for_each = local.buckets
  bucket   = each.key
  role     = "roles/storage.objectAdmin"
  member   = "serviceAccount:${google_service_account.data-app.email}"
}

# pub/sub
resource "google_pubsub_topic" "ecp-iot" {
  name                       = "ecp-iot"
  message_retention_duration = "604800s" # 7 days

}


resource "google_pubsub_subscription" "pull-iot" {
  name                 = "iot"
  topic                = google_pubsub_topic.ecp-iot.name
  ack_deadline_seconds = 30
}

# container registry
resource "google_artifact_registry_repository" "ecp_images" {
  project       = local.project_id
  location      = local.region
  repository_id = "ecp-registry"
  format        = "DOCKER"
  cleanup_policy_dry_run = false
}
