# Kubernetes Provider Configuration for Dev Clusters
provider "kubernetes" {
  alias                  = "dev_eastus"
  host                   = azurerm_kubernetes_cluster.aks_eastus_dev1.kube_config.0.host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.aks_eastus_dev1.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.aks_eastus_dev1.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks_eastus_dev1.kube_config.0.cluster_ca_certificate)
}

provider "kubernetes" {
  alias                  = "dev_westeu"
  host                   = azurerm_kubernetes_cluster.aks_westeu_dev2.kube_config.0.host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.aks_westeu_dev2.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.aks_westeu_dev2.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks_westeu_dev2.kube_config.0.cluster_ca_certificate)
}

# Kubernetes Provider Configuration for Prod Clusters
provider "kubernetes" {
  alias                  = "prod_eastus"
  host                   = azurerm_kubernetes_cluster.aks_eastus_prod1.kube_config.0.host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.aks_eastus_prod1.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.aks_eastus_prod1.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks_eastus_prod1.kube_config.0.cluster_ca_certificate)
}

provider "kubernetes" {
  alias                  = "prod_westeu"
  host                   = azurerm_kubernetes_cluster.aks_westeu_prod2.kube_config.0.host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.aks_westeu_prod2.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.aks_westeu_prod2.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks_westeu_prod2.kube_config.0.cluster_ca_certificate)
}

# Verify AKS clusters are ready before proceeding
resource "null_resource" "verify_aks_clusters" {
  depends_on = [
    azurerm_kubernetes_cluster.aks_eastus_dev1,
    azurerm_kubernetes_cluster.aks_westeu_dev2,
    azurerm_kubernetes_cluster.aks_eastus_prod1,
    azurerm_kubernetes_cluster.aks_westeu_prod2
  ]
  
  provisioner "local-exec" {
    command = <<EOT
      echo "Verifying AKS clusters are ready..."
      
      echo "Checking East US Dev1 AKS cluster..."
      STATUS=$(az aks show --resource-group ${azurerm_kubernetes_cluster.aks_eastus_dev1.resource_group_name} --name ${azurerm_kubernetes_cluster.aks_eastus_dev1.name} --query provisioningState -o tsv)
      echo "East US Dev1 status: $STATUS"
      if [ "$STATUS" != "Succeeded" ]; then
        echo "East US Dev1 AKS cluster is not ready. Status: $STATUS"
        exit 1
      fi
      
      echo "Checking West Europe Dev2 AKS cluster..."
      STATUS=$(az aks show --resource-group ${azurerm_kubernetes_cluster.aks_westeu_dev2.resource_group_name} --name ${azurerm_kubernetes_cluster.aks_westeu_dev2.name} --query provisioningState -o tsv)
      echo "West Europe Dev2 status: $STATUS"
      if [ "$STATUS" != "Succeeded" ]; then
        echo "West Europe Dev2 AKS cluster is not ready. Status: $STATUS"
        exit 1
      fi
      
      echo "Checking East US Prod1 AKS cluster..."
      STATUS=$(az aks show --resource-group ${azurerm_kubernetes_cluster.aks_eastus_prod1.resource_group_name} --name ${azurerm_kubernetes_cluster.aks_eastus_prod1.name} --query provisioningState -o tsv)
      echo "East US Prod1 status: $STATUS"
      if [ "$STATUS" != "Succeeded" ]; then
        echo "East US Prod1 AKS cluster is not ready. Status: $STATUS"
        exit 1
      fi
      
      echo "Checking West Europe Prod2 AKS cluster..."
      STATUS=$(az aks show --resource-group ${azurerm_kubernetes_cluster.aks_westeu_prod2.resource_group_name} --name ${azurerm_kubernetes_cluster.aks_westeu_prod2.name} --query provisioningState -o tsv)
      echo "West Europe Prod2 status: $STATUS"
      if [ "$STATUS" != "Succeeded" ]; then
        echo "West Europe Prod2 AKS cluster is not ready. Status: $STATUS"
        exit 1
      fi
      
      echo "All AKS clusters are ready!"
    EOT
  }
}

