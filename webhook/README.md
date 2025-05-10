# API para Webhooks do NetBox com Kubernetes

Esta solução implementa uma API Flask para processar webhooks enviados pelo NetBox quando interfaces de dispositivos são modificadas. A API é implantada em Kubernetes e pode ser facilmente configurada e testada.

## Visão Geral

Quando uma interface de dispositivo é modificada no NetBox, um webhook é enviado para a API, que processa as informações e pode executar ações com base nessas alterações.

## Requisitos

- Docker
- Kubernetes (cluster funcional)
- kubectl configurado
- Acesso ao Docker Hub
- NetBox operacional

## Implantação Rápida

1. **Baixe o script de setup**:
   Salve o arquivo `netbox-webhook-setup.sh` em seu sistema.

2. **Torne o script executável**:
   ```bash
   chmod +x netbox-webhook-setup.sh
   ```

3. **Execute o script**:
   ```bash
   ./netbox-webhook-setup.sh
   ```

4. **Teste a aplicação localmente**:
   ```bash
   cd webhook
   ./test-local.sh
   ```

5. **Implante no Kubernetes**:
   ```bash
   cd webhook
   ./deploy.sh
   ```

6. **Configure o NetBox**:
   Siga as instruções em `webhook/netbox-webhook-config.md`

7. **Teste a API**:
   ```bash
   cd webhook
   ./test-webhook.sh
   ```

## Estrutura da Solução

O script `netbox-webhook-setup.sh` cria a seguinte estrutura de arquivos:

```
webhook/
├── app.py                  # Aplicação Flask
├── requirements.txt        # Dependências
├── Dockerfile              # Para construir a imagem
├── deploy.sh               # Script de implantação
├── test-local.sh           # Script para teste local
├── test-webhook.sh         # Script para simular webhooks
├── netbox-webhook-config.md # Guia de configuração do NetBox
└── k8s/                    # Diretório para manifestos Kubernetes
    ├── deployment.yaml     # Manifesto do Deployment
    ├── service.yaml        # Manifesto do Service
    └── ingress.yaml        # Manifesto do Ingress
```

## Componentes da Solução

### Aplicação Flask (app.py)

A aplicação Flask fornece dois endpoints:
- `/health`: Endpoint para healthchecks do Kubernetes
- `/webhook/netbox`: Endpoint para receber webhooks do NetBox

### Manifesto Kubernetes (k8s/*.yaml)

Os manifestos Kubernetes incluem:
- **Deployment**: Define como a aplicação é executada
- **Service**: Expõe a aplicação internamente no cluster
- **Ingress**: Configura o acesso externo à aplicação

### Scripts de Teste e Implantação

- **test-local.sh**: Testa a aplicação localmente antes da implantação
- **deploy.sh**: Constrói, envia e implanta a aplicação
- **test-webhook.sh**: Simula um webhook para testar a funcionalidade

## Personalização

### Para alterar o nome de usuário do Docker Hub

Edite a variável `DOCKER_USERNAME` no início do script `netbox-webhook-setup.sh`.

### Para alterar o domínio do webhook

Edite a variável `WEBHOOK_DOMAIN` no início do script `netbox-webhook-setup.sh`.

### Para expandir a funcionalidade da API

Modifique a função `netbox_webhook()` em `app.py` para implementar lógica adicional.

## Solução de Problemas

### Verificando logs

```bash
kubectl logs -l app=netbox-webhook-api
```

### Testando o endpoint de saúde

```bash
curl http://webhook.labscale.org/health
```

### Reiniciando o deployment

```bash
kubectl rollout restart deployment netbox-webhook-api
```

## Melhorias Futuras

- Adicionar autenticação ao endpoint de webhook
- Implementar tratamento específico para diferentes tipos de eventos
- Adicionar monitoramento com Prometheus
- Configurar alerts para falhas

## Contato e Suporte

Para suporte ou sugestões, entre em contato com a equipe de DevOps.