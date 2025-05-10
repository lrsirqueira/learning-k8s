#!/bin/bash

# Script avançado para testar o webhook do NetBox
# Autor: Claude
# Data: 10 de Maio de 2025

# Definição de cores para saída
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Definir variáveis padrão
WEBHOOK_URL="http://webhook.labscale.org/webhook/netbox"
LOCAL_TEST=false
VERBOSE=false
EVENT_TYPE="updated"
INTERFACE_ENABLED=true
DEVICE_NAME="switch-01"
INTERFACE_NAME="GigabitEthernet1/0/1"
DESCRIPTION="Uplink to Router"

# Função de exibição de ajuda
show_help() {
    echo "Uso: $0 [opções]"
    echo ""
    echo "Opções:"
    echo "  -h, --help                 Exibe esta mensagem de ajuda"
    echo "  -l, --local                Testa localmente (localhost:5000 em vez de webhook.labscale.org)"
    echo "  -v, --verbose              Modo detalhado (exibe mais informações)"
    echo "  -e, --event TYPE           Tipo de evento (created, updated, deleted) [padrão: updated]"
    echo "  -s, --status STATUS        Status da interface (true=ativa, false=inativa) [padrão: true]"
    echo "  -d, --device NAME          Nome do dispositivo [padrão: switch-01]"
    echo "  -i, --interface NAME       Nome da interface [padrão: GigabitEthernet1/0/1]"
    echo "  -D, --description TEXT     Descrição da interface [padrão: Uplink to Router]"
    echo ""
    echo "Exemplos:"
    echo "  $0 --local                                  # Testa localmente"
    echo "  $0 --event created --device router-01       # Simula criação de interface"
    echo "  $0 --event deleted --interface eth0         # Simula exclusão de interface"
    echo "  $0 --status false                           # Simula desativação de interface"
}

# Analisar argumentos de linha de comando
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -h|--help)
            show_help
            exit 0
            ;;
        -l|--local)
            LOCAL_TEST=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -e|--event)
            EVENT_TYPE="$2"
            shift 2
            ;;
        -s|--status)
            INTERFACE_ENABLED="$2"
            shift 2
            ;;
        -d|--device)
            DEVICE_NAME="$2"
            shift 2
            ;;
        -i|--interface)
            INTERFACE_NAME="$2"
            shift 2
            ;;
        -D|--description)
            DESCRIPTION="$2"
            shift 2
            ;;
        *)
            echo -e "${RED}Opção desconhecida: $1${NC}"
            show_help
            exit 1
            ;;
    esac
done

# Definir o URL do webhook baseado na flag de teste local
if [ "$LOCAL_TEST" = true ]; then
    WEBHOOK_URL="http://localhost:5000/webhook/netbox"
    echo -e "${YELLOW}Modo de teste local ativado: usando $WEBHOOK_URL${NC}"
fi

# Validar tipo de evento
if [[ ! "$EVENT_TYPE" =~ ^(created|updated|deleted)$ ]]; then
    echo -e "${RED}Erro: Tipo de evento inválido. Use created, updated ou deleted.${NC}"
    exit 1
fi

# Validar status
if [[ ! "$INTERFACE_ENABLED" =~ ^(true|false)$ ]]; then
    echo -e "${RED}Erro: Status inválido. Use true ou false.${NC}"
    exit 1
fi

# Função para exibir mensagens no modo detalhado
log_verbose() {
    if [ "$VERBOSE" = true ]; then
        echo -e "${BLUE}[INFO]${NC} $1"
    fi
}

# Criar um payload de exemplo que simula uma alteração de interface no NetBox
log_verbose "Gerando payload para o webhook..."

# Gerar valores adicionais baseados no tipo de evento
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
REQUEST_ID=$(cat /proc/sys/kernel/random/uuid)
INTERFACE_ID=$((1000 + RANDOM % 9000))
DEVICE_ID=$((1000 + RANDOM % 9000))

# Criar snapshot baseado no tipo de evento
if [ "$EVENT_TYPE" = "created" ]; then
    SNAPSHOTS='"snapshots": { "prechange": null, "postchange": { "enabled": '$INTERFACE_ENABLED' } }'
