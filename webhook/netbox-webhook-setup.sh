#!/bin/bash

# Script master para configurar, testar e implantar a API Webhook do NetBox
# Autor: Claude (ajudado por um humano incrível)
# Data: 10 de Maio de 2025

# Definição de cores para saída
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Definir variáveis
DOCKER_USERNAME="lsirqueira"  # Substitua pelo seu nome de usuário no Docker Hub
IMAGE_NAME="netbox-webhook-api"
IMAGE_TAG="latest"
NAMESPACE="default"
WEBHOOK_DOMAIN="webhook.labscale.org"
PROJECT_DIR="webhook"

# Função para exibir mensagens
print_msg() {
  echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"
}

print_success() {
  echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
  echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
  echo -e "${RED}✗ $1${NC}"
}

# Função para verificar se um comando foi bem-sucedido
check_status() {
  if [ $? -eq 0 ]; then
    print_success "$1"
  else
    print_error "$2"
    exit 1
  fi
}

# Limpar ambiente anterior (se existir)
print_msg "Verificando e limpando ambiente anterior..."
if [ -d "$PROJECT_DIR" ]; then
  print_warning "Diretório $PROJECT_DIR já existe. Removendo..."
  rm -rf "$PROJECT_DIR"
fi

# Remover pods e recursos Kubernetes anteriores
print_msg "Removendo recursos Kubernetes anteriores (se existirem)..."
kubectl delete deployment netbox-webhook-api 2>/dev/null || true
kubectl delete service netbox-webhook-api 2>/dev/null || true
kubectl delete ingress netbox-webhook-api 2>/dev/null || true

# Criar estrutura de diretórios
print_msg "Criando estrutura de diretórios..."
mkdir -p "$PROJECT_DIR/k8s"
cd "$PROJECT_DIR"

# Criar app.py
print_msg "Criando aplicação Flask (app.py)..."
cat > app.py << 'EOF'
from flask import Flask, request, jsonify
import logging
import os

app = Flask(__name__)

# Configuração de logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

@app.route('/health', methods=['GET'])
def health_check():
    """Endpoint para healthcheck do Kubernetes"""
    return jsonify({"status": "healthy"}), 200

@app.route('/webhook/netbox', methods=['POST'])
def netbox_webhook():
    """Endpoint para receber webhooks do Netbox"""
    data = request.json
    
    # Registra o conteúdo completo da requisição
    logger.info(f"Webhook recebido do Netbox: {data}")
    
    # Verifica se é uma alteração de interface
    if data.get('model') == 'interface':
        device_name = data.get('data', {}).get('device', {}).get('name')
        interface_name = data.get('data', {}).get('name')
        status = data.get('data', {}).get('enabled')
        
        logger.info(f"Alteração na interface {interface_name} do dispositivo {device_name}. Status: {'ativo' if status else 'inativo'}")
        
        # Aqui você pode adicionar a lógica de processamento para a alteração da interface
        # Por exemplo, chamar uma função que executa alguma ação com base na alteração
        
    return jsonify({"status": "success", "message": "Webhook processado com sucesso"}), 200

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 5000))
    app.run(host='0.0.0.0', port=port, debug=False)
EOF
check_status "Aplicação Flask criada com sucesso" "Erro ao criar aplicação Flask"

# Criar requirements.txt
print_msg "Criando arquivo de dependências (requirements.txt)..."
cat > requirements.txt << 'EOF'
flask==2.0.1
werkzeug==2.0.1
gunicorn==20.1.0
requests==2.28.2
EOF
check_status "Arquivo de dependências criado com sucesso" "Erro ao criar arquivo de dependências"

# Criar Dockerfile
print_msg "Criando Dockerfile..."
cat > Dockerfile << 'EOF'
FROM python:3.9-slim

WORKDIR /app

# Instalar dependências com versões específicas para garantir compatibilidade
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copiar o código da aplicação
COPY app.py .

EXPOSE 5000

CMD ["gunicorn", "--bind", "0.0.0.0:5000", "app:app"]
EOF
check_status "Dockerfile criado com sucesso" "Erro ao criar Dockerfile"

# Criar manifesto de deployment
print_msg "Criando manifesto de deployment (k8s/deployment.yaml)..."
cat > k8s/deployment.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: netbox-webhook-api
  labels:
    app: netbox-webhook-api
