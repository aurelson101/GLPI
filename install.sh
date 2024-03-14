#!/bin/bash

apt-get autoremove -y

# Installing Apache if not installed
echo "Installing Apache..."
apt-get update
apt-get install apache2 -y

# Installing required PHP extensions for GLPI
echo "Installing PHP extensions..."
apt-get install php-curl php-gd php-json php-mbstring php-mysql php-xml php-cli php-ldap php-zip php-intl php-bcmath php-imap -y

# Enabling required Apache modules
a2enmod rewrite ssl headers env dir mime

# Downloading and installing GLPI
echo "Downloading and installing GLPI..."
wget -P /tmp https://github.com/glpi-project/glpi/releases/download/10.0.14/glpi-10.0.14.tgz

tar -xzf /tmp/glpi-10.0.14.tgz -C /var/www/glpi --strip-components=1

chown -R www-data:www-data /var/www/glpi
chmod -R 775 /var/www/glpi

# Asking for database information
echo "Setting up MariaDB database for GLPI..."
read -p "Enter GLPI database name: " dbname
read -p "Enter GLPI database username: " dbuser
read -sp "Enter GLPI database user password: " dbpassword
echo
echo "Creating database and user..."
mysql -e "CREATE DATABASE ${dbname};"
mysql -e "CREATE USER '${dbuser}'@'localhost' IDENTIFIED BY '${dbpassword}';"
mysql -e "GRANT ALL PRIVILEGES ON ${dbname}.* TO '${dbuser}'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

# Installing MariaDB
apt-get install mariadb-server -y

# Asking for VirtualHost information
echo "Configuring the Apache web server..."
read -p "Enter the ServerAdmin email (e.g., webmaster@example.com): " serveradmin
read -p "Enter the ServerName (e.g., example.com): " servername

# Pre-configuring Apache VirtualHost for GLPI
VHOST_CONF="/etc/apache2/sites-available/glpi.conf"
echo "Creating VirtualHost configuration file for GLPI..."
cat > ${VHOST_CONF} << EOF
<VirtualHost *:80>
    ServerAdmin $serveradmin
    ServerName $servername
    DocumentRoot /var/www/glpi/public
    Redirect permanent / https://$servername
</VirtualHost>
EOF

a2ensite glpi
a2dissite 000-default.conf
systemctl reload apache2

# SSL configuration choice
echo "SSL Configuration..."
echo "1. Use Certbot (Let's Encrypt)"
echo "2. Configure manually"
read -p "Enter your choice (1 or 2): " ssl_choice

case $ssl_choice in
    1)
        echo "Installing Certbot and requesting SSL certificates..."
        apt-get install certbot python3-certbot-apache -y
        certbot --apache --non-interactive --agree-tos -m $serveradmin -d $servername --redirect
        # Certbot automatically adjusts the Apache configuration to use SSL
        ;;
    2)
        echo "Manual SSL configuration..."
        read -p "Enter the full path to the SSL certificate (.crt): " sslcertpath
        read -p "Enter the full path to the SSL private key (.key): " sslkeypath
        # Adding SSL configuration to the VirtualHost
        cat > ${VHOST_CONF} << EOF
<VirtualHost *:443>
    ServerAdmin $serveradmin
    ServerName $servername
    DocumentRoot /var/www/glpi/public
    SSLEngine on
    SSLCertificateFile $sslcertpath
    SSLCertificateKeyFile $sslkeypath
    <Directory /var/www/glpi/public>
        Require all granted
        RewriteEngine on
        RewriteCond %{REQUEST_FILENAME} !-f
        RewriteRule ^(.*)$ index.php [QSA,L]
    </Directory>
    ErrorLog \${APACHE_LOG_DIR}/glpi_error.log
    CustomLog \${APACHE_LOG_DIR}/glpi_access.log combined
</VirtualHost>
EOF
        a2enmod ssl
        systemctl restart apache2
        ;;
    *)
        echo "Invalid choice."
        exit 1
        ;;
esac

echo "Installation and configuration completed."
