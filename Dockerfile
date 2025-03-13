FROM php:8.2-apache

LABEL org.opencontainers.image.source=https://github.com/AmozPay/docker-lamp

# Install packages
RUN apt-get update -y && apt-get install -y \
    wget \
    vim \
    mariadb-server mariadb-client \
  && rm -rf /var/cache/apt/archives /var/lib/apt/lists/*.


# Install phpmyadmin
RUN mkdir -p /usr/share/webapps/
RUN     cd /usr/share/webapps/ && \
  wget https://files.phpmyadmin.net/phpMyAdmin/5.2.1/phpMyAdmin-5.2.1-all-languages.tar.gz  && \
  tar zxvf phpMyAdmin-5.2.1-all-languages.tar.gz && \
  rm phpMyAdmin-5.2.1-all-languages.tar.gz && \
  mv phpMyAdmin-5.2.1-all-languages phpmyadmin && \
  chmod -R 755 /usr/share/webapps
RUN docker-php-ext-install mysqli pdo pdo_mysql && docker-php-ext-enable pdo_mysql

RUN cat > /var/www/html/info.php <<EOF
<?php
phpinfo();
?>
EOF

###
### INITIALISE PHPMYADMIN ON BOOT
###

RUN cat > /init_phpmyadmin.sh <<EOF
#!/bin/bash
if [ ! -d "/var/www/html/phpmyadmin" ]; then
    mv /usr/share/webapps/phpmyadmin/ /var/www/html/phpmyadmin
    mv /var/www/html/phpmyadmin/config.sample.inc.php /var/www/html/phpmyadmin/config.inc.php
    sed -i "s/\(\$cfg\['Servers'\]\[\\\$i\]\['host'\] = \)'localhost'/\1'127.0.0.1'/" /var/www/html/phpmyadmin/config.inc.php
fi
EOF
RUN chmod +x /init_phpmyadmin.sh

###
### INITIALISE MYSQL ON BOOT
###

RUN cat > /start_db.sh <<EOF
#!/bin/bash
set -e pipefail
mkdir -p /run/mysqld
chown -R mysql:mysql /run/mysqld

if [ ! -d "/var/lib/mysql/mysql" ]; then
    echo "Initializing MariaDB data directory..."
    mariadb-install-db --user=mysql --datadir=/var/lib/mysql
else
    echo "Existing database directory found, skipping initialization"
fi

# Start MariaDB properly
echo "Starting MariaDB..."
exec mariadbd --datadir=/var/lib/mysql --user=mysql --socket=/run/mysqld/mysqld.sock &
sleep 1

# Run initialization script if needed
if [ ! -f "/var/lib/mysql/.initialized" ]; then
    echo "Initializing databases..."
    echo "CREATE USER '\$MYSQL_USER'@localhost IDENTIFIED BY '\$MYSQL_PASSWORD';" | mysql -u root
    echo "GRANT ALL PRIVILEGES ON *.* TO '\$MYSQL_USER'@localhost IDENTIFIED BY '\$MYSQL_PASSWORD';" | mysql -u root
    touch /var/lib/mysql/.initialized
    echo "Databases initialized"
else
    echo "Found /var/lib/mysql/.initialized, skipping /init.sql"
fi
EOF

RUN chmod +x /start_db.sh

###
### SETUP ENTRYPOINT
###

RUN cat > /entrypoint.sh <<EOF
#!/bin/bash
set -euo pipefail
/init_phpmyadmin.sh
/start_db.sh &
exec apache2-foreground
EOF
RUN chmod +x /entrypoint.sh

# Port for apache and mysql
EXPOSE 80 3306
VOLUME /var/lib/mysql
VOLUME /var/www/html/sites

ENTRYPOINT [ "/entrypoint.sh" ]
