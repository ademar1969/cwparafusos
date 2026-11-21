#!/usr/bin/env bash
# =====================================================================
#  Instala a API de contatos da CW Parafusos numa VM Oracle Linux 9
#  que JÁ TEM o MariaDB e o banco cwdb (criado por criar-banco.sh).
#  Instala: PHP-FPM, Caddy (HTTPS automático) e libera o firewall.
#
#  curl -fsSL https://raw.githubusercontent.com/ademar1969/cwparafusos/banco-de-dados/servidor/instalar-api-oraclelinux.sh | sudo bash -s api.cwparafusos.com.br
# =====================================================================
set -euo pipefail
DOMINIO="${1:-api.cwparafusos.com.br}"
RAMO="${RAMO:-banco-de-dados}"
RAW="https://raw.githubusercontent.com/ademar1969/cwparafusos/${RAMO}/servidor"
CRED=/root/cwdb-credenciais.txt
ORIGENS="'https://www.cwparafusos.com.br', 'https://cwparafusos.com.br', 'https://ademar1969.github.io'"

[[ $EUID -eq 0 ]] || { echo "Rode com sudo"; exit 1; }
[[ -f $CRED ]] || { echo "Rode antes o criar-banco.sh (nao achei $CRED)"; exit 1; }
# shellcheck disable=SC1090
source "$CRED"

echo "==> 1/6 Instalando PHP-FPM"
dnf -y module reset php >/dev/null 2>&1 || true
dnf -y module enable php:8.2 >/dev/null 2>&1 || true
dnf -y install php-fpm php-mysqlnd php-mbstring curl tar policycoreutils-python-utils
# PHP-FPM escutando só localmente na porta 9000
sed -i 's#^listen = .*#listen = 127.0.0.1:9000#' /etc/php-fpm.d/www.conf
sed -i 's#^listen.allowed_clients = .*#listen.allowed_clients = 127.0.0.1#' /etc/php-fpm.d/www.conf

echo "==> 2/6 Instalando o Caddy (servidor web com HTTPS automatico)"
if ! command -v caddy >/dev/null; then
  ARCH=$(uname -m); [[ $ARCH == aarch64 ]] && GOARCH=arm64 || GOARCH=amd64
  VER=$(curl -fsSL https://api.github.com/repos/caddyserver/caddy/releases/latest | grep -m1 '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
  [[ -n "$VER" ]] || VER="2.10.2"
  echo "Baixando Caddy $VER ($GOARCH) do GitHub"
  TMPC=$(mktemp -d)
  curl -fsSL "https://github.com/caddyserver/caddy/releases/download/v${VER}/caddy_${VER}_linux_${GOARCH}.tar.gz" -o "$TMPC/caddy.tgz"
  tar -xzf "$TMPC/caddy.tgz" -C "$TMPC" caddy
  install -m 755 "$TMPC/caddy" /usr/bin/caddy
  rm -rf "$TMPC"
  restorecon /usr/bin/caddy 2>/dev/null || true
  caddy version
  id caddy >/dev/null 2>&1 || useradd --system --home /var/lib/caddy --create-home --shell /sbin/nologin caddy
  mkdir -p /etc/caddy
  cat > /etc/systemd/system/caddy.service <<'EOF'
[Unit]
Description=Caddy
After=network-online.target
Wants=network-online.target
[Service]
User=caddy
Group=caddy
ExecStart=/usr/bin/caddy run --environ --config /etc/caddy/Caddyfile
ExecReload=/usr/bin/caddy reload --config /etc/caddy/Caddyfile --force
TimeoutStopSec=5s
LimitNOFILE=1048576
AmbientCapabilities=CAP_NET_BIND_SERVICE
[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
fi

echo "==> 3/6 Copiando a API"
mkdir -p /var/www/cwapi /etc/cwapi
curl -fsSL "$RAW/api/contato.php"   -o /var/www/cwapi/contato.php
curl -fsSL "$RAW/api/relatorio.php" -o /var/www/cwapi/relatorio.php
chmod 644 /var/www/cwapi/*.php
cat > /etc/cwapi/config.php <<EOF
<?php
return [
    'db_host'            => 'localhost',
    'db_nome'            => 'cwdb',
    'db_usuario'         => 'cwapp',
    'db_senha'           => '$DB_SENHA',
    'chave_relatorio'    => '$CHAVE_RELATORIO',
    'sal_ip'             => '$SAL_IP',
    'origens_permitidas' => [$ORIGENS],
];
EOF
chown root:apache /etc/cwapi/config.php
chmod 640 /etc/cwapi/config.php

echo "==> 4/6 Ajustando o SELinux"
semanage fcontext -a -t httpd_sys_content_t '/var/www/cwapi(/.*)?' 2>/dev/null || true
semanage fcontext -a -t httpd_sys_content_t '/etc/cwapi(/.*)?' 2>/dev/null || true
restorecon -R /var/www/cwapi /etc/cwapi || true
setsebool -P httpd_can_network_connect_db 1 || true

echo "==> 5/6 Configurando o Caddy para $DOMINIO"
cat > /etc/caddy/Caddyfile <<EOF
$DOMINIO {
    root * /var/www/cwapi
    encode gzip
    @permitido path /contato.php /relatorio.php
    handle @permitido {
        php_fastcgi 127.0.0.1:9000
    }
    handle {
        respond "CW API" 404
    }
}
EOF
systemctl enable --now php-fpm
systemctl restart php-fpm
systemctl enable caddy
systemctl restart caddy

echo "==> 6/6 Liberando as portas 80 e 443 no firewall da VM"
firewall-cmd --permanent --add-service=http --add-service=https
firewall-cmd --reload

sleep 3
echo
echo "=== Teste local da API ==="
curl -s -o /dev/null -w "php-fpm+caddy respondendo: HTTP %{http_code}\n" -k --resolve "$DOMINIO:443:127.0.0.1" "https://$DOMINIO/contato.php" || echo "HTTPS ainda sem certificado (normal ate o DNS api apontar para esta VM)"
php -r '$c=require "/etc/cwapi/config.php"; $p=new PDO("mysql:host=localhost;dbname=cwdb",$c["db_usuario"],$c["db_senha"]); echo "Conexao PHP->cwdb: OK (".$p->query("SELECT COUNT(*) FROM contatos")->fetchColumn()." contatos)\n";'
systemctl is-active php-fpm caddy
echo
echo "API_INSTALADA_OK"
echo "Endereco da API ....: https://$DOMINIO/contato.php"
echo "Relatorio ..........: https://$DOMINIO/relatorio.php?chave=$CHAVE_RELATORIO"