# Get Kubernetes credentials for all clusters
resource "null_resource" "get_all_credentials" {
  depends_on = [null_resource.verify_aks_clusters]
  
  provisioner "local-exec" {
    command = <<EOT
      echo "Getting credentials for all AKS clusters..."
      
      az aks get-credentials --resource-group ${azurerm_kubernetes_cluster.aks_eastus_dev1.resource_group_name} --name ${azurerm_kubernetes_cluster.aks_eastus_dev1.name} --overwrite-existing
      az aks get-credentials --resource-group ${azurerm_kubernetes_cluster.aks_westeu_dev2.resource_group_name} --name ${azurerm_kubernetes_cluster.aks_westeu_dev2.name} --overwrite-existing
      az aks get-credentials --resource-group ${azurerm_kubernetes_cluster.aks_eastus_prod1.resource_group_name} --name ${azurerm_kubernetes_cluster.aks_eastus_prod1.name} --overwrite-existing
      az aks get-credentials --resource-group ${azurerm_kubernetes_cluster.aks_westeu_prod2.resource_group_name} --name ${azurerm_kubernetes_cluster.aks_westeu_prod2.name} --overwrite-existing
      
      echo "All credentials obtained!"
    EOT
  }
}

# ConfigMap for Dev East US Nginx configuration
resource "kubernetes_config_map" "dev_nginx_config_eastus" {
  provider = kubernetes.dev_eastus
  depends_on = [null_resource.get_all_credentials]
  
  metadata {
    name = "nginx-config"
    namespace = "default"
  }

  data = {
    "default.conf" = <<-EOT
    server {
      listen 80;
      server_name _;
      
      location / {
        root /usr/share/nginx/html;
        index index.html;
      }
      
      # Handle /dev path prefix for Front Door routing
      location /dev {
        alias /usr/share/nginx/html;
        index index.html;
      }
    }
    EOT
  }
}

# Development App Deployment - East US
resource "kubernetes_deployment" "dev_app_eastus" {
  provider = kubernetes.dev_eastus
  depends_on = [null_resource.get_all_credentials]
  
  metadata {
    name = "dev-demo-app"
    namespace = "default"
    labels = {
      app = "dev-demo"
    }
  }

  spec {
    replicas = 2
    selector {
      match_labels = {
        app = "dev-demo"
      }
    }

    template {
      metadata {
        labels = {
          app = "dev-demo"
        }
      }

      spec {
        container {
          image = "nginx:stable"
          name  = "dev-demo-app"
          
          env {
            name  = "TITLE"
            value = "Development Demo App"
          }

          env {
            name  = "VOTE1VALUE"
            value = "Cats"
          }

          env {
            name  = "VOTE2VALUE"
            value = "Dogs"
          }

          port {
            container_port = 80
          }

          resources {
            limits = {
              cpu    = "250m"
              memory = "256Mi"
            }
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
          }
          
          # Readiness probe with relaxed settings
          readiness_probe {
            http_get {
              path = "/"
              port = 80
            }
            initial_delay_seconds = 30
            period_seconds = 10
            timeout_seconds = 5
            failure_threshold = 6
          }
          
          # Liveness probe with relaxed settings
          liveness_probe {
            http_get {
              path = "/"
              port = 80
            }
            initial_delay_seconds = 60
            period_seconds = 15
            timeout_seconds = 5
            failure_threshold = 6
          }
          
          # Add volume mount for NGINX config
          volume_mount {
            name = "nginx-config"
            mount_path = "/etc/nginx/conf.d"
          }
        }

        # Add volume for NGINX config
        volume {
          name = "nginx-config"
          config_map {
            name = kubernetes_config_map.dev_nginx_config_eastus.metadata[0].name
          }
        }

        # Add tolerations for node not ready conditions
        toleration {
          key = "node.kubernetes.io/not-ready"
          operator = "Exists"
          effect = "NoExecute"
          toleration_seconds = 300
        }
        
        toleration {
          key = "node.kubernetes.io/unreachable"
          operator = "Exists"
          effect = "NoExecute"
          toleration_seconds = 300
        }
      }
    }
  }

  # Add timeouts for deployment
  timeouts {
    create = "15m"
    update = "15m"
    delete = "15m"
  }
}

