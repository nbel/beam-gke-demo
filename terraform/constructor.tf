locals {
  project_id  = "lloyds-assessment-479721"
  region      = "europe-north2"
  credentials = "../.secrets/lloyds-assessment-479721-7c2d15ca36df.json"
  gcp_services = [
    "compute.googleapis.com",
    "container.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "artifactregistry.googleapis.com",
    "dataflow.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "secretmanager.googleapis.com"
  ]

  beam-roles = [
    "roles/pubsub.subscriber",
    "roles/bigquery.dataEditor",
    "roles/storage.objectAdmin",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/artifactregistry.reader",
    "roles/bigquery.jobUser",
    "roles/secretmanager.secretAccessor"
  ]
  gitrunner-roles = [
    "roles/artifactregistry.writer",
    "roles/container.developer"
  ]
  buckets = {
    epc_raw_78904321 = {
      class                       = "Standard"
      uniform_bucket_level_access = true
    }
  }
}