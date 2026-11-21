# Banco CWDB + API de contatos (Oracle Cloud)

Grava cada pedido de orçamento enviado pelo site no banco MariaDB `cwdb`.

## Arquivos
- `cwdb.sql` – cria o banco `cwdb`, a tabela `contatos` e as views de análise
- `api/contato.php` – recebe o formulário do site e grava no banco
- `api/relatorio.php` – painel com totais por mês, dispositivo e últimos contatos (protegido por chave)
- `instalar.sh` – instala tudo numa máquina Ubuntu da Oracle Cloud (MariaDB, PHP, Caddy com HTTPS, firewall)

## Instalação
1. Oracle Cloud → Compute → Instances → Create instance (Ubuntu 24.04, formato Always Free).
2. Na VCN da instância → Security List → adicionar regras de entrada TCP 80 e 443 (origem 0.0.0.0/0).
3. No Registro.br, criar o registro `A` com nome `api` apontando para o IP público da instância.
4. Na instância (SSH):
   ```
   curl -fsSL https://raw.githubusercontent.com/ademar1969/cwparafusos/banco-de-dados/servidor/instalar.sh -o instalar.sh
   sudo bash instalar.sh api.cwparafusos.com.br
   ```
5. Guardar a chave do relatório exibida no final.

## Análises no banco
```
sudo mariadb cwdb
SELECT * FROM vw_contatos_por_mes ORDER BY mes DESC;
SELECT * FROM vw_contatos_por_dia ORDER BY dia DESC LIMIT 30;
SELECT * FROM vw_contatos_por_dispositivo;
```
