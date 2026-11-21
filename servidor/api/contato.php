<?php
/**
 * API de contatos - CW Parafusos & Ferramentas
 * Recebe o formulário do site (POST, corpo JSON) e grava no banco cwdb.
 *
 * A configuração (usuário/senha do banco) fica FORA da pasta pública,
 * em /etc/cwapi/config.php, criada pelo instalador.
 */

declare(strict_types=1);

$config = require '/etc/cwapi/config.php';

// ---------- CORS: só aceita chamadas vindas do site ----------
$origem = $_SERVER['HTTP_ORIGIN'] ?? '';
if (in_array($origem, $config['origens_permitidas'], true)) {
    header('Access-Control-Allow-Origin: ' . $origem);
    header('Vary: Origin');
    header('Access-Control-Allow-Methods: POST, OPTIONS');
    header('Access-Control-Allow-Headers: Content-Type');
}
header('Content-Type: application/json; charset=utf-8');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

function responder(int $codigo, array $dados): void
{
    http_response_code($codigo);
    echo json_encode($dados, JSON_UNESCAPED_UNICODE);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    responder(405, ['ok' => false, 'erro' => 'Método não permitido']);
}
if ($origem !== '' && !in_array($origem, $config['origens_permitidas'], true)) {
    responder(403, ['ok' => false, 'erro' => 'Origem não permitida']);
}

// ---------- Lê e valida os dados ----------
$bruto = file_get_contents('php://input', false, null, 0, 20000) ?: '';
$d = json_decode($bruto, true);
if (!is_array($d)) {
    responder(400, ['ok' => false, 'erro' => 'Dados inválidos']);
}

// Campo "armadilha" para robôs: humanos não veem e não preenchem
if (!empty($d['site'])) {
    responder(200, ['ok' => true]);
}

$limpar = static fn($v, int $max): string =>
    mb_substr(trim(strip_tags((string)($v ?? ''))), 0, $max);

$nome          = $limpar($d['nome'] ?? '', 120);
$email         = mb_strtolower($limpar($d['email'] ?? '', 160));
$telefone      = $limpar($d['telefone'] ?? '', 30);
$mensagem      = $limpar($d['mensagem'] ?? '', 5000);
$consentimento = !empty($d['consentimento']) ? 1 : 0;
$origemPagina  = $limpar($d['pagina'] ?? '', 255);
$userAgent     = $limpar($_SERVER['HTTP_USER_AGENT'] ?? '', 255);

if ($nome === '' || $telefone === '' || $mensagem === '') {
    responder(422, ['ok' => false, 'erro' => 'Preencha nome, telefone e mensagem']);
}
if ($email !== '' && !filter_var($email, FILTER_VALIDATE_EMAIL)) {
    responder(422, ['ok' => false, 'erro' => 'E-mail inválido']);
}
if ($consentimento !== 1) {
    responder(422, ['ok' => false, 'erro' => 'É preciso aceitar o uso dos dados']);
}

// IP anonimizado (não guardamos o IP real, só um código)
$ip     = $_SERVER['REMOTE_ADDR'] ?? '';   // o Caddy entrega o IP real do visitante aqui
$ipHash = hash('sha256', $ip . $config['sal_ip']);

// ---------- Grava no banco ----------
try {
    $pdo = new PDO(
        'mysql:host=' . $config['db_host'] . ';dbname=' . $config['db_nome'] . ';charset=utf8mb4',
        $config['db_usuario'],
        $config['db_senha'],
        [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION, PDO::ATTR_EMULATE_PREPARES => false]
    );

    // Limite anti-spam: no máximo 5 envios por 10 minutos do mesmo IP
    $q = $pdo->prepare('SELECT COUNT(*) FROM contatos WHERE ip_hash = ? AND criado_em > NOW() - INTERVAL 10 MINUTE');
    $q->execute([$ipHash]);
    if ((int)$q->fetchColumn() >= 5) {
        responder(429, ['ok' => false, 'erro' => 'Muitos envios. Tente mais tarde.']);
    }

    $ins = $pdo->prepare(
        'INSERT INTO contatos (CNPJ_EMPRESA, nome, email, telefone, mensagem, consentimento, origem_pagina, user_agent, ip_hash)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)'
    );
    $ins->execute([$config['cnpj_empresa'] ?? '39535064000122', $nome, $email !== '' ? $email : null, $telefone, $mensagem, $consentimento, $origemPagina, $userAgent, $ipHash]);

    responder(201, ['ok' => true, 'id' => (int)$pdo->lastInsertId()]);
} catch (Throwable $e) {
    error_log('cwapi contato: ' . $e->getMessage());
    responder(500, ['ok' => false, 'erro' => 'Erro ao salvar']);
}
