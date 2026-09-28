FROM php:8.2-apache

RUN docker-php-ext-install pdo pdo_mysql \
    && a2enmod rewrite

COPY ./Web\ Panel/ /var/www/html/
RUN chown -R www-data:www-data /var/www/html \
    && chmod -R 755 /var/www/html \
    && mkdir -p /var/www/html/payloads /var/www/html/passwords \
    && chown www-data:www-data /var/www/html/payloads /var/www/html/passwords

EXPOSE 80
