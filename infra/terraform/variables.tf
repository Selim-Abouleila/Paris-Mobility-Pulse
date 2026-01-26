variable "project_id" {
  description = "The GCP Project ID"
  type        = string
  default     = "paris-mobility-pulse"
}

variable "region" {
  description = "Default region for resources"
  type        = string
  default     = "europe-west9"
}

variable "zone" {
  description = "Default zone"
  type        = string
  default     = "europe-west9-a"
}

variable "scheduler_location" {
  description = "Location for Cloud Scheduler jobs (regional service)"
  type        = string
  default     = "europe-west1"
}
