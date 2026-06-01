# All-in-one: WordPress (Apache+PHP) + MariaDB in ONE container, managed by supervisord.
FROM wordpress:php8.2-apache

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        mariadb-server mariadb-client supervisor curl; \
    rm -rf /var/lib/apt/lists/*; \
    mkdir -p /run/mysqld /var/log/supervisor; \
    chown -R mysql:mysql /run/mysqld

# MariaDB listens on 5054 inside the container (and is published to host 5054),
# so it never collides with Webuzo's MySQL on 3306.
# Host networking: Apache must listen on 5053, NOT 80 (NPM owns 80 on the host).
RUN sed -ri 's/^Listen 80$/Listen 5053/' /etc/apache2/ports.conf; \
    sed -ri 's/<VirtualHost \*:80>/<VirtualHost *:5053>/' /etc/apache2/sites-available/000-default.conf

COPY docker/mariadb-port.cnf      /etc/mysql/mariadb.conf.d/99-aio.cnf
COPY docker/supervisord.conf      /etc/supervisor/conf.d/aio.conf
COPY docker/entrypoint.sh         /usr/local/bin/aio-entrypoint.sh
COPY docker/start-apache.sh       /usr/local/bin/start-apache.sh
RUN chmod +x /usr/local/bin/aio-entrypoint.sh /usr/local/bin/start-apache.sh

EXPOSE 5053 5054
ENTRYPOINT ["/usr/local/bin/aio-entrypoint.sh"]
