FROM php:8.2-apache

RUN apt-get update && apt-get install -y --no-install-recommends git unzip rsync libzip-dev \
    && rm -rf /var/lib/apt/lists/* \
    && docker-php-ext-install pdo pdo_mysql \
    && pecl install redis && docker-php-ext-enable redis \
    && a2enmod rewrite \
    && a2enmod headers

RUN echo '<Directory /var/www/html>\n    AllowOverride All\n    Require all granted\n</Directory>' > /etc/apache2/conf-available/jasmin.conf \
    && a2enconf jasmin

COPY ["Web Panel/", "/var/www/html/"]
COPY ["VERSION", "/var/www/html/VERSION"]

RUN rm -f /var/www/html/.installed /var/www/html/.env \
    && chown -R www-data:www-data /var/www/html \
    && chmod -R 755 /var/www/html \
    && mkdir -p /var/www/html/payloads /var/www/html/passwords \
    && chown www-data:www-data /var/www/html/payloads /var/www/html/passwords

# Pass GIT_TOKEN as Apache env
RUN echo 'PassEnv GIT_TOKEN' >> /etc/apache2/conf-available/jasmin.conf

COPY docker/entrypoint-php.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 80
ENTRYPOINT ["/entrypoint.sh"]
