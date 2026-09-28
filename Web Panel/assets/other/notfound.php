<?php
require_once __DIR__ . '/../../includes/auth.php';
require_auth();
?>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Not Found</title>
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css">
  <style>
    *{box-sizing:border-box;margin:0;padding:0}
    body{font-family:'Segoe UI',system-ui,sans-serif;background:#0a0e17;color:#e2e8f0;min-height:100vh;display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center;padding:40px 20px}
    .icon{font-size:5rem;color:#f43f5e;margin-bottom:20px}
    h1{font-size:1.6rem;margin-bottom:12px;color:#e2e8f0}
    p{color:#94a3b8;font-size:.95rem;max-width:420px;line-height:1.6;margin-bottom:28px}
    a.btn{display:inline-block;padding:10px 24px;background:#4dc3fa;color:#0a0e17;border-radius:8px;font-weight:600;text-decoration:none;transition:opacity .2s}
    a.btn:hover{opacity:.85}
  </style>
</head>
<body>
  <div class="icon"><i class="fas fa-ghost"></i></div>
  <h1>No Results Found</h1>
  <p>We couldn't find any victims matching your search. Please check your input and try again.</p>
  <a href="/dashboard.php" class="btn"><i class="fas fa-arrow-left"></i> Back to Dashboard</a>
</body>
</html>
