FROM php:8.2-apache

RUN docker-php-ext-install pdo pdo_mysql \
    && a2enmod rewrite \
    && a2enmod headers

# Apache config for .htaccess
RUN echo '<Directory /var/www/html>\n    AllowOverride All\n    Require all granted\n</Directory>' > /etc/apache2/conf-available/jasmin.conf \
    && a2enconf jasmin

COPY ./Web\ Panel/ /var/www/html/

# Remove .installed to force install wizard on first run
RUN rm -f /var/www/html/.installed /var/www/html/.env \
    && chown -R www-data:www-data /var/www/html \
    && chmod -R 755 /var/www/html \
    && mkdir -p /var/www/html/payloads /var/www/html/passwords \
    && chown www-data:www-data /var/www/html/payloads /var/www/html/passwords

EXPOSE 80
