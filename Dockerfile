FROM php:8.0-fpm-alpine as php_base

RUN apk add --no-cache \
		acl \
		file \
		gettext \
		git \
        shadow \
	;

RUN set -eux; \
    apk add --no-cache --virtual .build-deps \
        $PHPIZE_DEPS \
        icu-dev \
        libzip-dev \
        zlib-dev \
        zip \
    ; \
    docker-php-ext-configure zip; \
    docker-php-ext-install -j$(nproc) \
        bcmath \
        zip \
    ; \
    pecl install apcu; \
    pecl clear-cache; \
    docker-php-ext-enable \
        apcu \
        opcache \
    ; \
    run_deps="$( \
		scanelf --needed --nobanner --format '%n#p' --recursive /usr/local/lib/php/extensions \
			| tr ',' '\n' \
			| sort -u \
			| awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
	)"; \
	apk add --no-cache --virtual .app-phpexts-rundeps ${run_deps}; \
	apk del .build-deps

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

RUN mv $PHP_INI_DIR/php.ini-production $PHP_INI_DIR/php.ini

RUN rm -Rf /usr/local/etc/php-fpm.d/*

COPY docker/php/conf.d/*.ini $PHP_INI_DIR/conf.d/
COPY docker/php/php-fpm.d/*.conf /usr/local/etc/php-fpm.d/

RUN mkdir -p /app && chown -R www-data:www-data /app /usr/local/etc/php-fpm.d/

ENV COMPOSER_ALLOW_SUPERUSER=1
ENV PATH="${PATH}:/root/.composer/vendor/bin"
ENV APP_ENV=prod

USER www-data

WORKDIR /app

FROM php_base as app

COPY --chown=www-data:www-data composer*.json symfony.lock ./

RUN set -eux; \
    composer install --prefer-dist --no-scripts --no-progress; \
    composer clear-cache

COPY --chown=www-data:www-data . .

RUN set -eux; \
    mkdir -p var/cache var/log; \
    composer dump-autoload --classmap-authoritative; \
    composer run-script post-install-cmd; \
    chmod +x bin/console; sync

FROM php_base as app-dev

USER root

RUN mv $PHP_INI_DIR/php.ini-development $PHP_INI_DIR/php.ini

ENV APP_ENV=dev

RUN usermod -u 1000 www-data && groupmod -g 1000 www-data

USER www-data

FROM nginx:1.21 AS web

COPY docker/nginx/conf.d/*.conf /etc/nginx/conf.d/

WORKDIR /app

COPY --chown=www-data:www-data public public