#!/usr/bin/env bash
# ============================================================
# Wazuh All-in-One Installer for Ubuntu 22.04 LTS
# Instala Wazuh Manager + Indexer + Dashboard + Filebeat
# Configura certificados, firewall e senha admin aleatória.
# ============================================================

set -euo pipefail
IFS=$'\n\t'

# --- Funções utilitárias ---
eecho() { echo -e "\e[1;33m[INFO]\e[0m $*"; }
wecho() { echo -e "\e[1;31m[WARN]\e[0m $*"; }
die()   { echo -e "\e[1;31m[ERROR]\e[0m $*"; exit 1; }

# --- Verificações iniciais ---
if [ "$(id -u)" -ne 0 ]; then
  die "Execute este script como root (sudo $0)"
fi

if ! grep -q "Ubuntu 22.04" /etc/os-release; then
  wecho "Este script foi projetado para Ubuntu 22.04. Prosseguindo mesmo assim..."
fi

# --- Configurações automáticas ---
NODE_NAME="wazuh-server"
SERVER_IP=$(hostname -I | awk '{print $1}')
ADMIN_USER="admin"
ADMIN_PASS=$(openssl rand -base64 12)
WAZUH_VERSION="4.13"
WAZUH_REPO_URL="https://packages.wazuh.com/${WAZUH_VERSION}/apt"
WAZUH_KEYRING="/usr/share/keyrings/wazuh.gpg"

eecho "==============================="
eecho " 🚀 Iniciando instalação Wazuh All-in-One"
eecho "==============================="
sleep 2

# --- Atualiza o sistema ---
eecho "Atualizando pacotes..."
apt-get update -y && apt-get upgrade -y

# --- Instala dependências ---
eecho "Instalando dependências..."
apt-get install -y curl unzip gnupg apt-transport-https software-properties-common pwgen ufw jq

# --- Adiciona repositório Wazuh ---
eecho "Adicionando repositório Wazuh..."
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --dearmor -o ${WAZUH_KEYRING}
echo "deb [signed-by=${WAZUH_KEYRING}] ${WAZUH_REPO_URL} stable main" | tee /etc/apt/sources.list.d/wazuh.list
apt-get update -y

# --- Instala pacotes principais ---
eecho "Instalando Wazuh Manager, Indexer e Dashboard..."
apt-get install -y wazuh-manager wazuh-indexer wazuh-dashboard filebeat

# --- Configuração dos certificados ---
eecho "Gerando certificados TLS..."
mkdir -p /etc/wazuh-certificates
cd /etc/wazuh-certificates

cat > ./instances.yml <<EOF
nodes:
  - name: ${NODE_NAME}
    ip: ${SERVER_IP}
EOF

/var/ossec/bin/wazuh-cert-tool.sh -A > /dev/null 2>&1
tar -xf wazuh-certificates.tar
cp -r ./wazuh-certificates/* /etc/

chown -R wazuh:wazuh /etc/wazuh-certificates /etc/wazuh-certificates/*
chmod -R 600 /etc/wazuh-certificates/*

# --- Configura Indexer ---
eecho "Configurando Wazuh Indexer..."
systemctl daemon-reexec
/usr/share/wazuh-indexer/bin/wazuh-indexer-setup.sh --start-cluster

# --- Cria usuário admin com senha aleatória ---
eecho "Criando usuário administrador no Dashboard..."
/usr/share/wazuh-indexer/plugins/opensearch-security/tools/securityadmin.sh \
  -cd /usr/share/wazuh-indexer/plugins/opensearch-security/securityconfig/ \
  -nhnv -icl -key /etc/wazuh-certificates/wazuh-indexer-key.pem \
  -cert /etc/wazuh-certificates/wazuh-indexer.pem \
  -cacert /etc/wazuh-certificates/root-ca.pem || true

/usr/share/wazuh-indexer/bin/opensearch-users useradd ${ADMIN_USER} -p "${ADMIN_PASS}" -r admin

# --- Configura Dashboard ---
eecho "Configurando Dashboard..."
sed -i "s|https://.*:5601|https://${SERVER_IP}:5601|g" /usr/share/wazuh-dashboard/config/opensearch_dashboards.yml || true
systemctl enable wazuh-dashboard
systemctl restart wazuh-dashboard

# --- Configura Filebeat ---
eecho "Configurando Filebeat..."
curl -so /etc/filebeat/filebeat.yml https://packages.wazuh.com/${WAZUH_VERSION}/tpl/wazuh/filebeat/filebeat.yml
mkdir -p /usr/share/filebeat/module/wazuh
curl -s https://packages.wazuh.com/4.x/filebeat/wazuh-filebeat-0.4.tar.gz | tar -xz -C /usr/share/filebeat/module/

filebeat keystore create --force
echo -n "${ADMIN_USER}" | filebeat keystore add username --stdin --force
echo -n "${ADMIN_PASS}" | filebeat keystore add password --stdin --force
systemctl enable filebeat
systemctl restart filebeat

# --- Habilita serviços ---
eecho "Habilitando serviços..."
systemctl enable wazuh-manager wazuh-indexer wazuh-dashboard
systemctl restart wazuh-manager wazuh-indexer wazuh-dashboard

# --- Configura firewall (UFW) ---
eecho "Configurando firewall (ufw)..."
ufw --force enable
ufw allow 22/tcp
ufw allow 443/tcp
ufw allow 5601/tcp
ufw allow 1514/tcp
ufw allow 1515/tcp
ufw allow 1516/tcp
ufw allow 9200/tcp
ufw allow 55000/tcp

# --- Exibe resumo final ---
clear
cat <<EOF

==============================================================
✅ INSTALAÇÃO CONCLUÍDA COM SUCESSO
==============================================================

🌐 Acesse o painel Wazuh Dashboard:
    URL: https://${SERVER_IP}:5601
    Usuário: ${ADMIN_USER}
    Senha: ${ADMIN_PASS}

📁 Logs e Configurações:
    - Manager: /var/ossec/logs/ossec.log
    - Indexer: /var/log/wazuh-indexer/
    - Dashboard: /var/log/wazuh-dashboard/
    - Filebeat: /var/log/filebeat/filebeat

🔐 Certificados:
    - Local: /etc/wazuh-certificates/

🔥 Firewall configurado com as portas necessárias.

Para iniciar/parar serviços:
    systemctl start|stop wazuh-manager wazuh-indexer wazuh-dashboard filebeat

Documentação: https://documentation.wazuh.com/

==============================================================
EOF
