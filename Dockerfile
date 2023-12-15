FROM ubuntu:22.04

ENV PACKAGES="openjdk-11-jdk apt-transport-https curl vim golang-go git subversion mysql-client php8.2 php8.2-memcached php8.2-mysql php8.2-intl php8.2-redis php8.2-xdebug php8.2-bcmath php8.2-gd php8.2-soap php8.2-zip"
ENV PHP_CONFIG_PATH=/etc/php/8.2
ENV GLOBAL_PATH=/usr/local/bin
ENV DB_PASSWORD="p@ssw0rd1"

# Fix debconf warnings upon build
ARG DEBIAN_FRONTEND=noninteractive

# Add PHP Repository
RUN apt-get update && \
    apt-get install -y software-properties-common && \
    add-apt-repository ppa:ondrej/php

RUN apt-get update
RUN apt-get -y --no-install-recommends install $PACKAGES \
    && apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /usr/share/doc/*

# Configure
COPY conf/php.ini $PHP_CONFIG_PATH/fpm/
COPY conf/php.ini $PHP_CONFIG_PATH/cli/
COPY conf/php-fpm.conf $PHP_CONFIG_PATH/fpm/

RUN mkdir -p /var/www/html

### Install sendmail for use with mailhog
ENV GOPATH /tmp
RUN cd /tmp \
    && go install github.com/mailhog/mhsendmail@v0.2.0 \
    && cp /tmp/bin/mhsendmail /usr/local/bin

#Install and configure PHPCS
RUN curl -L https://squizlabs.github.io/PHP_CodeSniffer/phpcs.phar -o $GLOBAL_PATH/phpcs \
    && chmod +x $GLOBAL_PATH/phpcs

# Install MYSQL
RUN echo "mariadb-server-11.2 mysql-server/root_password password $DEFAULTPASS" | debconf-set-selections
RUN echo "mariadb-server-11.2 mysql-server/root_password_again password $DEFAULTPASS" | debconf-set-selections
RUN mkdir -p /etc/apt/keyrings && \
    curl -o /etc/apt/keyrings/mariadb-keyring.pgp 'https://mariadb.org/mariadb_release_signing_key.pgp'

COPY mariadb.sources /etc/apt/sources.list.d

RUN apt-get update && \
    apt-get install -y mariadb-server
    
RUN service mariadb start &&\
    mariadb -uroot -p$DB_PASSWORD -e 'CREATE DATABASE magento2;'

HEALTHCHECK --start-period=5m \
  CMD mariadb -e 'SELECT @@datadir;' || exit 1


# INSTALL ELASTICSEARCH
RUN curl -LO https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-7.14.0-amd64.deb

RUN dpkg -i elasticsearch-7.14.0-amd64.deb

RUN cat /etc/elasticsearch/elasticsearch.yml && \
    sed /# network.host/network.host /etc/elasticsearch/elasticsearch.yml && \
    cat /etc/elasticsearch/elasticsearch.yml

RUN service elasticsearch start

# INSTALL MAGENTO
RUN curl -LO https://github.com/magento/magento2/archive/refs/tags/2.4.6-p3.zip && \
    unzip -qq 2.4.6-p3.zip && \
    mv magento2-2.4.6-p3 magento2 && \
    rm -rf 2.4.6-p3.zip

RUN cd magento2 && \
    composer require mp-plugins/php-sdk && \
    composer update && \
    composer install

RUN service mariadb start && \
    service mariadb status && \
    cd magento2 && \
    ./bin/magento setup:install \
        --base-url=https://magento2.ppolimpo.io \
        --db-host=localhost \
        --db-name=magento2 \
        --db-user=root \
        --db-password=$DB_PASSWORD \
        --db-prefix=m_ \
        --admin-firstname=Nome \
        --admin-lastname=Sobrenome \
        --admin-email=meu@email.com \
        --admin-user=admin \
        --admin-password=1234qwer \
        --backend-frontname=admin \
        --language=pt_BR \
        --currency=BRL \
        --timezone=America/Sao_Paulo \
        --use-rewrites=1
