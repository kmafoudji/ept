#!/bin/bash
set -e

# Generate configs from dist templates if they don't exist
CONFIG_DIR="/var/www/ept/application/configs"

if [ ! -f "$CONFIG_DIR/application.ini" ]; then
    cp "$CONFIG_DIR/application.dist.ini" "$CONFIG_DIR/application.ini"

    # Apply environment variables to application.ini
    sed -i "s|^resources.db.params.host\s*=.*|resources.db.params.host = ${DB_HOST:-db}|" "$CONFIG_DIR/application.ini"
    sed -i "s|^resources.db.params.username\s*=.*|resources.db.params.username = ${DB_USER:-root}|" "$CONFIG_DIR/application.ini"
    sed -i "s|^resources.db.params.password\s*=.*|resources.db.params.password = ${DB_PASSWORD:-ept_secret}|" "$CONFIG_DIR/application.ini"
    sed -i "s|^resources.db.params.dbname\s*=.*|resources.db.params.dbname = ${DB_NAME:-ept}|" "$CONFIG_DIR/application.ini"
    sed -i "s|^domain\s*=.*|domain = ${APP_DOMAIN:-http://localhost/}|" "$CONFIG_DIR/application.ini"

    # Generate security salt
    SALT=$(openssl rand -hex 32)
    sed -i "s|^security.salt\s*=.*|security.salt = '${SALT}'|" "$CONFIG_DIR/application.ini"

    echo "Generated application.ini from template."
fi

# php.path: application.dist.ini points at /usr/bin/php (the Ubuntu package
# path). In this image PHP lives in /usr/local/bin, so every scheduled job
# (emails, evaluation, reports, certificates) failed with "php: not found".
# Point it at the PHP binary that is really here, on new and existing configs.
PHP_BIN="$(command -v php)"
CURRENT_PHP_PATH="$(sed -n 's|^php.path\s*=\s*"\{0,1\}\([^"]*\)"\{0,1\}\s*$|\1|p' "$CONFIG_DIR/application.ini" | head -n 1)"
if [ -n "$PHP_BIN" ] && { [ -z "$CURRENT_PHP_PATH" ] || [ ! -x "$CURRENT_PHP_PATH" ]; }; then
    if grep -q "^php.path" "$CONFIG_DIR/application.ini"; then
        sed -i "s|^php.path\s*=.*|php.path = \"${PHP_BIN}\"|" "$CONFIG_DIR/application.ini"
    else
        sed -i "0,/^\[production\]/s||[production]\nphp.path = \"${PHP_BIN}\"|" "$CONFIG_DIR/application.ini"
    fi
    echo "Set php.path to ${PHP_BIN}."
fi

# Optional mail trap for test and training instances. When EPT_MAIL_TRAP_DSN is
# set (for example smtp://mailpit:1025), every email goes to that catcher
# instead of real inboxes. The key lives in the [production] section, which the
# container runs, so it is set on the commented line the template ships with.
if [ -n "${EPT_MAIL_TRAP_DSN:-}" ]; then
    if grep -q "^email.devTrapDsn" "$CONFIG_DIR/application.ini"; then
        sed -i "s|^email.devTrapDsn\s*=.*|email.devTrapDsn = \"${EPT_MAIL_TRAP_DSN}\"|" "$CONFIG_DIR/application.ini"
    else
        sed -i "0,/^;email.devTrapDsn\s*=.*/s||email.devTrapDsn = \"${EPT_MAIL_TRAP_DSN}\"|" "$CONFIG_DIR/application.ini"
    fi
    echo "Mail trap enabled: ${EPT_MAIL_TRAP_DSN}"
fi

# Plain-HTTP test instances: docker/php.ini sends the session cookie only over
# HTTPS, so over http:// the browser drops it and login (captcha) always fails.
# Set EPT_INSECURE_HTTP=1 only for a local test box without TLS.
if [ "${EPT_INSECURE_HTTP:-0}" = "1" ]; then
    echo "session.cookie_secure = 0" > /usr/local/etc/php/conf.d/zz-insecure-http.ini
    echo "WARNING: session cookies allowed over plain HTTP (EPT_INSECURE_HTTP=1). Do not use in production."
else
    rm -f /usr/local/etc/php/conf.d/zz-insecure-http.ini
fi

if [ ! -f "$CONFIG_DIR/.env" ]; then
    echo "FORM_SECRET=$(openssl rand -hex 32)" > "$CONFIG_DIR/.env"
    echo "Generated .env with FORM_SECRET."
fi

# Wait for MySQL to be ready
echo "Waiting for MySQL..."
max_tries=30
count=0
until php -r "new PDO('mysql:host=${DB_HOST:-db};port=3306', '${DB_USER:-root}', '${DB_PASSWORD:-ept_secret}');" 2>/dev/null; do
    count=$((count + 1))
    if [ $count -ge $max_tries ]; then
        echo "MySQL not reachable after ${max_tries} attempts. Starting anyway..."
        break
    fi
    sleep 2
done
echo "MySQL is ready."

# Run migrations
echo "Running database migrations..."
cd /var/www/ept
composer post-update --no-interaction 2>&1 || echo "Migration warning (may be first run)."

# Run one-time scripts
php bin/run-once.php 2>/dev/null || true

# Ensure permissions. Includes application/configs because this entrypoint
# generates application.ini/config.ini/.env above as root — without this chown
# they stay root-owned and www-data (Apache) can't rewrite them, e.g. when the
# global-config admin page saves settings. Runs after config generation so the
# freshly-created files are covered. The volume-mounted dirs (uploads/logs/
# backups/downloads) are re-chowned here too since the mount masks the
# build-time ownership.
chown -R www-data:www-data application/configs application/cache logs downloads backups public/temporary public/uploads

# Start cron. The crontab (see Dockerfile) logs to logs/cron.log, which
# www-data can write and which persists on the logs volume.
touch logs/cron.log && chown www-data:www-data logs/cron.log
cron

exec "$@"
