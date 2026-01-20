provider "google" {
  project = "paris-mobility-pulse"
}


module "gcloud-export-projects-paris-mobility-pulse-PubSubSubscription" {
  source = "./gcloud-export/projects/paris-mobility-pulse/PubSubSubscription"
}


module "gcloud-export-projects-paris-mobility-pulse-PubSubTopic" {
  source = "./gcloud-export/projects/paris-mobility-pulse/PubSubTopic"
}


module "gcloud-export-paris-mobility-pulse-BigQueryDataset-europe-west9" {
  source = "./gcloud-export/paris-mobility-pulse/BigQueryDataset/europe-west9"
}


module "gcloud-export-projects-paris-mobility-pulse-IAMServiceAccount" {
  source = "./gcloud-export/projects/paris-mobility-pulse/IAMServiceAccount"
}


module "gcloud-export-19684349165-Service" {
  source = "./gcloud-export/19684349165/Service"
}


module "gcloud-export-projects-paris-mobility-pulse-BigQueryTable" {
  source = "./gcloud-export/projects/paris-mobility-pulse/BigQueryTable"
}
