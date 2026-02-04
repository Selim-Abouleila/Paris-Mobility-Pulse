resource "google_artifact_registry_repository" "cloud_run_source_deploy" {
  description = "Cloud Run Source Deployments"
  format      = "DOCKER"

  labels = {
    managed-by-cnrm = "true"
  }

  location      = "europe-west9"
  mode          = "STANDARD_REPOSITORY"
  
  repository_id = "cloud-run-source-deploy"
}
# terraform import google_artifact_registry_repository.cloud_run_source_deploy projects/paris-mobility-pulse/locations/europe-west9/repositories/cloud-run-source-deploy
