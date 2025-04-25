# kubernetes_config.tf

# This file handles kubernetes configuration and deployments

# Get Kubernetes credentials and configure providers
resource "null_resource" "configure_kubernetes" {
  depends_on = [
    azurerm_kubernetes_cluster.aks_eastus_dev1,
    azurerm_kubernetes_cluster.aks_eastus_prod1,
    azurerm_kubernetes_cluster.aks_westeu_dev2,
    azurerm_kubernetes_cluster.aks_westeu_prod2
  ]
  
  provisioner "local-exec" {
    command = <<EOT
      echo "Getting credentials for all AKS clusters..."
      
      # Get credentials for all clusters
      az aks get-credentials --resource-group ${azurerm_kubernetes_cluster.aks_eastus_dev1.resource_group_name} --name ${azurerm_kubernetes_cluster.aks_eastus_dev1.name} --overwrite-existing
      az aks get-credentials --resource-group ${azurerm_kubernetes_cluster.aks_westeu_dev2.resource_group_name} --name ${azurerm_kubernetes_cluster.aks_westeu_dev2.name} --overwrite-existing
      az aks get-credentials --resource-group ${azurerm_kubernetes_cluster.aks_eastus_prod1.resource_group_name} --name ${azurerm_kubernetes_cluster.aks_eastus_prod1.name} --overwrite-existing
      az aks get-credentials --resource-group ${azurerm_kubernetes_cluster.aks_westeu_prod2.resource_group_name} --name ${azurerm_kubernetes_cluster.aks_westeu_prod2.name} --overwrite-existing
      
      echo "All credentials obtained!"
      
      # Deploy application manifests using kubectl
      # Dev East US
      echo "Deploying to Dev East US cluster..."
      kubectl --context=${azurerm_kubernetes_cluster.aks_eastus_dev1.name} apply -f dev_eastus_manifests.yaml
      
      # Dev West Europe
      echo "Deploying to Dev West Europe cluster..."
      kubectl --context=${azurerm_kubernetes_cluster.aks_westeu_dev2.name} apply -f dev_westeu_manifests.yaml
      
      # Prod East US
      echo "Deploying to Prod East US cluster..."
      kubectl --context=${azurerm_kubernetes_cluster.aks_eastus_prod1.name} apply -f prod_eastus_manifests.yaml
      
      # Prod West Europe
      echo "Deploying to Prod West Europe cluster..."
      kubectl --context=${azurerm_kubernetes_cluster.aks_westeu_prod2.name} apply -f prod_westeu_manifests.yaml
    EOT
  }
}

# Create local manifest files for each cluster
resource "local_file" "dev_eastus_manifests" {
  filename = "dev_eastus_manifests.yaml"
  content = <<-EOT
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dev-demo-app
  namespace: default
  labels:
    app: dev-demo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: dev-demo
  template:
    metadata:
      labels:
        app: dev-demo
    spec:
      containers:
      - name: dev-demo-app
        image: nginx:stable
        ports:
        - containerPort: 80
        env:
        - name: TITLE
          value: "Development Demo App"
        - name: VOTE1VALUE
          value: "Cats"
        - name: VOTE2VALUE
          value: "Dogs"
        resources:
          limits:
            cpu: "250m"
            memory: "256Mi"
          requests:
            cpu: "100m"
            memory: "128Mi"
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 6
        livenessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 60
          periodSeconds: 15
          timeoutSeconds: 5
          failureThreshold: 6
        volumeMounts:
        - name: nginx-config
          mountPath: /etc/nginx/conf.d
      volumes:
      - name: nginx-config
        configMap:
          name: nginx-config
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
data:
  default.conf: |
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
---
apiVersion: v1
kind: Service
metadata:
  name: dev-demo-service
  namespace: default
spec:
  selector:
    app: dev-demo
  ports:
  - port: 80
    targetPort: 80
  type: LoadBalancer
EOT
}

