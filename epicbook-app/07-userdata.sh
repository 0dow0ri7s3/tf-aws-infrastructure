#!/bin/bash
set -e

# ─────────────────────────────────────────
# SYSTEM UPDATE
# ─────────────────────────────────────────
apt-get update -y
#apt-get upgrade -y

# ─────────────────────────────────────────
# INSTALL DEPENDENCIES
# ─────────────────────────────────────────
apt-get install -y nodejs npm git nginx mysql-client

# ─────────────────────────────────────────
# CLONE THE APP
# ─────────────────────────────────────────
cd /home/ubuntu
git clone https://github.com/pravinmishraaws/theepicbook.git
cd theepicbook

# ─────────────────────────────────────────
# CREATE .env FILE
# ─────────────────────────────────────────
cat > .env <<EOF
DB_HOST=${db_host}
DB_USER=${db_username}
DB_PASSWORD=${db_password}
DB_NAME=${db_name}
DB_PORT=${db_port}
PORT=${app_port}
EOF

# ─────────────────────────────────────────
# UPDATE config.json WITH RDS CREDENTIALS
# This overrides the hardcoded localhost values
# ─────────────────────────────────────────
cat > config/config.json <<EOF
{
  "development": {
    "username": "${db_username}",
    "password": "${db_password}",
    "database": "${db_name}",
    "host": "${db_host}",
    "dialect": "mysql"
  },
  "test": {
    "username": "root",
    "password": null,
    "database": "database_test",
    "host": "127.0.0.1",
    "dialect": "mysql"
  },
  "production": {
    "username": "${db_username}",
    "password": "${db_password}",
    "database": "${db_name}",
    "host": "${db_host}",
    "dialect": "mysql"
  }
}
EOF

# ─────────────────────────────────────────
# INSTALL APP DEPENDENCIES
# ─────────────────────────────────────────
npm install

# ─────────────────────────────────────────
# WAIT FOR RDS TO BE FULLY READY
# RDS takes time to accept connections after provisioning
# ─────────────────────────────────────────
echo "Waiting for RDS to be ready..."
for i in {1..30}; do
  if mysqladmin ping -h "${db_host}" -u "${db_username}" -p"${db_password}" --silent 2>/dev/null; then
    echo "RDS is ready"
    break
  fi
  echo "Attempt $i — waiting 10 seconds..."
  sleep 10
done

# ─────────────────────────────────────────
# CREATE DATABASE AND IMPORT SQL DUMPS
# ─────────────────────────────────────────
mysql -h "${db_host}" -u "${db_username}" -p"${db_password}" \
  -e "CREATE DATABASE IF NOT EXISTS ${db_name};"

mysql -h "${db_host}" -u "${db_username}" -p"${db_password}" "${db_name}" \
  < /home/ubuntu/theepicbook/db/BuyTheBook_Schema.sql

mysql -h "${db_host}" -u "${db_username}" -p"${db_password}" "${db_name}" \
  < /home/ubuntu/theepicbook/db/author_seed.sql

mysql -h "${db_host}" -u "${db_username}" -p"${db_password}" "${db_name}" \
  < /home/ubuntu/theepicbook/db/books_seed.sql

echo "Database seeded successfully"

# ─────────────────────────────────────────
# INSTALL PM2 AND START APP
# ─────────────────────────────────────────
npm install -g pm2

# Start as ubuntu user not root
sudo -u ubuntu bash -c "cd /home/ubuntu/theepicbook && pm2 start npm --name 'epicbook' -- start"
sudo -u ubuntu bash -c "pm2 save"

# Set pm2 to start on reboot
env PATH=$PATH:/usr/bin pm2 startup systemd -u ubuntu --hp /home/ubuntu
systemctl enable pm2-ubuntu

# ─────────────────────────────────────────
# CONFIGURE NGINX REVERSE PROXY
# ─────────────────────────────────────────
cat > /etc/nginx/sites-available/epicbook <<'NGINXCONF'
server {
  listen 80;
  server_name _;

  location / {
    proxy_pass http://127.0.0.1:8080;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
  }
}
NGINXCONF

ln -sf /etc/nginx/sites-available/epicbook /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl restart nginx
systemctl enable nginx

echo "EpicBook deployment complete"