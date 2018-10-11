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

///////////////////////////////////////////////////////////////////////////////////////
// Create the resources needed for the Stackdriver Export Sinks
///////////////////////////////////////////////////////////////////////////////////////

// Random string used to create a unique bucket name
resource "random_id" "server" {
  byte_length = 8
}

// Create a Cloud Storage Bucket for long-term storage of logs
// Note: the bucket has force_destroy turned on, so the data will be lost if you run
// terraform destroy
resource "google_storage_bucket" "gcp-log-bucket" {
  name          = "stackdriver-gcp-logging-bucket-${random_id.server.hex}"
  storage_class = "NEARLINE"
  force_destroy = true
}

// Create a BigQuery Dataset for storage of logs
// Note: only the most recent hour's data will be stored based on the table expiration
resource "google_bigquery_dataset" "gcp-bigquery-dataset" {
  dataset_id                  = "gcp_logs_dataset"
  location                    = "US"
  default_table_expiration_ms = 3600000

  labels {
    env = "default"
  }
}

///////////////////////////////////////////////////////////////////////////////////////
// Create the primary cluster for this project.
///////////////////////////////////////////////////////////////////////////////////////

// Create A GKE Cluster to generate some logs
// https://www.terraform.io/docs/providers/google/d/google_container_cluster.html
resource "google_container_cluster" "primary" {
  name               = "stackdriver-logging"
  zone               = "${var.zone}"
  initial_node_count = 2

  node_config {
    oauth_scopes = [
      "https://www.googleapis.com/auth/compute",
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
    ]
  }

  // These local-execs are used to provision the sample service
  provisioner "local-exec" {
    command = "gcloud container clusters get-credentials ${google_container_cluster.primary.name} --zone ${google_container_cluster.primary.zone} --project ${var.project}"
  }

  provisioner "local-exec" {
    command = "kubectl --namespace default run hello-server --image gcr.io/google-samples/hello-app:1.0 --port 8080"
  }

  provisioner "local-exec" {
    command = "kubectl --namespace default expose deployment hello-server --type \"LoadBalancer\" "
  }
}

///////////////////////////////////////////////////////////////////////////////////////
// Configure the stackdriver sinks and necessary roles.
// To enable writing to the various export sinks we must grant additional permissions.
// Refer to the following URL for details:
// https://cloud.google.com/logging/docs/export/configure_export_v2#dest-auth
///////////////////////////////////////////////////////////////////////////////////////


// Create the Stackdriver Export Sink for BigQuery gcp Notifications
resource "google_logging_project_sink" "bigquery-sink" {
  name        = "gcp_bigquery_sink"
  destination = "bigquery.googleapis.com/projects/${var.project}/datasets/${google_bigquery_dataset.gcp-bigquery-dataset.dataset_id}"
  filter      = "resource.type = bigquery.v2.dataset"

  unique_writer_identity = true
}

// Create the Stackdriver Export Sink for gce_firewall_rule gcp Notifications
resource "google_logging_project_sink" "gce_firewall_rule" {
  name        = "gcp_gce_firewall_rule"
  destination = "bigquery.googleapis.com/projects/${var.project}/datasets/${google_bigquery_dataset.gcp-bigquery-dataset.dataset_id}"
  filter      = "resource.type = gce_firewall_rule"

  unique_writer_identity = true
}

// Create the Stackdriver Export Sink for gce_forwarding_rule gcp Notifications
resource "google_logging_project_sink" "gce_forwarding_rule" {
  name        = "gcp_gce_forwarding_rule"
  destination = "bigquery.googleapis.com/projects/${var.project}/datasets/${google_bigquery_dataset.gcp-bigquery-dataset.dataset_id}"
  filter      = "resource.type = gce_forwarding_rule"

  unique_writer_identity = true
}


// Create the Stackdriver Export Sink for gce_network gcp Notifications
resource "google_logging_project_sink" "gce_network" {
  name        = "gcp_gce_network"
  destination = "bigquery.googleapis.com/projects/${var.project}/datasets/${google_bigquery_dataset.gcp-bigquery-dataset.dataset_id}"
  filter      = "resource.type = gce_network"

  unique_writer_identity = true
}

/*
Create the export facility
*/

// Create the Stackdriver Export Sink for audited_resource gcp Notifications
resource "google_logging_project_sink" "audited_resource" {
  name        = "gcp-audited_resource"
  destination = "bigquery.googleapis.com/projects/${var.project}/datasets/${google_bigquery_dataset.gcp-bigquery-dataset.dataset_id}"
  filter      = "resource.type =audited_resource"

  unique_writer_identity = true
}

// Grant the role of BigQuery Data Editor
resource "google_project_iam_binding" "log-writer-bigquery" {
  role = "roles/bigquery.dataEditor"

  members = [
    "${google_logging_project_sink.bigquery-sink.writer_identity}",
  ]
}
