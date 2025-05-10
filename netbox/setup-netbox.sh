#!/bin/bash
# Script para criar todos os arquivos do Netbox
# Execute como: chmod +x create-netbox-files.sh && ./create-netbox-files.sh

# Criar diretório para os arquivos se não existir
mkdir -p ~/netbox

# Criar arquivo PV (Persistent Volumes)
cat <<EOF > ~/netbox/pv.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: postgres-pv
spec:
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  hostPath:
    path: /mnt/data/postgres
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: netbox-pv
spec:
  capacity:
    storage: 5Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  hostPath:
    path: /mnt/data/netbox
EOF
echo "✅ Arquivo pv.yaml criado"

# Criar arquivo PVC (Persistent Volume Claims)
cat <<EOF > ~/netbox/pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-data
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  volumeName: postgres-pv
  storageClassName: ""
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: netbox-media
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
  volumeName: netbox-pv
  storageClassName: ""
EOF
echo "✅ Arquivo pvc.yaml criado"

# Criar arquivo de Deployment do PostgreSQL
cat <<EOF > ~/netbox/postgres-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: netbox-postgres
  labels:
    app: netbox-postgres
    app.kubernetes.io/name: netbox
    app.kubernetes.io/component: database
spec:
  replicas: 1
  selector:
    matchLabels:
      app: netbox-postgres
  template:
    metadata:
      labels:
        app: netbox-postgres
        app.kubernetes.io/name: netbox
        app.kubernetes.io/component: database
    spec:
      containers:
      - name: postgres
        image: postgres:15
        env:
        - name: POSTGRES_DB
          value: "netbox"
        - name: POSTGRES_USER
          value: "netbox"
        - name: POSTGRES_PASSWORD
          value: "netbox"
        - name: PGDATA
          value: "/var/lib/postgresql/data/pgdata"
        ports:
        - containerPort: 5432
        volumeMounts:
        - name: postgres-data
          mountPath: /var/lib/postgresql/data
      volumes:
      - name: postgres-data
        persistentVolumeClaim:
          claimName: postgres-data
---
apiVersion: v1
kind: Service
metadata:
  name: netbox-postgres
  labels:
    app.kubernetes.io/name: netbox
    app.kubernetes.io/component: database
spec:
  ports:
  - port: 5432
  selector:
    app: netbox-postgres
EOF
echo "✅ Arquivo postgres-deployment.yaml criado"

# Criar arquivo de Deployment do Redis
cat <<EOF > ~/netbox/redis.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis
  labels:
    app: redis
    app.kubernetes.io/name: netbox
    app.kubernetes.io/component: cache
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
        app.kubernetes.io/name: netbox
        app.kubernetes.io/component: cache
    spec:
      containers:
      - name: redis
        image: redis:7-alpine
        ports:
        - containerPort: 6379
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "256Mi"
            cpu: "250m"
---
apiVersion: v1
kind: Service
metadata:
  name: redis
  labels:
    app.kubernetes.io/name: netbox
    app.kubernetes.io/component: cache
spec:
  selector:
    app: redis
  ports:
    - protocol: TCP
      port: 6379
      targetPort: 6379
EOF
echo "✅ Arquivo redis.yaml criado"

# Criar arquivo de Deployment do Netbox
cat <<EOF > ~/netbox/deployment-netbox.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: netbox-config
  labels:
    app.kubernetes.io/name: netbox
    app.kubernetes.io/component: config
data:
  SUPERUSER_NAME: "admin"
  SUPERUSER_PASSWORD: "admin"
  ALLOWED_HOSTS: "*"
  DB_NAME: "netbox"
  DB_USER: "netbox"
  DB_PASSWORD: "netbox"
  DB_HOST: "netbox-postgres"
  DB_PORT: "5432"
  DB_WAIT_DEBUG: "1"
  SECRET_KEY: "4n9GzjG91fKZqCvY9mXo3TxFu7E3Wjq2FkU6Tj3jL3QoeuUYAMyZKtAZMD9ZK2OG"
  REDIS_HOST: "redis"
  REDIS_PORT: "6379"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: netbox
  labels:
    app: netbox
    app.kubernetes.io/name: netbox
    app.kubernetes.io/component: web
spec:
  replicas: 1
  selector:
    matchLabels:
      app: netbox
  template:
    metadata:
      labels:
        app: netbox
        app.kubernetes.io/name: netbox
        app.kubernetes.io/component: web
    spec:
      containers:
        - name: netbox
          image: netboxcommunity/netbox:latest
          ports:
            - containerPort: 8080
          envFrom:
            - configMapRef:
                name: netbox-config
          volumeMounts:
            - name: netbox-media
              mountPath: /opt/netbox/netbox/media
          livenessProbe:
            httpGet:
              path: /
              port: 8080
            initialDelaySeconds: 60
            periodSeconds: 30
          readinessProbe:
            httpGet:
              path: /
              port: 8080
            initialDelaySeconds: 30
            periodSeconds: 10
      volumes:
        - name: netbox-media
          persistentVolumeClaim:
            claimName: netbox-media
EOF
echo "✅ Arquivo deployment-netbox.yaml criado"

# Criar arquivo de Service do Netbox
cat <<EOF > ~/netbox/service-netbox.yaml
apiVersion: v1
kind: Service
metadata:
  name: netbox-service
  labels:
    app.kubernetes.io/name: netbox
    app.kubernetes.io/component: web
spec:
  selector:
    app: netbox
  ports:
  - protocol: TCP
    port: 80
    targetPort: 8080
  type: ClusterIP
EOF
echo "✅ Arquivo service-netbox.yaml criado"

# Criar arquivo de Ingress para Netbox
cat <<EOF > ~/netbox/ingress-netbox.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: netbox-ingress
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"
    nginx.ingress.kubernetes.io/rewrite-target: /
  labels:
    app.kubernetes.io/name: netbox
    app.kubernetes.io/component: ingress
spec:
  ingressClassName: nginx
  rules:
  - host: netbox.labscale.org
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: netbox-service
            port:
              number: 80
EOF
echo "✅ Arquivo ingress-netbox.yaml criado"

# Criar script de implantação
cat <<EOF > ~/netbox/deploy-netbox.sh
#!/bin/bash
# Script para implantar Netbox no Kubernetes

# Criar diretórios para volumes persistentes
mkdir -p /mnt/data/postgres /mnt/data/netbox
chmod 777 /mnt/data/postgres /mnt/data/netbox

# Aplicar recursos na ordem correta
kubectl apply -f pv.yaml
kubectl apply -f pvc.yaml
kubectl apply -f postgres-deployment.yaml
kubectl apply -f redis.yaml
kubectl apply -f deployment-netbox.yaml
kubectl apply -f service-netbox.yaml
kubectl apply -f ingress-netbox.yaml

echo "⏳ Aguardando Netbox iniciar..."
kubectl wait --for=condition=available deployment/netbox --timeout=300s || true

echo "✅ Netbox implantado!"
echo "🌐 Acesse: http://netbox.labscale.org"
echo "👤 Usuário: admin"
echo "🔑 Senha: admin"
EOF
chmod +x ~/netbox/deploy-netbox.sh
echo "✅ Script deploy-netbox.sh criado e executável"

echo ""
echo "✨ Todos os arquivos foram criados em ~/netbox/"
echo "📋 Para implantar o Netbox, execute: cd ~/netbox && ./deploy-netbox.sh"