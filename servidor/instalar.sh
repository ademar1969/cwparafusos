#!/usr/bin/env bash
# =====================================================================
#  Instalador do banco CWDB + API de contatos - CW Parafusos
#  Para uma máquina Ubuntu 22.04/24.04 (Oracle Cloud Always Free)
#
#  Uso (na máquina da Oracle, via SSH ou Cloud Shell):
#    curl -fsSL https://raw.githubusercontent.com/ademar1969/cwparafusos/banco-de-dados/servidor/instalar.sh -o instalar.sh
#    sudo bash instalar.sh api.cwparafusos.com.br
# =====================================================================
set -euo pipefail

DOMINIO="${1:-}"
RAMO="${RAMO:-banco-de-dados}"
RAW="https://raw.githubusercontent.com/ademar1969/cwparafusos/${RAMO}/servidor"
ORIGENS=("https://www.cwparafusos.com.br" "https://cwparafusos.com.br" "https://ademar1969.github.io")

if [[ $EUID -ne 0 ]]; then echo "Rode com sudo: sudo bash instalar.sh api.cwparafusos.com.br"; exit 1; fi
if [[ -z "$DOMINIO" ]]; then echo "Informe o domínio da API. Ex.: sudo bash instalar.sh api.cwparafusos.com.br"; exit 1; fi
if ! grep -qi ubuntu /etc/os-release; then echo "Este instalador foi feito para Ubuntu."; exit 1; fi

echo "==> 1/7 Atualizando o sistema e instalando MariaDB, PHP e ferramentas"
export DEBIAN_FRONTEND=noninteractive
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
apt-get update -y
apt-get install -y mariadb-server php-fpm php-mysql php-mbstring curl gnupg \
  debian-keyring debian-archive-keyring apt-transport-https iptables-persistent openssl

echo "==> 2/7 Instalando o Caddy (servidor web com HTTPS automático)"
if ! command -v caddy >/dev/null; then
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' > /etc/apt/sources.list.d/caddy-stable.list
  apt-get update -y
  apt-get install -y caddy
fi

echo "==> 3/7 Baixando os arquivos da API e do banco"
TMP=$(mktemp -d)
for f in cwdb.sql api/contato.php api/relatorio.php; do
  mkdir -p "$TMP/$(dirname "$f")"
  curl -fsSL "$RAW/$f" -o "$TMP/$f"
done

echo "==> 4/7 Criando o banco cwdb e o usuário da aplicação"
systemctl enable --now mariadb
CRED=/root/cwdb-credenciais.txt
if [[ -f $CRED ]]; then
  # Reinstalação: reaproveita as senhas já criadas
  # shellcheck disable=SC1090
  source "$CRED"
else
  DB_SENHA=$(openssl rand -hex 20)
  CHAVE_RELATORIO=$(openssl rand -hex 16)
  SAL_IP=$(openssl rand -hex 16)
  umask 077
  cat > "$CRED" <<EOF
DB_SENHA=$DB_SENHA
CHAVE_RELATORIO=$CHAVE_RELATORIO
SAL_IP=$SAL_IP
EOF
fi
mariadb < "$TMP/cwdb.sql"
mariadb <<EOF
CREATE USER IF NOT EXISTS 'cwapp'@'localhost' IDENTIFIED BY '$DB_SENHA';
ALTER USER 'cwapp'@'localhost' IDENTIFIED BY '$DB_SENHA';
GRANT SELECT, INSERT, UPDATE ON cwdb.* TO 'cwapp'@'localhost';
FLUSH PRIVILEGES;
EOF

echo "==> 5/7 Gravando a configuração (fora da pasta pública)"
mkdir -p /etc/cwapi
ORIGENS_PHP=$(printf "'%s', " "${ORIGENS[@]}")
cat > /etc/cwapi/config.php <<EOF
<?php
return [
    'db_host'            => 'localhost',
    'db_nome'            => 'cwdb',
    'db_usuario'         => 'cwapp',
    'db_senha'           => '$DB_SENHA',
    'chave_relatorio'    => '$CHAVE_RELATORIO',
    'sal_ip'             => '$SAL_IP',
    'cnpj_empresa'       => '39535064000122',
    'origens_permitidas' => [${ORIGENS_PHP%, }],
];
EOF
chown root:www-data /etc/cwapi/config.php
chmod 640 /etc/cwapi/config.php

mkdir -p /var/www/cwapi
install -m 644 "$TMP/api/contato.php" "$TMP/api/relatorio.php" /var/www/cwapi/
rm -rf "$TMP"

echo "==> 6/7 Configurando o servidor web com HTTPS para $DOMINIO"
SOCK=$(ls /run/php/php*-fpm.sock | head -1)
usermod -aG www-data caddy
cat > /etc/caddy/Caddyfile <<EOF
$DOMINIO {
    root * /var/www/cwapi
    encode gzip
    @permitido path /contato.php /relatorio.php
    handle @permitido {
        php_fastcgi unix/$SOCK
    }
    handle {
        respond "CW API" 404
    }
}
EOF
systemctl restart "$(basename "$SOCK" .sock)"
systemctl restart caddy

echo "==> 7/7 Liberando as portas 80 e 443 no firewall da máquina"
for p in 80 443; do
  iptables -C INPUT -p tcp --dport $p -j ACCEPT 2>/dev/null || iptables -I INPUT 1 -p tcp --dport $p -j ACCEPT
done
netfilter-persistent save

IP=$(curl -fsS https://api.ipify.org || echo "?")
cat <<EOF

=====================================================================
 PRONTO! Banco cwdb e API instalados.

 IP público desta máquina ..: $IP
   -> No Registro.br crie:  tipo A | nome: api | valor: $IP

 Endereço da API ..........: https://$DOMINIO/contato.php
 Relatório de contatos ....: https://$DOMINIO/relatorio.php?chave=$CHAVE_RELATORIO

 Guarde a chave do relatório. Senhas salvas em: $CRED
 Para ver os dados direto no banco:  sudo mariadb cwdb
=====================================================================
EOF
