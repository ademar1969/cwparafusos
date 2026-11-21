-- =====================================================================
--  Banco de dados CWDB - CW Parafusos & Ferramentas
--  Guarda os contatos (pedidos de orçamento) enviados pelo site.
--  MariaDB 10.6+ / MySQL 8+
-- =====================================================================

CREATE DATABASE IF NOT EXISTS cwdb
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE cwdb;

-- ---------------------------------------------------------------------
--  Tabela principal: um registro por contato enviado pelo formulário
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS contatos (
  id              INT UNSIGNED     NOT NULL AUTO_INCREMENT,
  criado_em       DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
  nome            VARCHAR(120)     NOT NULL,
  email           VARCHAR(160)     NULL,
  telefone        VARCHAR(30)      NOT NULL,
  mensagem        TEXT             NOT NULL,
  consentimento   TINYINT(1)       NOT NULL DEFAULT 0,   -- aceitou a LGPD
  origem_pagina   VARCHAR(255)     NULL,                 -- de qual endereço veio
  user_agent      VARCHAR(255)     NULL,                 -- navegador/celular
  ip_hash         CHAR(64)         NULL,                 -- IP anonimizado (SHA-256)
  status          ENUM('novo','respondido','orcamento_enviado','venda','descartado')
                                   NOT NULL DEFAULT 'novo',
  PRIMARY KEY (id),
  KEY idx_criado_em (criado_em),
  KEY idx_email (email),
  KEY idx_status (status),
  KEY idx_ip_hash_data (ip_hash, criado_em)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
--  Views para análise
-- ---------------------------------------------------------------------

-- Quantos contatos por dia
CREATE OR REPLACE VIEW vw_contatos_por_dia AS
SELECT DATE(criado_em)            AS dia,
       COUNT(*)                   AS total,
       COUNT(DISTINCT telefone)   AS pessoas_distintas
FROM contatos
GROUP BY DATE(criado_em);

-- Quantos contatos por mês
CREATE OR REPLACE VIEW vw_contatos_por_mes AS
SELECT DATE_FORMAT(criado_em, '%Y-%m') AS mes,
       COUNT(*)                        AS total,
       COUNT(DISTINCT telefone)        AS pessoas_distintas,
       SUM(email IS NOT NULL)          AS com_email
FROM contatos
GROUP BY DATE_FORMAT(criado_em, '%Y-%m');

-- Contatos por situação (funil)
CREATE OR REPLACE VIEW vw_contatos_por_status AS
SELECT status, COUNT(*) AS total
FROM contatos
GROUP BY status;

-- Celular x computador
CREATE OR REPLACE VIEW vw_contatos_por_dispositivo AS
SELECT CASE
         WHEN user_agent REGEXP 'Mobile|Android|iPhone|iPad' THEN 'Celular/Tablet'
         ELSE 'Computador'
       END AS dispositivo,
       COUNT(*) AS total
FROM contatos
GROUP BY dispositivo;

-- ---------------------------------------------------------------------
--  Consultas úteis (exemplos para rodar no MariaDB)
-- ---------------------------------------------------------------------
--  SELECT * FROM vw_contatos_por_mes ORDER BY mes DESC;
--  SELECT * FROM vw_contatos_por_dia ORDER BY dia DESC LIMIT 30;
--  SELECT COUNT(*) AS total_geral FROM contatos;
--  SELECT * FROM contatos ORDER BY criado_em DESC LIMIT 20;
--  UPDATE contatos SET status = 'respondido' WHERE id = 1;