elif [ "$EVENT_TYPE" = "deleted" ]; then
    SNAPSHOTS='"snapshots": { "prechange": { "enabled": '$INTERFACE_ENABLED' }, "postchange": null }'
else
    # Para updated, alternar o status anterior
    if [ "$INTERFACE_ENABLED" = "true" ]; then
        PREV_STATUS="false"
    else
        PREV_STATUS="true"
    fi
    SNAPSHOTS='"snapshots": { "prechange": { "enabled": '$PREV_STATUS' }, "postchange": { "enabled": '$INTERFACE_ENABLED' } }'
fi

# Montar o payload completo
read -r -d '' PAYLOAD << EOF
{
  "event": "${EVENT_TYPE}",
  "timestamp": "${TIMESTAMP}",
  "model": "interface",
  "username": "admin",
  "request_id": "${REQUEST_ID}",
  "data": {
    "id": ${INTERFACE_ID},
    "device": {
      "id": ${DEVICE_ID},
      "name": "${DEVICE_NAME}",
      "display": "${DEVICE_NAME}"
    },
    "name": "${INTERFACE_NAME}",
    "type": {
      "value": "1000base-t",
      "label": "1000BASE-T (1GE)"
    },
    "enabled": ${INTERFACE_ENABLED},
    "mgmt_only": false,
    "description": "${DESCRIPTION}",
    "mode": {
      "value": "access",
      "label": "Access"
    }
  },
  ${SNAPSHOTS}
}
EOF

# Exibir detalhes do teste
echo -e "${GREEN}===== TESTE DE WEBHOOK NETBOX =====${NC}"
echo -e "${YELLOW}URL:${NC} $WEBHOOK_URL"
echo -e "${YELLOW}Evento:${NC} $EVENT_TYPE"
echo -e "${YELLOW}Dispositivo:${NC} $DEVICE_NAME"
echo -e "${YELLOW}Interface:${NC} $INTERFACE_NAME"
echo -e "${YELLOW}Status:${NC} $([ "$INTERFACE_ENABLED" = "true" ] && echo "Ativada" || echo "Desativada")"
echo -e "${YELLOW}Descrição:${NC} $DESCRIPTION"
echo ""

if [ "$VERBOSE" = true ]; then
    echo -e "${BLUE}Payload completo:${NC}"
    echo "$PAYLOAD" | jq . 2>/dev/null || echo "$PAYLOAD"
    echo ""
fi

# Verificar se jq está instalado para formatação JSON
if ! command -v jq &> /dev/null && [ "$VERBOSE" = false ]; then
    echo -e "${YELLOW}Dica: Instale jq para formatação JSON melhorada:${NC} apt-get install jq"
fi

# Enviar o webhook para a API
echo -e "${GREEN}Enviando webhook...${NC}"

# Enviar a requisição POST
start_time=$(date +%s.%N)
RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" -d "$PAYLOAD" "$WEBHOOK_URL")
end_time=$(date +%s.%N)
STATUS=$?
execution_time=$(echo "$end_time - $start_time" | bc)

# Verificar se a requisição foi bem-sucedida
if [ $STATUS -eq 0 ]; then
    echo -e "${GREEN}✓ Requisição enviada com sucesso!${NC} (${execution_time}s)"
    echo -e "${YELLOW}Resposta:${NC}"
    echo "$RESPONSE" | jq . 2>/dev/null || echo "$RESPONSE"
else
    echo -e "${RED}✗ Erro ao enviar requisição. Código de status: $STATUS${NC}"
fi

# Instruções para verificar os logs
echo ""
echo -e "${BLUE}Para verificar os logs da API e confirmar que o webhook foi recebido:${NC}"
echo "  kubectl logs -l app=netbox-webhook-api --tail=20"
echo ""
echo -e "${BLUE}Resumo da chamada:${NC}"
echo "  $EVENT_TYPE interface '$INTERFACE_NAME' no dispositivo '$DEVICE_NAME'"
echo "  Status: $([ "$INTERFACE_ENABLED" = "true" ] && echo "Ativada" || echo "Desativada")"