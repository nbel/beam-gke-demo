terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
  }
  backend "local" {
    path = "state/terraform.tfstate"
  }
}

terraform {

}
provider "google" {
  project     = local.project_id
  region      = local.region
  credentials = file(local.credentials)
}