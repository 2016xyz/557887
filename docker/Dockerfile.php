FROM php:8.2-apache

RUN apt-get update && apt-get install -y --no-install-recommends git unzip rsync libzip-dev \
    && rm -rf /var/lib/apt/lists/* \
    && docker-php-ext-install pdo pdo_mysql zip \
    && pecl install redis && docker-php-ext-enable redis \
    && a2enmod rewrite \
    && a2enmod headers

RUN echo '<Directory /var/www/html>\n    AllowOverride All\n    Require all granted\n</Directory>' > /etc/apache2/conf-available/jasmin.conf \
    && a2enconf jasmin

COPY ["Web Panel/", "/var/www/html/"]
COPY ["VERSION", "/var/www/html/VERSION"]

# 解密工具烘焙到非卷路径 —— payloads/ 是 volume，直接 COPY 进去会被卷挂载覆盖，
# 因此由 entrypoint 在运行时补进卷内。
# 早期缺失: 解密教程里的 curl payloads/jasmin_decrypt_openssl.sh 与 .py 全是 404。
COPY ["Linux Encrypter/", "/opt/jasmin-tools/"]

RUN rm -f /var/www/html/.installed /var/www/html/.env \
    && chown -R www-data:www-data /var/www/html \
    && chmod -R 755 /var/www/html \
    && mkdir -p /var/www/html/payloads /var/www/html/passwords \
    && chown www-data:www-data /var/www/html/payloads /var/www/html/passwords

# ── 会话 Cookie 加固（全局 ini）──
# 放在 php/conf.d 下对每个 session_start() 生效，不必逐个入口文件去改。
#   cookie_httponly   —— 挡 XSS 偷会话（此前全仓库没有任何 httponly 设置）
#   cookie_samesite   —— 挡跨站请求携带会话（CSRF 的第二道防线）
#   use_strict_mode   —— 拒绝使用未经服务端初始化的 session id（防会话固定）
#   sid_length/bits   —— 会话 ID 熵从默认 128 bit 提到约 384 bit
# 不设 cookie_secure：这套面板默认跑在明文 HTTP 上（8080/5000），
# 打开 secure 会让浏览器直接不发送 Cookie，等于把登录打死。
RUN printf '%s\n' \
    'session.cookie_httponly=1' \
    'session.cookie_samesite=Lax' \
    'session.use_strict_mode=1' \
    'session.sid_length=64' \
    'session.sid_bits_per_character=6' \
    > /usr/local/etc/php/conf.d/zz-jasmin-session.ini

# Pass GIT_TOKEN as Apache env
RUN echo 'PassEnv GIT_TOKEN' >> /etc/apache2/conf-available/jasmin.conf

COPY docker/entrypoint-php.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 80
ENTRYPOINT ["/entrypoint.sh"]
