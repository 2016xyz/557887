<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" http-equiv="refresh" content="2;url=/dashboard.php">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Loading...</title>
  <style>
    *{margin:0;padding:0;box-sizing:border-box}
    body{background:#0a0e17;display:flex;align-items:center;justify-content:center;min-height:100vh;font-family:'Segoe UI',system-ui,sans-serif}
    .loader{text-align:center}
    .spinner{width:48px;height:48px;border:3px solid #1e293b;border-top-color:#4dc3fa;border-radius:50%;animation:spin .8s linear infinite;margin:0 auto 20px}
    .text{color:#94a3b8;font-size:.9rem;letter-spacing:2px}
    @keyframes spin{to{transform:rotate(360deg)}}
  </style>
</head>
<body>
  <div class="loader">
    <div class="spinner"></div>
    <div class="text">LOADING</div>
  </div>
</body>
</html>
