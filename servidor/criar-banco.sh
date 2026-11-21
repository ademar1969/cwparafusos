#!/usr/bin/env bash
# Cria (ou atualiza) o banco cwdb e o usuário cwapp no MariaDB desta máquina.
# Pode rodar mais de uma vez sem perder dados.
#   curl -fsSL https://raw.githubusercontent.com/ademar1969/cwparafusos/banco-de-dados/servidor/criar-banco.sh | sudo bash
set -euo pipefail
RAMO="${RAMO:-banco-de-dados}"
RAW="https://raw.githubusercontent.com/ademar1969/cwparafusos/${RAMO}/servidor"
CRED=/root/cwdb-credenciais.txt

echo "==> Criando o banco cwdb, a tabela contatos e as views"
curl -fsSL "$RAW/cwdb.sql" | mariadb

echo "==> Criando o usuario cwapp (so acesso local)"
if [[ -f $CRED ]]; then
  # shellcheck disable=SC1090
  source "$CRED"
else
  DB_SENHA=$(openssl rand -hex 20)
  CHAVE_RELATORIO=$(openssl rand -hex 16)
  SAL_IP=$(openssl rand -hex 16)
  ( umask 077; printf 'DB_SENHA=%s\nCHAVE_RELATORIO=%s\nSAL_IP=%s\n' "$DB_SENHA" "$CHAVE_RELATORIO" "$SAL_IP" > "$CRED" )
fi
mariadb <<EOF
CREATE USER IF NOT EXISTS 'cwapp'@'localhost' IDENTIFIED BY '$DB_SENHA';
ALTER USER 'cwapp'@'localhost' IDENTIFIED BY '$DB_SENHA';
GRANT SELECT, INSERT, UPDATE ON cwdb.* TO 'cwapp'@'localhost';
FLUSH PRIVILEGES;
EOF

echo "==> Conferindo"
mariadb cwdb -e "SHOW FULL TABLES; SELECT COUNT(*) AS contatos_gravados FROM contatos;"
mariadb -e "SHOW GRANTS FOR 'cwapp'@'localhost';"
echo "BANCO_CWDB_OK  (senha do usuario cwapp guardada em $CRED, so o root le)"