resource "local_file" "dev_westeu_manifests" {
  filename = "dev_westeu_manifests.yaml"
  content = <<-EOT
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dev-demo-app
  namespace: default
  labels:
    app: dev-demo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: dev-demo
  template:
    metadata:
      labels:
        app: dev-demo
    spec:
      containers:
      - name: dev-demo-app
        image: nginx:stable
        ports:
        - containerPort: 80
        env:
        - name: TITLE
          value: "Development Demo App"
        - name: VOTE1VALUE
          value: "Cats"
        - name: VOTE2VALUE
          value: "Dogs"
        resources:
          limits:
            cpu: "250m"
            memory: "256Mi"
          requests:
            cpu: "100m"
            memory: "128Mi"
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 6
        livenessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 60
          periodSeconds: 15
          timeoutSeconds: 5
          failureThreshold: 6
        volumeMounts:
        - name: nginx-config
          mountPath: /etc/nginx/conf.d
      volumes:
      - name: nginx-config
        configMap:
          name: nginx-config
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
data:
  default.conf: |
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
---
apiVersion: v1
kind: Service
metadata:
  name: dev-demo-service
  namespace: default
spec:
  selector:
    app: dev-demo
  ports:
  - port: 80
    targetPort: 80
  type: LoadBalancer
EOT
}

resource "local_file" "prod_eastus_manifests" {
  filename = "prod_eastus_manifests.yaml"
  content = <<-EOT
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prod-demo-app
  namespace: default
  labels:
    app: prod-demo
spec:
  replicas: 3
  selector:
    matchLabels:
      app: prod-demo
  template:
    metadata:
      labels:
        app: prod-demo
    spec:
      containers:
      - name: prod-demo-app
        image: nginx:stable
        ports:
        - containerPort: 80
        env:
        - name: TITLE
          value: "Production Demo App"
        - name: VOTE1VALUE
          value: "Tea"
        - name: VOTE2VALUE
          value: "Coffee"
        resources:
          limits:
            cpu: "500m"
            memory: "512Mi"
          requests:
            cpu: "250m"
            memory: "256Mi"
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 6
        livenessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 60
          periodSeconds: 15
          timeoutSeconds: 5
          failureThreshold: 6
        volumeMounts:
        - name: nginx-config
          mountPath: /etc/nginx/conf.d
      volumes:
      - name: nginx-config
        configMap:
          name: nginx-config
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
data:
  default.conf: |
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
---
apiVersion: v1
kind: Service
metadata:
  name: prod-demo-service
  namespace: default
spec:
  selector:
    app: prod-demo
  ports:
  - port: 80
    targetPort: 80
  type: LoadBalancer
EOT
}

resource "local_file" "prod_westeu_manifests" {
  filename = "prod_westeu_manifests.yaml"
  content = <<-EOT
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prod-demo-app
  namespace: default
  labels:
    app: prod-demo
spec:
  replicas: 3
  selector:
    matchLabels:
      app: prod-demo
  template:
    metadata:
      labels:
        app: prod-demo
    spec:
      containers:
      - name: prod-demo-app
        image: nginx:stable
        ports:
        - containerPort: 80
        env:
        - name: TITLE
          value: "Production Demo App"
        - name: VOTE1VALUE
          value: "Tea"
        - name: VOTE2VALUE
          value: "Coffee"
        resources:
          limits:
            cpu: "500m"
            memory: "512Mi"
          requests:
            cpu: "250m"
            memory: "256Mi"
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 6
        livenessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 60
          periodSeconds: 15
          timeoutSeconds: 5
          failureThreshold: 6
        volumeMounts:
        - name: nginx-config
          mountPath: /etc/nginx/conf.d
      volumes:
      - name: nginx-config
        configMap:
          name: nginx-config
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
data:
  default.conf: |
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
---
apiVersion: v1
kind: Service
metadata:
  name: prod-demo-service
  namespace: default
spec:
  selector:
    app: prod-demo
  ports:
  - port: 80
    targetPort: 80
  type: LoadBalancer
EOT
}