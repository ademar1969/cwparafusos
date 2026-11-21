#!/usr/bin/env bash
# Verifica a API de contatos dentro da VM: PHP -> banco cwdb, e um envio
# de teste completo (Caddy -> PHP-FPM -> MariaDB) por uma porta local 8080
# que só aceita conexões da própria máquina. O contato de teste é apagado.
set -uo pipefail
echo "==> Instalando o PHP de linha de comando (para testes)"
dnf -y -q install php-cli >/dev/null 2>&1 && echo "php-cli OK"

echo "==> Servicos"
systemctl is-active mariadb php-fpm caddy

echo "==> PHP -> banco cwdb"
php -r '$c=require "/etc/cwapi/config.php"; $p=new PDO("mysql:host=localhost;dbname=cwdb",$c["db_usuario"],$c["db_senha"]); echo "Conexao OK, contatos gravados: ".$p->query("SELECT COUNT(*) FROM contatos")->fetchColumn()."\n";' || echo "FALHA na conexao PHP->banco"

echo "==> Porta de teste local (127.0.0.1:8080)"
if ! grep -q '127.0.0.1:8080' /etc/caddy/Caddyfile; then
  cat >> /etc/caddy/Caddyfile <<'EOF'

# Acesso local para testes/monitoramento (so de dentro da VM)
http://127.0.0.1:8080 {
    root * /var/www/cwapi
    @permitido path /contato.php
    handle @permitido {
        php_fastcgi 127.0.0.1:9000
    }
    handle {
        respond "CW API local" 404
    }
}
EOF
  systemctl reload caddy || systemctl restart caddy
  sleep 2
fi

echo "==> Envio de teste completo"
RESP=$(curl -s -w ' HTTP %{http_code}' -X POST http://127.0.0.1:8080/contato.php \
  -H 'Origin: https://www.cwparafusos.com.br' -H 'Content-Type: text/plain' \
  -d '{"nome":"TESTE AUTOMATICO","telefone":"00 0000-0000","email":"teste@cwparafusos.com.br","mensagem":"teste de instalacao","consentimento":true,"pagina":"teste"}')
echo "Resposta: $RESP"

echo "==> Conferindo no banco e apagando o teste"
mariadb cwdb -e "SELECT id, criado_em, nome FROM contatos WHERE nome='TESTE AUTOMATICO'; DELETE FROM contatos WHERE nome='TESTE AUTOMATICO'; SELECT COUNT(*) AS contatos_reais FROM contatos;"

echo "==> Ultimas mensagens do Caddy"
journalctl -u caddy --no-pager -n 8 2>/dev/null | cut -c1-220

source /root/cwdb-credenciais.txt
echo
echo "Relatorio (depois que o DNS api estiver ativo):"
echo "https://api.cwparafusos.com.br/relatorio.php?chave=$CHAVE_RELATORIO"
echo "VERIFICACAO_CONCLUIDA"
