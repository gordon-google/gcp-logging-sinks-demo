/*
Copyright 2018 Google LLC

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    https://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

/*
Required Variables
These must be provided at runtime.
*/

variable "zone" {
  description = "The zone in which to create the Kubernetes cluster. Must match the region"
  type        = "string"
  default     = "us-west1-a"
}

variable "project" {
  description = "The name of the project."
  type        = "string"
  default     = "ace-tomato-218918"
}

variable "dataset" {
  description = "A name for the GCP BigQuery Dataset"
  type        = "string"
  default     = "gcp_logs"
}

variable "location" {
  description = "The location for the GCP BigQuery dataset"
  type        = "string"
  default     = "US"
}