# Development App Service - East US
resource "kubernetes_service" "dev_service_eastus" {
  provider = kubernetes.dev_eastus
  depends_on = [kubernetes_deployment.dev_app_eastus]
  
  metadata {
    name = "dev-demo-service"
    namespace = "default"
  }
  spec {
    selector = {
      app = "dev-demo"
    }
    port {
      port        = 80
      target_port = 80
    }
    type = "LoadBalancer"
  }
}

# ConfigMap for Dev West Europe Nginx configuration
resource "kubernetes_config_map" "dev_nginx_config_westeu" {
  provider = kubernetes.dev_westeu
  depends_on = [null_resource.get_all_credentials]
  
  metadata {
    name = "nginx-config"
    namespace = "default"
  }

  data = {
    "default.conf" = <<-EOT
    server {
      listen 80;
      server_name _;
      
      location / {
        root /usr/share/nginx/html;
        index index.html;
      }
      
      # Handle /dev path prefix for Front Door routing
      location /dev {
        alias /usr/share/nginx/html;
        index index.html;
      }
    }
    EOT
  }
}

# Development App Deployment - West Europe
resource "kubernetes_deployment" "dev_app_westeu" {
  provider = kubernetes.dev_westeu
  depends_on = [null_resource.get_all_credentials]
  
  metadata {
    name = "dev-demo-app"
    namespace = "default"
    labels = {
      app = "dev-demo"
    }
  }

  spec {
    replicas = 2
    selector {
      match_labels = {
        app = "dev-demo"
      }
    }

    template {
      metadata {
        labels = {
          app = "dev-demo"
        }
      }

      spec {
        container {
          image = "nginx:stable"
          name  = "dev-demo-app"
          
          env {
            name  = "TITLE"
            value = "Development Demo App"
          }

          env {
            name  = "VOTE1VALUE"
            value = "Cats"
          }

          env {
            name  = "VOTE2VALUE"
            value = "Dogs"
          }

          port {
            container_port = 80
          }

          resources {
            limits = {
              cpu    = "250m"
              memory = "256Mi"
            }
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
          }
          
          # Readiness probe with relaxed settings
          readiness_probe {
            http_get {
              path = "/"
              port = 80
            }
            initial_delay_seconds = 30
            period_seconds = 10
            timeout_seconds = 5
            failure_threshold = 6
          }
          
          # Liveness probe with relaxed settings
          liveness_probe {
            http_get {
              path = "/"
              port = 80
            }
            initial_delay_seconds = 60
            period_seconds = 15
            timeout_seconds = 5
            failure_threshold = 6
          }
          
          # Add volume mount for NGINX config
          volume_mount {
            name = "nginx-config"
            mount_path = "/etc/nginx/conf.d"
          }
        }

        # Add volume for NGINX config
        volume {
          name = "nginx-config"
          config_map {
            name = kubernetes_config_map.dev_nginx_config_westeu.metadata[0].name
          }
        }

        # Add tolerations for node not ready conditions
        toleration {
          key = "node.kubernetes.io/not-ready"
          operator = "Exists"
          effect = "NoExecute"
          toleration_seconds = 300
        }
        
        toleration {
          key = "node.kubernetes.io/unreachable"
          operator = "Exists"
          effect = "NoExecute"
          toleration_seconds = 300
        }
      }
    }
  }

  # Add timeouts for deployment
  timeouts {
    create = "15m"
    update = "15m"
    delete = "15m"
  }
}

