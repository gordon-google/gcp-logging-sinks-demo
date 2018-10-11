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

//TODO: 

# GCE Health Check
# GCE Instance Group Manager
# GCE Instance Template
# GCE Project
# GCE Reserved Address
# GCE Route
# GCE Subnetwork
# GCE Target Pool
# GCS Bucket
# GKE Cluster Operations
# GKE Container
# Google Project
# Kubernetes Cluster
# Logging export sink
# Service Account

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


// Create the Stackdriver Export Sink for BigQuery Audit Table CRUD type Notifications
resource "google_logging_project_sink" "bigquery-sink" {
  name        = "gcp_bigquery_sink"
  destination = "bigquery.googleapis.com/projects/${var.project}/datasets/${google_bigquery_dataset.gcp-bigquery-dataset.dataset_id}"
  filter      = "resource.type = bigquery_resource protoPayload.methodName != tabledataservice.list protoPayload.methodName !=jobservice.jobcompleted protoPayload.methodName!= jobservice.getqueryresults"

  unique_writer_identity = true
}

// Create the Stackdriver Export Sink for gce_firewall_rule Notifications
resource "google_logging_project_sink" "gce_firewall_rule" {
  name        = "gcp_gce_firewall_rule"
  destination = "bigquery.googleapis.com/projects/${var.project}/datasets/${google_bigquery_dataset.gcp-bigquery-dataset.dataset_id}"
  filter      = "resource.type = gce_firewall_rule"

  unique_writer_identity = true
}

// Create the Stackdriver Export Sink for gce_forwarding_rule Notifications
resource "google_logging_project_sink" "gce_forwarding_rule" {
  name        = "gcp_gce_forwarding_rule"
  destination = "bigquery.googleapis.com/projects/${var.project}/datasets/${google_bigquery_dataset.gcp-bigquery-dataset.dataset_id}"
  filter      = "resource.type = gce_forwarding_rule"

  unique_writer_identity = true
}


// Create the Stackdriver Export Sink for gce_network Notifications
resource "google_logging_project_sink" "gce_network" {
  name        = "gcp_gce_network"
  destination = "bigquery.googleapis.com/projects/${var.project}/datasets/${google_bigquery_dataset.gcp-bigquery-dataset.dataset_id}"
  filter      = "resource.type = gce_network"

  unique_writer_identity = true
}

// Create the Stackdriver Export Sink for gce_instance Notifications
resource "google_logging_project_sink" "gce_instance" {
  name        = "gcp_gce_instance"
  destination = "bigquery.googleapis.com/projects/${var.project}/datasets/${google_bigquery_dataset.gcp-bigquery-dataset.dataset_id}"
  # filter      = "resource.type = gce_instance resource.type = gce_instance jsonPayload._CMDLINE!=""/home/kubernetes/bin/kubelet --v=2 --max-pods=110 --kube-reserved=cpu=60m,memory=960Mi --allow-privileged=true --cgroup-root=/ --cloud-provider=gce --cluster-dns=10.55.240.10 --cluster-domain=cluster.local --pod-manifest-path=/etc/kubernetes/manifests --experimental-mounter-path=/home/kubernetes/containerized_mounter/mounter --experimental-check-node-capabilities-before-mount=true --cert-dir=/var/lib/kubelet/pki/ --enable-debugging-handlers=true --bootstrap-kubeconfig=/var/lib/kubelet/bootstrap-kubeconfig --kubeconfig=/var/lib/kubelet/kubeconfig --anonymous-auth=false --authorization-mode=Webhook --client-ca-file=/etc/srv/kubernetes/pki/ca-certificates.crt --cni-bin-dir=/home/kubernetes/bin --network-plugin=kubenet --volume-plugin-dir=/home/kubernetes/flexvolume --node-labels=beta.kubernetes.io/fluentd-ds-ready=true,cloud.google.com/gke-nodepool=default-pool --eviction-hard=memory.available<100Mi,nodefs.available<10%,nodefs.inodesFree<5% --feature-gates=ExperimentalCriticalPodAnnotation=true"" jsonPayload._CMDLINE!=""/usr/bin/dockerd --registry-mirror=https://mirror.gcr.io --host=fd:// -p /var/run/docker.pid --iptables=false --ip-masq=false --log-level=warn --bip=169.254.123.1/24 --registry-mirror=https://mirror.gcr.io --log-driver=json-file --log-opt=max-size=10m --log-opt=max-file=5 --live-restore=false --insecure-registry 10.0.0.0/8"
  filter      = "resource.type = gce_instance"
  unique_writer_identity = true
}

// Create the Stackdriver Export Sink for gce_instanc Notifications
resource "google_logging_project_sink" "gce_health_check" {
  name        = "gcp_gce_health_check"
  destination = "bigquery.googleapis.com/projects/${var.project}/datasets/${google_bigquery_dataset.gcp-bigquery-dataset.dataset_id}"
  filter      = "resource.type = gce_health_check"

  unique_writer_identity = true
}




/*
Create the export facilities
*/

// Create the Stackdriver Export Sink for audited_resource Notifications
resource "google_logging_project_sink" "audited_resource" {
  name        = "gcp-audited_resource"
  destination = "bigquery.googleapis.com/projects/${var.project}/datasets/${google_bigquery_dataset.gcp-bigquery-dataset.dataset_id}"
  filter      = "resource.type =audited_resource"

  unique_writer_identity = true
}

// Grant BigQuery Data Editor role to exports
resource "google_project_iam_binding" "log-writer-bigquery" {
  role = "roles/bigquery.dataEditor"

  members = [
    "${google_logging_project_sink.bigquery-sink.writer_identity}",
  ]
}

resource "google_project_iam_binding" "log-gce_firewall_rule" {
  role = "roles/bigquery.dataEditor"

  members = [
    "${google_logging_project_sink.gce_firewall_rule.writer_identity}",
  ]
}

resource "google_project_iam_binding" "log-audited_resource" {
  role = "roles/bigquery.dataEditor"

  members = [
    "${google_logging_project_sink.audited_resource.writer_identity}",
  ]
}

resource "google_project_iam_binding" "gce_forwarding_rule" {
  role = "roles/bigquery.dataEditor"

  members = [
    "${google_logging_project_sink.gce_forwarding_rule.writer_identity}",
  ]
}


resource "google_project_iam_binding" "gce_network" {
  role = "roles/bigquery.dataEditor"

  members = [
    "${google_logging_project_sink.gce_network.writer_identity}",
  ]
}

resource "google_project_iam_binding" "gce_instance" {
  role = "roles/bigquery.dataEditor"

  members = [
    "${google_logging_project_sink.gce_instance.writer_identity}",
  ]
}

resource "google_project_iam_binding" "gce_health_check" {
  role = "roles/bigquery.dataEditor"

  members = [
    "${google_logging_project_sink.gce_health_check.writer_identity}",
  ]
}
