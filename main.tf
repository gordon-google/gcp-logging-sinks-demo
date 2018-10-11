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
//filter out GKE KubeLet heathcheck/heartbeat stuff

//add the following:
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
  default_table_expiration_ms = 86400000 # set to 24 hours, adjust to match your policy/requirements

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

// Create the Stackdriver Export Sink for gce_instance_group_manager Notifications
resource "google_logging_project_sink" "gce_instance_group_manager" {
  name        = "gcp_gce_instance_group_manager"
  destination = "bigquery.googleapis.com/projects/${var.project}/datasets/${google_bigquery_dataset.gcp-bigquery-dataset.dataset_id}"
  filter      = "resource.type = gce_instance_group_manager"
  unique_writer_identity = true
}

// Create the Stackdriver Export Sink for gce_instance_template Notifications
resource "google_logging_project_sink" "gce_instance_template" {
  name        = "gcp_gce_gce_instance_template"
  destination = "bigquery.googleapis.com/projects/${var.project}/datasets/${google_bigquery_dataset.gcp-bigquery-dataset.dataset_id}"
  filter      = "resource.type = gce_instance_template"
  unique_writer_identity = true
}

// Create the Stackdriver Export Sink for gce_health_check Notifications
resource "google_logging_project_sink" "gce_health_check" {
  name        = "gcp_gce_health_check"
  destination = "bigquery.googleapis.com/projects/${var.project}/datasets/${google_bigquery_dataset.gcp-bigquery-dataset.dataset_id}"
  filter      = "resource.type = gce_health_check"

  unique_writer_identity = true
}

// Create the Stackdriver Export Sink for gce_project Notifications
resource "google_logging_project_sink" "gce_project" {
  name        = "gcp_gce_project"
  destination = "bigquery.googleapis.com/projects/${var.project}/datasets/${google_bigquery_dataset.gcp-bigquery-dataset.dataset_id}"
  filter      = "resource.type = gce_project"

  unique_writer_identity = true
}

// Create the Stackdriver Export Sink for gce_reserved_address Notifications
resource "google_logging_project_sink" "gce_reserved_address" {
  name        = "gcp_gce_reserved_address"
  destination = "bigquery.googleapis.com/projects/${var.project}/datasets/${google_bigquery_dataset.gcp-bigquery-dataset.dataset_id}"
  filter      = "resource.type = gce_reserved_address"

  unique_writer_identity = true
}


// Create the Stackdriver Export Sink for gce_route Notifications
resource "google_logging_project_sink" "gce_route" {
  name        = "gcp_gce_route"
  destination = "bigquery.googleapis.com/projects/${var.project}/datasets/${google_bigquery_dataset.gcp-bigquery-dataset.dataset_id}"
  filter      = "resource.type = gce_route"

  unique_writer_identity = true
}

// Create the Stackdriver Export Sink for gce_subnetwork Notifications
resource "google_logging_project_sink" "gce_subnetwork" {
  name        = "gcp_gce_subnetwork"
  destination = "bigquery.googleapis.com/projects/${var.project}/datasets/${google_bigquery_dataset.gcp-bigquery-dataset.dataset_id}"
  filter      = "resource.type = gce_subnetwork"

  unique_writer_identity = true
}

// Create the Stackdriver Export Sink for gce_target_pool Notifications
resource "google_logging_project_sink" "gce_target_pool" {
  name        = "gcp_gce_target_pool"
  destination = "bigquery.googleapis.com/projects/${var.project}/datasets/${google_bigquery_dataset.gcp-bigquery-dataset.dataset_id}"
  filter      = "resource.type = gce_target_pool"

  unique_writer_identity = true
}


// Create the Stackdriver Export Sink for gcs_bucket Notifications
resource "google_logging_project_sink" "gcs_bucket" {
  name        = "gcp_gcs_bucket"
  destination = "bigquery.googleapis.com/projects/${var.project}/datasets/${google_bigquery_dataset.gcp-bigquery-dataset.dataset_id}"
  filter      = "resource.type = gcs_bucket"

  unique_writer_identity = true
}


// Create the Stackdriver Export Sink for gke_cluster Notifications
resource "google_logging_project_sink" "gke_cluster" {
  name        = "gcp_gke_cluster"
  destination = "bigquery.googleapis.com/projects/${var.project}/datasets/${google_bigquery_dataset.gcp-bigquery-dataset.dataset_id}"
  filter      = "resource.type = gke_cluster"

  unique_writer_identity = true
}

// Create the Stackdriver Export Sink for container Notifications
resource "google_logging_project_sink" "container" {
  name        = "gcp_container"
  destination = "bigquery.googleapis.com/projects/${var.project}/datasets/${google_bigquery_dataset.gcp-bigquery-dataset.dataset_id}"
  filter      = "resource.type = container"

  unique_writer_identity = true
}