# Development App Service - West Europe
resource "kubernetes_service" "dev_service_westeu" {
  provider = kubernetes.dev_westeu
  depends_on = [kubernetes_deployment.dev_app_westeu]
  
  metadata {
    name = "dev-demo-service"
    namespace = "default"
  }
  spec {
    selector = {
      app = "dev-demo"
    }
    port {
      port        = 80
      target_port = 80
    }
    type = "LoadBalancer"
  }
}

# ConfigMap for Prod East US Nginx configuration
resource "kubernetes_config_map" "prod_nginx_config_eastus" {
  provider = kubernetes.prod_eastus
  depends_on = [null_resource.get_all_credentials]
  
  metadata {
    name = "nginx-config"
    namespace = "default"
  }

  data = {
    "default.conf" = <<-EOT
    server {
      listen 80;
      server_name _;
      
      location / {
        root /usr/share/nginx/html;
        index index.html;
      }
      
      # Handle /prod path prefix for Front Door routing
      location /prod {
        alias /usr/share/nginx/html;
        index index.html;
      }
    }
    EOT
  }
}

# Production App Deployment - East US
resource "kubernetes_deployment" "prod_app_eastus" {
  provider = kubernetes.prod_eastus
  depends_on = [null_resource.get_all_credentials]
  
  metadata {
    name = "prod-demo-app"
    namespace = "default"
    labels = {
      app = "prod-demo"
    }
  }

  spec {
    replicas = 3
    selector {
      match_labels = {
        app = "prod-demo"
      }
    }

    template {
      metadata {
        labels = {
          app = "prod-demo"
        }
      }

      spec {
        container {
          image = "nginx:stable"
          name  = "prod-demo-app"
          
          env {
            name  = "TITLE"
            value = "Production Demo App"
          }

          env {
            name  = "VOTE1VALUE"
            value = "Tea"
          }

          env {
            name  = "VOTE2VALUE"
            value = "Coffee"
          }

          port {
            container_port = 80
          }

          resources {
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
            requests = {
              cpu    = "250m"
              memory = "256Mi"
            }
          }
          
          # Readiness probe with relaxed settings
          readiness_probe {
            http_get {
              path = "/"
              port = 80
            }
            initial_delay_seconds = 30
            period_seconds = 10
            timeout_seconds = 5
            failure_threshold = 6
          }
          
          # Liveness probe with relaxed settings
          liveness_probe {
            http_get {
              path = "/"
              port = 80
            }
            initial_delay_seconds = 60
            period_seconds = 15
            timeout_seconds = 5
            failure_threshold = 6
          }
          
          # Add volume mount for NGINX config
          volume_mount {
            name = "nginx-config"
            mount_path = "/etc/nginx/conf.d"
          }
        }

        # Add volume for NGINX config
        volume {
          name = "nginx-config"
          config_map {
            name = kubernetes_config_map.prod_nginx_config_eastus.metadata[0].name
          }
        }

        # Add tolerations for node not ready conditions
        toleration {
          key = "node.kubernetes.io/not-ready"
          operator = "Exists"
          effect = "NoExecute"
          toleration_seconds = 300
        }
        
        toleration {
          key = "node.kubernetes.io/unreachable"
          operator = "Exists"
          effect = "NoExecute"
          toleration_seconds = 300
        }
      }
    }
  }

  # Add timeouts for deployment
  timeouts {
    create = "15m"
    update = "15m"
    delete = "15m"
  }
}

# Production App Service - East US
resource "kubernetes_service" "prod_service_eastus" {
  provider = kubernetes.prod_eastus
  depends_on = [kubernetes_deployment.prod_app_eastus]
  
  metadata {
    name = "prod-demo-service"
    namespace = "default"
  }
  spec {
    selector = {
      app = "prod-demo"
    }
    port {
      port        = 80
      target_port = 80
    }
    type = "LoadBalancer"
  }
}

