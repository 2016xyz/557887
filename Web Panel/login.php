<?php
require_once __DIR__ . '/includes/auth.php';
require_once __DIR__ . '/includes/csrf.php';
require_guest();
?>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Jasmin — Login</title>
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css">
  <link rel="stylesheet" href="./assets/css/login-new.css">
</head>
<body>
<div class="login-wrap">
  <form id="accesspanel" action="checklogin.php" method="post">
    <div class="logo"><i class="fas fa-skull-crossbones"></i></div>
    <h1>JASMIN</h1>
    <p class="subtitle">Ransomware Control Panel</p>
    <div class="field">
      <i class="fas fa-user"></i>
      <input type="text" name="username" id="email" placeholder="Username" required autocomplete="username">
    </div>
    <div class="field">
      <i class="fas fa-lock"></i>
      <input type="password" name="password" id="password" placeholder="Password" required autocomplete="current-password">
    </div>
    <?=csrf_field()?>
    <button type="submit" id="go">Authorize</button>
    <p id="msg" class="msg"></p>
  </form>
</div>
<script>
document.getElementById('accesspanel').addEventListener('submit', function(e) {
  e.preventDefault();
  var btn = document.getElementById('go');
  var msg = document.getElementById('msg');
  btn.textContent = 'Verifying...';
  btn.disabled = true;
  msg.textContent = '';
  fetch('checklogin.php', {method:'POST', body: new FormData(this)})
    .then(r => r.text())
    .then(data => {
      if (data.trim() === 'success') {
        window.location = 'dashboard.php';
      } else {
        msg.textContent = 'Access Denied';
        msg.className = 'msg error';
        btn.textContent = 'Authorize';
        btn.disabled = false;
      }
    })
    .catch(() => {
      msg.textContent = 'Connection error';
      msg.className = 'msg error';
      btn.textContent = 'Authorize';
      btn.disabled = false;
    });
});
</script>
</body>
</html>