spec:
  replicas: 2
  selector:
    matchLabels:
      app: netbox-webhook-api
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    metadata:
      labels:
        app: netbox-webhook-api
    spec:
      containers:
      - name: netbox-webhook-api
        image: ${DOCKER_USERNAME}/${IMAGE_NAME}:${IMAGE_TAG}
        imagePullPolicy: Always
        ports:
        - containerPort: 5000
        resources:
          limits:
            cpu: "500m"
            memory: "512Mi"
          requests:
            cpu: "200m"
            memory: "256Mi"
        livenessProbe:
          httpGet:
            path: /health
            port: 5000
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 5000
          initialDelaySeconds: 5
          periodSeconds: 5
        env:
        - name: PORT
          value: "5000"
EOF
check_status "Manifesto de deployment criado com sucesso" "Erro ao criar manifesto de deployment"

# Criar manifesto de service
print_msg "Criando manifesto de service (k8s/service.yaml)..."
cat > k8s/service.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: netbox-webhook-api
  labels:
    app: netbox-webhook-api
spec:
  type: ClusterIP
  ports:
  - port: 80
    targetPort: 5000
    protocol: TCP
    name: http
  selector:
    app: netbox-webhook-api
EOF
check_status "Manifesto de service criado com sucesso" "Erro ao criar manifesto de service"

# Criar manifesto de ingress
print_msg "Criando manifesto de ingress (k8s/ingress.yaml)..."
cat > k8s/ingress.yaml << EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: netbox-webhook-api
  annotations:
    kubernetes.io/ingress.class: "nginx"
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
spec:
  rules:
  - host: ${WEBHOOK_DOMAIN}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: netbox-webhook-api
            port:
              number: 80
EOF
check_status "Manifesto de ingress criado com sucesso" "Erro ao criar manifesto de ingress"

# Criar script para teste local
print_msg "Criando script para teste local (test-local.sh)..."
cat > test-local.sh << 'EOF'
#!/bin/bash

# Script para testar a aplicação localmente

echo "Iniciando teste local da aplicação..."

# Construir a imagem
docker build -t netbox-webhook-api:local .

# Executar o container
echo "Iniciando container..."
docker run --name webhook-test -d -p 5000:5000 netbox-webhook-api:local

# Aguardar inicialização
echo "Aguardando inicialização (5s)..."
sleep 5