# ConfigMap for Prod West Europe Nginx configuration
resource "kubernetes_config_map" "prod_nginx_config_westeu" {
  provider = kubernetes.prod_westeu
  depends_on = [null_resource.get_all_credentials]
  
  metadata {
    name = "nginx-config"
    namespace = "default"
  }

  data = {
    "default.conf" = <<-EOT
    server {
      listen 80;
      server_name _;
      
      location / {
        root /usr/share/nginx/html;
        index index.html;
      }
      
      # Handle /prod path prefix for Front Door routing
      location /prod {
        alias /usr/share/nginx/html;
        index index.html;
      }
    }
    EOT
  }
}

# Production App Deployment - West Europe
resource "kubernetes_deployment" "prod_app_westeu" {
  provider = kubernetes.prod_westeu
  depends_on = [null_resource.get_all_credentials]
  
  metadata {
    name = "prod-demo-app"
    namespace = "default"
    labels = {
      app = "prod-demo"
    }
  }

  spec {
    replicas = 3
    selector {
      match_labels = {
        app = "prod-demo"
      }
    }

    template {
      metadata {
        labels = {
          app = "prod-demo"
        }
      }

      spec {
        container {
          image = "nginx:stable"
          name  = "prod-demo-app"
          
          env {
            name  = "TITLE"
            value = "Production Demo App"
          }

          env {
            name  = "VOTE1VALUE"
            value = "Tea"
          }

          env {
            name  = "VOTE2VALUE"
            value = "Coffee"
          }

          port {
            container_port = 80
          }

          resources {
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
            requests = {
              cpu    = "250m"
              memory = "256Mi"
            }
          }
          
          # Readiness probe with relaxed settings
          readiness_probe {
            http_get {
              path = "/"
              port = 80
            }
            initial_delay_seconds = 30
            period_seconds = 10
            timeout_seconds = 5
            failure_threshold = 6
          }
          
          # Liveness probe with relaxed settings
          liveness_probe {
            http_get {
              path = "/"
              port = 80
            }
            initial_delay_seconds = 60
            period_seconds = 15
            timeout_seconds = 5
            failure_threshold = 6
          }
          
          # Add volume mount for NGINX config
          volume_mount {
            name = "nginx-config"
            mount_path = "/etc/nginx/conf.d"
          }
        }

        # Add volume for NGINX config
        volume {
          name = "nginx-config"
          config_map {
            name = kubernetes_config_map.prod_nginx_config_westeu.metadata[0].name
          }
        }

        # Add tolerations for node not ready conditions
        toleration {
          key = "node.kubernetes.io/not-ready"
          operator = "Exists"
          effect = "NoExecute"
          toleration_seconds = 300
        }
        
        toleration {
          key = "node.kubernetes.io/unreachable"
          operator = "Exists"
          effect = "NoExecute"
          toleration_seconds = 300
        }
      }
    }
  }

  # Add timeouts for deployment
  timeouts {
    create = "15m"
    update = "15m"
    delete = "15m"
  }
}

# Production App Service - West Europe
resource "kubernetes_service" "prod_service_westeu" {
  provider = kubernetes.prod_westeu
  depends_on = [kubernetes_deployment.prod_app_westeu]
  
  metadata {
    name = "prod-demo-service"
    namespace = "default"
  }
  spec {
    selector = {
      app = "prod-demo"
    }
    port {
      port        = 80
      target_port = 80
    }
    type = "LoadBalancer"
  }
}

# Outputs
output "dev_eastus_service_ip" {
  value = kubernetes_service.dev_service_eastus.status.0.load_balancer.0.ingress.0.ip
  description = "IP address of the Dev East US demo service"
}

output "dev_westeu_service_ip" {
  value = kubernetes_service.dev_service_westeu.status.0.load_balancer.0.ingress.0.ip
  description = "IP address of the Dev West Europe demo service"
}

output "prod_eastus_service_ip" {
  value = kubernetes_service.prod_service_eastus.status.0.load_balancer.0.ingress.0.ip
  description = "IP address of the Prod East US demo service"
}

output "prod_westeu_service_ip" {
  value = kubernetes_service.prod_service_westeu.status.0.load_balancer.0.ingress.0.ip
  description = "IP address of the Prod West Europe demo service"
}