// Create the Stackdriver Export Sink for GCP project Notifications
resource "google_logging_project_sink" "project" {
  name        = "gcp_project"
  destination = "bigquery.googleapis.com/projects/${var.project}/datasets/${google_bigquery_dataset.gcp-bigquery-dataset.dataset_id}"
  filter      = "resource.type = project"

  unique_writer_identity = true
}

// Create the Stackdriver Export Sink for k8s_cluster Notifications
resource "google_logging_project_sink" "k8s_cluster" {
  name        = "gcp_k8s_cluster"
  destination = "bigquery.googleapis.com/projects/${var.project}/datasets/${google_bigquery_dataset.gcp-bigquery-dataset.dataset_id}"
  filter      = "resource.type = k8s_cluster"

  unique_writer_identity = true
}

// Create the Stackdriver Export Sink for k8s_cluster Notifications
resource "google_logging_project_sink" "logging_sink" {
  name        = "gcp_logging_sink"
  destination = "bigquery.googleapis.com/projects/${var.project}/datasets/${google_bigquery_dataset.gcp-bigquery-dataset.dataset_id}"
  filter      = "resource.type = logging_sink"

  unique_writer_identity = true
}


// Create the Stackdriver Export Sink for k8s_cluster Notifications
resource "google_logging_project_sink" "service_account" {
  name        = "gcp_service_account"
  destination = "bigquery.googleapis.com/projects/${var.project}/datasets/${google_bigquery_dataset.gcp-bigquery-dataset.dataset_id}"
  filter      = "resource.type = service_account"

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

resource "google_project_iam_binding" "gce_instance_group_manager" {
  role = "roles/bigquery.dataEditor"

  members = [
    "${google_logging_project_sink.gce_instance_group_manager.writer_identity}",
  ]
}

resource "google_project_iam_binding" "gce_instance_template" {
  role = "roles/bigquery.dataEditor"

  members = [
    "${google_logging_project_sink.gce_instance_template.writer_identity}",
  ]
}

resource "google_project_iam_binding" "gce_health_check" {
  role = "roles/bigquery.dataEditor"

  members = [
    "${google_logging_project_sink.gce_health_check.writer_identity}",
  ]
}

resource "google_project_iam_binding" "gce_project" {
  role = "roles/bigquery.dataEditor"

  members = [
    "${google_logging_project_sink.gce_project.writer_identity}",
  ]
}

resource "google_project_iam_binding" "gce_reserved_address" {
  role = "roles/bigquery.dataEditor"

  members = [
    "${google_logging_project_sink.gce_reserved_address.writer_identity}",
  ]
}

resource "google_project_iam_binding" "gce_route" {
  role = "roles/bigquery.dataEditor"

  members = [
    "${google_logging_project_sink.gce_route.writer_identity}",
  ]
}

resource "google_project_iam_binding" "gce_subnetwork" {
  role = "roles/bigquery.dataEditor"

  members = [
    "${google_logging_project_sink.gce_subnetwork.writer_identity}",
  ]
}

resource "google_project_iam_binding" "gce_target_pool" {
  role = "roles/bigquery.dataEditor"

  members = [
    "${google_logging_project_sink.gce_target_pool.writer_identity}",
  ]
}

resource "google_project_iam_binding" "gcs_bucket" {
  role = "roles/bigquery.dataEditor"

  members = [
    "${google_logging_project_sink.gcs_bucket.writer_identity}",
  ]
}

resource "google_project_iam_binding" "gke_cluster" {
  role = "roles/bigquery.dataEditor"

  members = [
    "${google_logging_project_sink.gke_cluster.writer_identity}",
  ]
}

resource "google_project_iam_binding" "container" {
  role = "roles/bigquery.dataEditor"

  members = [
    "${google_logging_project_sink.container.writer_identity}",
  ]
}

resource "google_project_iam_binding" "project" {
  role = "roles/bigquery.dataEditor"

  members = [
    "${google_logging_project_sink.project.writer_identity}",
  ]
}

resource "google_project_iam_binding" "k8s_cluster" {
  role = "roles/bigquery.dataEditor"

  members = [
    "${google_logging_project_sink.k8s_cluster.writer_identity}",
  ]
}

resource "google_project_iam_binding" "logging_sink" {
  role = "roles/bigquery.dataEditor"

  members = [
    "${google_logging_project_sink.logging_sink.writer_identity}",
  ]
}

resource "google_project_iam_binding" "service_account" {
  role = "roles/bigquery.dataEditor"

  members = [
    "${google_logging_project_sink.service_account.writer_identity}",
  ]
}
