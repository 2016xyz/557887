Jasmin C2 Platform
==================

本目录不提供任何默认凭据。

管理员账户由部署流程创建：
  - Docker:   由 entrypoint 调用 setup.php，口令取自 ADMIN_PASSWORD 环境变量
              （未设置则使用初始口令，部署后请立刻在后台「修改密码」处更换）
  - 手动部署: 安装向导 install.php 完成第 2 步后于第 3 步创建

请勿在此文件或任何 web 可访问路径下记录口令。
