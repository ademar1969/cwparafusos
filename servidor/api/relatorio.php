<?php
/**
 * Relatório de contatos - CW Parafusos & Ferramentas
 * Acesso: https://api.cwparafusos.com.br/relatorio.php?chave=SUA_CHAVE
 * A chave é gerada pelo instalador e fica em /etc/cwapi/config.php
 */

declare(strict_types=1);

$config = require '/etc/cwapi/config.php';

header('Content-Type: text/html; charset=utf-8');
header('X-Robots-Tag: noindex, nofollow');
header("Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'");

$chave = (string)($_GET['chave'] ?? '');
if ($chave === '' || !hash_equals($config['chave_relatorio'], $chave)) {
    http_response_code(403);
    exit('<h1>Acesso negado</h1>');
}

$pdo = new PDO(
    'mysql:host=' . $config['db_host'] . ';dbname=' . $config['db_nome'] . ';charset=utf8mb4',
    $config['db_usuario'],
    $config['db_senha'],
    [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
);

$e = static fn($v): string => htmlspecialchars((string)$v, ENT_QUOTES, 'UTF-8');

$total   = (int)$pdo->query('SELECT COUNT(*) FROM contatos')->fetchColumn();
$hoje    = (int)$pdo->query('SELECT COUNT(*) FROM contatos WHERE DATE(criado_em) = CURDATE()')->fetchColumn();
$mesAtual= (int)$pdo->query("SELECT COUNT(*) FROM contatos WHERE DATE_FORMAT(criado_em,'%Y-%m') = DATE_FORMAT(CURDATE(),'%Y-%m')")->fetchColumn();
$pessoas = (int)$pdo->query('SELECT COUNT(DISTINCT telefone) FROM contatos')->fetchColumn();
$porMes  = $pdo->query('SELECT * FROM vw_contatos_por_mes ORDER BY mes DESC LIMIT 12')->fetchAll(PDO::FETCH_ASSOC);
$porDisp = $pdo->query('SELECT * FROM vw_contatos_por_dispositivo')->fetchAll(PDO::FETCH_ASSOC);
$ultimos = $pdo->query('SELECT id, criado_em, nome, email, telefone, mensagem, status FROM contatos ORDER BY criado_em DESC LIMIT 50')->fetchAll(PDO::FETCH_ASSOC);
?>
<!DOCTYPE html>
<html lang="pt-BR"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Relatório de contatos - CW</title>
<style>
body{font-family:system-ui,sans-serif;margin:0;background:#f2f2f6;color:#14142f}
header{background:#14142f;color:#fff;padding:18px 24px;font-size:1.3rem;font-weight:700}
main{max-width:1100px;margin:auto;padding:24px}
.kpis{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:14px;margin-bottom:24px}
.kpi{background:#fff;border-radius:10px;padding:18px;border-top:4px solid #5b5fd6}
.kpi b{display:block;font-size:2rem}
table{width:100%;border-collapse:collapse;background:#fff;border-radius:10px;overflow:hidden;margin-bottom:24px}
th,td{padding:9px 12px;border-bottom:1px solid #e4e4ec;text-align:left;font-size:.92rem;vertical-align:top}
th{background:#24243f;color:#fff}
h2{margin:8px 0 12px}
</style></head><body>
<header>CW Parafusos &amp; Ferramentas — Contatos pelo site</header>
<main>
<div class="kpis">
  <div class="kpi"><b><?= $total ?></b>contatos no total</div>
  <div class="kpi"><b><?= $pessoas ?></b>pessoas diferentes</div>
  <div class="kpi"><b><?= $mesAtual ?></b>neste mês</div>
  <div class="kpi"><b><?= $hoje ?></b>hoje</div>
</div>

<h2>Por mês</h2>
<table><tr><th>Mês</th><th>Contatos</th><th>Pessoas diferentes</th><th>Com e-mail</th></tr>
<?php foreach ($porMes as $l): ?>
<tr><td><?= $e($l['mes']) ?></td><td><?= $e($l['total']) ?></td><td><?= $e($l['pessoas_distintas']) ?></td><td><?= $e($l['com_email']) ?></td></tr>
<?php endforeach; ?>
</table>

<h2>Dispositivo</h2>
<table><tr><th>Dispositivo</th><th>Contatos</th></tr>
<?php foreach ($porDisp as $l): ?>
<tr><td><?= $e($l['dispositivo']) ?></td><td><?= $e($l['total']) ?></td></tr>
<?php endforeach; ?>
</table>

<h2>Últimos 50 contatos</h2>
<table><tr><th>#</th><th>Data</th><th>Nome</th><th>E-mail</th><th>Telefone</th><th>Mensagem</th><th>Status</th></tr>
<?php foreach ($ultimos as $l): ?>
<tr><td><?= $e($l['id']) ?></td><td><?= $e(date('d/m/Y H:i', strtotime($l['criado_em']))) ?></td><td><?= $e($l['nome']) ?></td><td><?= $e($l['email']) ?></td><td><?= $e($l['telefone']) ?></td><td><?= nl2br($e($l['mensagem'])) ?></td><td><?= $e($l['status']) ?></td></tr>
<?php endforeach; ?>
</table>
</main></body></html>
