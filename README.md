# 🦊 Wazuh All-in-One Install

Script Bash automatizado para instalar **Wazuh All-in-One** em **Ubuntu 22.04 LTS**, incluindo todos os componentes essenciais:

- 🧩 **Wazuh Manager**
- 🔍 **Wazuh Indexer (OpenSearch)**
- 📊 **Wazuh Dashboard**
- 📡 **Filebeat**

Tudo configurado automaticamente com certificados TLS, firewall liberado e credenciais seguras.

---

## ⚙️ Instalação rápida

Clone o repositório e execute o script:

```bash
git clone https://github.com/maksyflay/wazuh.git
cd wazuh
chmod +x install_wazuh_all.sh
sudo ./install_wazuh_all.sh
