#!/bin/bash

# ==========================================
# USER VARIABLES - UPDATE THIS!
# ==========================================
# Your external drive mount point/backup folder
BACKUP_DIR="/mnt/ssd/server_config/nextcloud/next_backup"

# Number of days to keep old backups
DAYS_TO_KEEP=7

# ==========================================
# DO NOT EDIT BELOW THIS LINE
# ==========================================
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
CURRENT_BACKUP_PATH="$BACKUP_DIR/backup_$TIMESTAMP"

echo "Starting Nextcloud AIO backup: $TIMESTAMP"

# 1. Create the backup directory
mkdir -p "$CURRENT_BACKUP_PATH"

# 2. Enable Maintenance Mode
echo "Enabling Maintenance Mode..."
docker exec --user www-data nextcloud-aio-nextcloud php occ maintenance:mode --on

# 3. Extract Database Credentials dynamically from config.php
echo "Fetching DB credentials..."
DB_USER=$(docker exec --user www-data nextcloud-aio-nextcloud php -r 'include "/var/www/html/config/config.php"; echo $CONFIG["dbuser"];')
DB_PASS=$(docker exec --user www-data nextcloud-aio-nextcloud php -r 'include "/var/www/html/config/config.php"; echo $CONFIG["dbpassword"];')
DB_NAME=$(docker exec --user www-data nextcloud-aio-nextcloud php -r 'include "/var/www/html/config/config.php"; echo $CONFIG["dbname"];')

# 4. Backup the PostgreSQL Database
echo "Backing up database..."
docker exec -e PGPASSWORD="$DB_PASS" nextcloud-aio-database pg_dump -U "$DB_USER" -d "$DB_NAME" > "$CURRENT_BACKUP_PATH/nextcloud-db.sql"

# 5. Backup the Nextcloud Config Directory
echo "Backing up Nextcloud configuration..."
docker cp nextcloud-aio-nextcloud:/var/www/html/config "$CURRENT_BACKUP_PATH/config"

# 6. Backup the AIO Mastercontainer Volume (Crucial for AIO UI settings)
echo "Backing up AIO Mastercontainer settings..."
docker run --rm -v nextcloud_aio_mastercontainer:/volume -v "$CURRENT_BACKUP_PATH:/backup" alpine sh -c "tar -czf /backup/aio_mastercontainer.tar.gz -C /volume ."

# 7. Disable Maintenance Mode
echo "Disabling Maintenance Mode..."
docker exec --user www-data nextcloud-aio-nextcloud php occ maintenance:mode --off

# 8. Compress the backup to save space
echo "Compressing backup folder..."
cd "$BACKUP_DIR"
tar -czf "backup_$TIMESTAMP.tar.gz" "backup_$TIMESTAMP"
rm -rf "backup_$TIMESTAMP" 

# 9. Clean up old backups
echo "Cleaning up backups older than $DAYS_TO_KEEP days..."
find "$BACKUP_DIR" -name "backup_*.tar.gz" -type f -mtime +$DAYS_TO_KEEP -delete

echo "Backup completed successfully!"