# Testar endpoint de saúde
echo "Testando endpoint de saúde..."
RESPONSE=$(curl -s http://localhost:5000/health)
EXPECTED='{"status":"healthy"}'

if [ "$RESPONSE" == "$EXPECTED" ]; then
    echo "✓ Teste bem-sucedido! A API está funcionando corretamente."
    echo "Resposta: $RESPONSE"
else
    echo "✗ Teste falhou. Resposta recebida:"
    echo "$RESPONSE"
    echo "Verificando logs do container:"
    docker logs webhook-test
fi

# Limpar
echo "Removendo container de teste..."
docker stop webhook-test > /dev/null
docker rm webhook-test > /dev/null

echo "Teste local concluído."
EOF
chmod +x test-local.sh
check_status "Script de teste local criado com sucesso" "Erro ao criar script de teste local"

# Criar script de deploy
print_msg "Criando script de deploy (deploy.sh)..."
cat > deploy.sh << EOF
#!/bin/bash

# Script para construir, enviar e implantar a API

# Definir variáveis
DOCKER_USERNAME="${DOCKER_USERNAME}"
IMAGE_NAME="${IMAGE_NAME}"
IMAGE_TAG="${IMAGE_TAG}"
NAMESPACE="${NAMESPACE}"
FULL_IMAGE_NAME="\${DOCKER_USERNAME}/\${IMAGE_NAME}:\${IMAGE_TAG}"

echo "Construindo imagem Docker..."
docker build -t \${FULL_IMAGE_NAME} .

echo "Enviando imagem para o Docker Hub..."
docker push \${FULL_IMAGE_NAME}

echo "Aplicando manifestos Kubernetes..."
kubectl apply -f k8s/deployment.yaml -n \${NAMESPACE}
kubectl apply -f k8s/service.yaml -n \${NAMESPACE}
kubectl apply -f k8s/ingress.yaml -n \${NAMESPACE}

echo "Aguardando implantação..."
kubectl rollout status deployment netbox-webhook-api -n \${NAMESPACE}

echo "Verificando status dos pods..."
kubectl get pods -l app=netbox-webhook-api -n \${NAMESPACE}

echo ""
echo "Implantação concluída! Para testar o webhook:"
echo "  curl http://${WEBHOOK_DOMAIN}/health"
echo ""
echo "Para verificar os logs:"
echo "  kubectl logs -l app=netbox-webhook-api"
EOF
chmod +x deploy.sh
check_status "Script de deploy criado com sucesso" "Erro ao criar script de deploy"

# Criar script de teste de webhook
print_msg "Criando script para simular webhook (test-webhook.sh)..."
cat > test-webhook.sh << EOF
#!/bin/bash

# Script para simular um webhook do NetBox para testes

# Definir o URL do webhook
WEBHOOK_URL="http://${WEBHOOK_DOMAIN}/webhook/netbox"
# Para testes locais, descomente a linha abaixo
# WEBHOOK_URL="http://localhost:5000/webhook/netbox"

# Criar um payload de exemplo que simula uma alteração de interface no NetBox
read -r -d '' PAYLOAD << 'EEOF'
{
  "event": "updated",
  "timestamp": "2025-05-10 00:00:00",
  "model": "interface",
  "username": "admin",
  "request_id": "12345678-1234-5678-1234-567812345678",
  "data": {
    "id": 123,
    "device": {
      "id": 456,
      "name": "switch-01",
      "display": "switch-01"
    },
    "name": "GigabitEthernet1/0/1",
    "type": {
      "value": "1000base-t",
      "label": "1000BASE-T (1GE)"
    },
    "enabled": true,
    "mgmt_only": false,
    "description": "Uplink to Router",
    "mode": {
      "value": "access",
      "label": "Access"
    }
  },
  "snapshots": {
    "prechange": {
      "enabled": false
    },
    "postchange": {
      "enabled": true
    }
  }
}
EEOF

# Enviar o webhook para a API
echo "Enviando webhook simulado para: \$WEBHOOK_URL"
echo "Payload:"
echo "\$PAYLOAD" | jq . 2>/dev/null || echo "\$PAYLOAD"
echo ""

# Enviar a requisição POST
RESPONSE=\$(curl -s -X POST -H "Content-Type: application/json" -d "\$PAYLOAD" "\$WEBHOOK_URL")
STATUS=\$?

# Verificar se a requisição foi bem-sucedida
if [ \$STATUS -eq 0 ]; then
  echo "Requisição enviada com sucesso!"
  echo "Resposta:"
  echo "\$RESPONSE" | jq . 2>/dev/null || echo "\$RESPONSE"
else
  echo "Erro ao enviar requisição. Código de status: \$STATUS"
fi

# Instruções para verificar os logs
echo ""
echo "Para verificar os logs da API e confirmar que o webhook foi recebido:"
echo "  kubectl logs -l app=netbox-webhook-api --tail=50"
EOF
chmod +x test-webhook.sh
check_status "Script de teste de webhook criado com sucesso" "Erro ao criar script de teste de webhook"

# Criar guia de configuração do NetBox
print_msg "Criando guia de configuração do NetBox..."
cat > netbox-webhook-config.md << EOF
# Configuração do Webhook no NetBox

Para configurar o NetBox para enviar webhooks para nossa API, siga os passos abaixo:

1. Acesse a interface web do NetBox (normalmente em netbox.labscale.org) com privilégios de administrador.

2. Navegue até **Admin > Webhooks > Add webhook**.

3. Configure o webhook com os seguintes parâmetros:
   - **Name**: Interface Change Webhook
   - **Content Types**: dcim > interface
   - **URL**: http://${WEBHOOK_DOMAIN}/webhook/netbox
   - **HTTP Method**: POST
   - **HTTP Content Type**: application/json
   - **Enabled**: Yes
   - **Events**: created, updated, deleted

4. Salve a configuração.

5. Para testar, faça uma alteração em uma interface de um dispositivo no NetBox e verifique os logs da API:
   ```bash
   kubectl logs -l app=netbox-webhook-api
   ```

## Simulação de Webhook para Testes

Você também pode simular um webhook usando o script de teste incluído:

```bash
./test-webhook.sh
```

Este script enviará uma requisição POST simulando uma alteração de interface no NetBox, permitindo testar a API sem precisar fazer alterações reais no NetBox.
EOF
check_status "Guia de configuração do NetBox criado com sucesso" "Erro ao criar guia de configuração do NetBox"

# Voltar para o diretório pai
cd ..

print_success "Configuração concluída! Todos os arquivos foram criados na pasta 'webhook'."
print_msg ""
print_msg "Próximos passos:"
print_msg "1. Teste a aplicação localmente:"
print_msg "   cd webhook && ./test-local.sh"
print_msg ""
print_msg "2. Se o teste local for bem-sucedido, implante no Kubernetes:"
print_msg "   cd webhook && ./deploy.sh"
print_msg ""
print_msg "3. Configure o webhook no NetBox conforme instruções em:"
print_msg "   webhook/netbox-webhook-config.md"
print_msg ""
print_msg "4. Teste a API com o simulador de webhook:"
print_msg "   cd webhook && ./test-webhook.sh"
print_msg ""