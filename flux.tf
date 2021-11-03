
resource "kubernetes_namespace" "flux_system" {
  depends_on = [
    azurerm_kubernetes_cluster.default
  ]

  metadata {
    name = "flux-system"
  }
}

# Flux

data "http" "flux_components" {
  url = "https://raw.githubusercontent.com/gdud/notejam-k8s-cluster-configuration/main/flux-components.yaml"
}

data "kubectl_file_documents" "flux_components" {
    content = data.http.flux_components.body
}

resource "kubectl_manifest" "flux_components" {
  depends_on = [
    kubernetes_namespace.flux_system
  ]

  for_each  = data.kubectl_file_documents.flux_components.manifests
  yaml_body = each.value
}

data "http" "flux_sync" {
  url = "https://raw.githubusercontent.com/gdud/notejam-k8s-cluster-configuration/main/flux-sync-cluster-configuration.yaml"
}

data "kubectl_file_documents" "flux_sync" {
    content = data.http.flux_sync.body
}

resource "kubectl_manifest" "flux_sync" {
  depends_on = [
    azurerm_kubernetes_cluster.default
  ]

  for_each  = data.kubectl_file_documents.flux_sync.manifests
  yaml_body = each.value
}

# Keys for repos authorization

resource "tls_private_key" "git_credentials_cluster_configuration" {
  algorithm = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_private_key" "git_credentials_apps" {
  algorithm = "ECDSA"
  ecdsa_curve = "P256"
}

locals {
  known_hosts = "github.com ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAq2A7hRGmdnm9tUDbO9IDSwBK6TbQa+PXYPCPy6rbTrTtw7PHkccKrpp0yVhp5HdEIcKr6pLlVDBfOLX9QUsyCOV0wzfjIJNlGEYsdlLJizHhbn2mUjvSAHQqZETYP81eFzLQNnPHt4EVVUh7VfDESU84KezmD5QlWpXLmvU31/yMf+Se8xhHTvKSCZIFImWwoG6mbUoWf9nzpIoaSjB+weqqUUmpaaasXVal72J+UX2B+2RPW3RcT0eOzQgqlJL3RKrTJvdsjE3JEAvGq3lGHSZXy28G3skua2SmVi/w4yCE6gbODqnTWlg7+wC604ydGXA8VJiS5ap43JXiUFFAaQ=="
}

resource "kubernetes_secret" "git_credentials_cluster_configuration" {

  depends_on = [
    kubectl_manifest.flux_components
  ]

  metadata {
    name      = "git-credentials-cluster-configuration"
    namespace = "flux-system"
  }

  data = {
    identity       = tls_private_key.git_credentials_cluster_configuration.private_key_pem
    "identity.pub" = tls_private_key.git_credentials_cluster_configuration.public_key_pem
    known_hosts    = local.known_hosts
  }
}

resource "kubernetes_secret" "git_credentials_apps" {
  metadata {
    name      = "git-credentials-apps"
    namespace = "flux-system"
  }

  data = {
    identity       = tls_private_key.git_credentials_apps.private_key_pem
    "identity.pub" = tls_private_key.git_credentials_apps.public_key_pem
    known_hosts    = local.known_hosts
  }
}

resource "github_repository_deploy_key" "cluster_configuration" {
  title      = "${local.name_prefix}-flux"
  repository = "notejam-k8s-cluster-configuration"
  key        = tls_private_key.git_credentials_cluster_configuration.public_key_openssh
  read_only  = true
}

resource "github_repository_deploy_key" "apps" {
  title      = "${local.name_prefix}-flux"
  repository = "notejam-k8s-apps"
  key        = tls_private_key.git_credentials_apps.public_key_openssh
  read_only  = true
}