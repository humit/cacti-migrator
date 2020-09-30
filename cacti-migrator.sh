#!/bin/sh

## This script should be run in the server where you want to migrate & upgrade
## a cacti server.

## It will backup an existing CACTI installation
## from ${ORIG_CACTI_SERVER}:${ORIG_CACTI_WEBROOT} folder.

## It installs latest cacti version and migrates backed up data
## to this server resulting an upgraded migration.

set -ex


version=0.1

## -- DO NOT FORGET TO CHECK
## -- FOLLOWING PARAMETERS FROM
## -- THE ORIGINAL CACTI SERVER
## -- AND CORRECT THEM

ORIG_CACTI_SERVER="SOURCE_CACTI_SERVER_IP"
ORIG_CACTI_WEBROOT="/opt/cacti"
ORIG_CACTI_CONFIG="${ORIG_CACTI_WEBROOT}/include/config.php"
ORIG_CACTI_BACKUP="/root/cacti-backup"
ORIG_BACKUP_FILE="cacti-backup.tar.gz"
ORIG_BACKUP_PATH="/root/${ORIG_BACKUP_FILE}"

## -- THE NEW CACTI SERVER WILL BE
## -- CONFIGURED WITH THE FOLLOWING
## -- PARAMETERS

DB_USER="cacti_db_user"
DB_PASS="cacti_db_pass"
DB_NAME="cacti"
DB_HOST="localhost"
DB_PORT="3306"
DB_ROOT_PASS="none"
CACTI_USER="www-data"
CACTI_GRUP="www-data"
CACTI_WEBROOT="/usr/share/cacti/site"

SNMP_RO_COMMUNITY="CHANGEME"

## -- UNDER NORMAL OPERATION THERE SHOULD BE
## -- NO NEED TO CHANGE ANYTHING BELOW THIS LINE

SRC_DIR="/root/src"
CACTI_LATEST_TAR="${SRC_DIR}/cacti-latest.tar.gz"
CACTI_MIGRAT_TAR="${SRC_DIR}/${ORIG_BACKUP_FILE}"
CACTI_MIGRAT_DIR="/root/cacti-backup"
CACTI_MIGRAT_SQL_FILE="cacti-orig.sql"
CACTI_MIGRAT_SQL_PATH="${CACTI_MIGRAT_DIR}/${CACTI_MIGRAT_SQL_FILE}"
CACTI_INIT_SQL="${CACTI_WEBROOT}/cacti.sql"
LASTFUNC="main"
LOGFILE="/tmp/cacti-migrator.log"

mklog(){
    echo "$(date)"  ${LASTFUNC}: "$@" | tee -a ${LOGFILE}
}


prepare_dirs(){
    echo "DELETING FOLDERS: ${CACTI_WEBROOT} ${CACTI_MIGRAT_DIR}"
    echo "HIT CTRL+C TO QUIT or ENTER to continue"
    read
    rm -rf "${CACTI_WEBROOT}" "${CACTI_MIGRAT_DIR}"
    mkdir -p "${SRC_DIR}" "${CACTI_WEBROOT}" "${CACTI_MIGRAT_DIR}"
}

## -- Configure ssh access to the ORIGINAL CACTI server
config_ssh(){
    LASTFUNC=${FUNCNAME[0]}
    if ! [ -f /root/.ssh/id_rsa.pub ];then
     mklog "Creating ssh keys"
     mkdir /root/.ssh && chmod 700 /root/.ssh
     ssh-keygen -t rsa && chmod -R go-rwx /root/.ssh
    fi

    mklog "Transferring ssh public key to root@${ORIG_CACTI_SERVER}"
    mklog "Please enter root password for root@${ORIG_CACTI_SERVER}"
    ssh-copy-id -i /root/.ssh/id_rsa.pub root@${ORIG_CACTI_SERVER}
}

get_orig_db_cfg(){
    ORIG_DB_CFG=$(ssh -t root@${ORIG_CACTI_SERVER} "egrep '^\\\$database_(default|username|password|hostname|port)' ${ORIG_CACTI_CONFIG}")
    ORIG_DB_NAME=$(echo "${ORIG_DB_CFG}"|grep _default|cut -d \' -f 2)
    ORIG_DB_HOST=$(echo "${ORIG_DB_CFG}"|grep _hostname|cut -d \' -f 2)
    ORIG_DB_USER=$(echo "${ORIG_DB_CFG}"|grep _username|cut -d \' -f 2)
    ORIG_DB_PASS=$(echo "${ORIG_DB_CFG}"|grep _password|cut -d \' -f 2)
    ORIG_DB_PORT=$(echo "${ORIG_DB_CFG}"|grep _port|cut -d \' -f 2)
}

create_backup(){
    ## --  Get connection parameters for the original cacti database
    get_orig_db_cfg

    mklog "Creating backup on ORIGINAL server and transferring to this server"
    ssh root@${ORIG_CACTI_SERVER} "mkdir -p ${ORIG_CACTI_BACKUP} ${ORIG_CACTI_BACKUP}/site"

    mklog "Creating mysql backup"
    ssh root@${ORIG_CACTI_SERVER} "mysqldump --opt -u${ORIG_DB_USER} -p${ORIG_DB_PASS} -h${ORIG_DB_HOST} -P${ORIG_DB_PORT} ${ORIG_DB_NAME} > ${ORIG_CACTI_BACKUP}/${CACTI_MIGRAT_SQL_FILE}"

    mklog "Creating Cacti backup"
    ssh root@${ORIG_CACTI_SERVER} "cp -a ${ORIG_CACTI_WEBROOT}/rra ${ORIG_CACTI_WEBROOT}/scripts ${ORIG_CACTI_WEBROOT}/resource ${ORIG_CACTI_BACKUP}/site"
    ssh root@${ORIG_CACTI_SERVER} "tar cvfz ${ORIG_BACKUP_PATH} ${ORIG_CACTI_BACKUP}"
    scp root@${ORIG_CACTI_SERVER}:${ORIG_BACKUP_PATH} ${SRC_DIR}
    mklog "Migration file successfully transferred to ${ORIG_CACTI_SERVER}:${SRC_DIR}"
}

## - Install required packages
apt_install(){
LASTFUNC=${FUNCNAME[0]}

apt update && apt upgrade -y && \
apt install -y php php-mysql php-curl php-net-socket php-gd php-intl \
                     php-pear php-imap php-memcache libapache2-mod-php \
                     php-pspell php-recode php-tidy php-xmlrpc php-snmp \
                     php-mbstring php-gettext php-gmp php-json php-xml \
                     php-common sendmail-bin cacti cacti-spine apache2 \
                     percona-toolkit mariadb-server snmp snmpd \
                     snmp-mibs-downloader rrdtool
}

## -- Configure php for apache and cli
config_php(){
LASTFUNC=${FUNCNAME[0]}

sed -i s/^\;date\.timezone\ =$/date.timezone\ =\ Asia\\/Beirut/ \
       /etc/php/7.2/apache2/php.ini
sed -i -e "s/memory_limit.*/memory_limit=512M/g" \
            -e "s/max_execution_time.*/max_execution_time=60/g" \
            /etc/php/7.2/apache2/php.ini

sed -i s/^\;date\.timezone\ =$/date.timezone\ =\ Asia\\/Beirut/ \
       /etc/php/7.2/cli/php.ini
sed -i -e "s/memory_limit.*/memory_limit=512M/g" \
            -e "s/max_execution_time.*/max_execution_time=60/g" \
            /etc/php/7.2/cli/php.ini
}

config_snmp(){
## -- Configure snmpd
sed -i s/^mibs\ :/\#\ mibs\ :/ /etc/snmp/snmp.conf
sed -i s/^rocommunity.*/rocommunity\ CactIsnmp\ localhost/ /etc/snmp/snmpd.conf
echo rocommunity ${SNMP_RO_COMMUNITY} localhost >> /etc/snmp/snmpd.conf
}

config_mysql(){
LASTFUNC=${FUNCNAME[0]}

cat << EOF > /etc/mysql/mariadb.conf.d/cacti.cnf
[mysqld]
collation_server=utf8mb4_unicode_ci
max_heap_table_size=512M
tmp_table_size=128M
join_buffer_size=250M
innodb_buffer_pool_size=1947M
innodb_buffer_pool_instances=16
innodb_doublewrite=ON
innodb_flush_log_at_timeout=3
innodb_read_io_threads=32
innodb_write_io_threads=16
innodb_additional_mem_pool_size=80M
innodb_file_format=Barracuda
innodb_large_prefix=1
innodb_io_capacity=5000
innodb_io_capacity_max=10000
innodb_default_row_format=dynamic
EOF

}

cleanup(){
LASTFUNC=${FUNCNAME[0]}

    mklog "Cleanup..."
#    rm -rf "${SRC_DIR}" "${CACTI_WEBROOT}" "${CACTI_MIGRAT_DIR}"
#     rm -rf "${CACTI_WEBROOT}" "${CACTI_MIGRAT_DIR}"
}


## -- Create and migrate cacti db
create_db(){
LASTFUNC=${FUNCNAME[0]}


do_db(){
LASTFUNC=${FUNCNAME[0]}

mklog "Waiting for mysqld to run"

## -- wait for database to initialize - http://stackoverflow.com/questions/4922943/test-from-shell-script-if-remote-tcp-port-is-open
while ! timeout 1 bash -c "cat < /dev/null > /dev/tcp/localhost/${DB_PORT}"; do mklog "Waiting for database port connection"; sleep 1; done
while ! mysql -uroot -p${DB_ROOT_PASS} -e "show variables like '%VERSION%'"; do mklog "Waiting for successful SQL execution"; sleep 1; done
mklog "Database is up, continuing..."

mklog "Set mysql timezone"
mysql_tzinfo_to_sql /usr/share/zoneinfo|/usr/bin/mysql -uroot -p${DB_ROOT_PASS} mysql

mklog "Drop & Create cacti database and grant rights"

if [ $(mysql -uroot -e "SHOW DATABASES\G"|grep -wq cacti) ]; then /usr/bin/mysql -uroot -p${DB_ROOT_PASS} -e "DROP DATABASE cacti"; fi
/usr/bin/mysql -uroot -p${DB_ROOT_PASS} -e "CREATE DATABASE cacti"

mklog "Grant user rights"
/usr/bin/mysql -uroot -p${DB_ROOT_PASS} -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO ${DB_USER}@'localhost' IDENTIFIED BY '${DB_PASS}'"
/usr/bin/mysql -uroot -p${DB_ROOT_PASS} -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO ${DB_USER}@'%' IDENTIFIED BY '${DB_PASS}'"
/usr/bin/mysql -uroot -p${DB_ROOT_PASS} -e "GRANT SELECT ON mysql.time_zone_name TO ${DB_USER}@'%';"
/usr/bin/mysql -uroot -p${DB_ROOT_PASS} -e "FLUSH PRIVILEGES"

if [ -f ${CACTI_DB_FILE} ];
 then
    mklog "Restoring database \"${DB_NAME}\" from \"${CACTI_DB_FILE}\" file"
    cat ${CACTI_DB_FILE} |  /usr/bin/mysql -uroot --password="${DB_ROOT_PASS}" "${DB_NAME}"
 else
    mklog "DB file ${CACTI_DB_FILE} does not exist"
fi
}

config_cacti_on_db(){
LASTFUNC=${FUNCNAME[0]}
    mklog "Initial configuration changes on cacti db"
     /usr/bin/mysql -uroot -p${DB_ROOT_PASS} ${DB_NAME} -e "UPDATE settings SET value='/var/log/cacti/cacti.log' WHERE name='path_cactilog'"
     /usr/bin/mysql -uroot -p${DB_ROOT_PASS} ${DB_NAME} -e "UPDATE settings SET value='/var/log/cacti/cacti_stderr.log' WHERE name='path_stderrlog'"
     /usr/bin/mysql -uroot -p${DB_ROOT_PASS} ${DB_NAME} -e "UPDATE settings SET value='/var/log/cacti/cacti_stderr.log' WHERE name='path_stderrrlog'"
     /usr/bin/mysql -uroot -p${DB_ROOT_PASS} ${DB_NAME} -e "UPDATE settings SET value='${CACTI_WEBROOT}' WHERE name='path_webroot'"
     /usr/bin/mysql -uroot -p${DB_ROOT_PASS} ${DB_NAME} -e "UPDATE settings SET value='/var/lib/cacti/cache/boost' WHERE name='boost_png_cache_directory'"
     /usr/bin/mysql -uroot -p${DB_ROOT_PASS} ${DB_NAME} -e "UPDATE settings SET value='/var/lib/cacti/cache/realtime' WHERE name='realtime_cache_path'"
     /usr/bin/mysql -uroot -p${DB_ROOT_PASS} ${DB_NAME} -e "UPDATE settings SET value='/var/lib/cacti/cache/spikekill' WHERE name='spikekill_backupdir'"
     /usr/bin/mysql -uroot -p${DB_ROOT_PASS} ${DB_NAME} -e "UPDATE settings SET value='/usr/sbin/spine' WHERE name='path_spine'"
     /usr/bin/mysql -uroot -p${DB_ROOT_PASS} ${DB_NAME} -e "UPDATE settings SET value='/etc/cacti/spine.conf' WHERE name='path_spine_config'"
     /usr/bin/mysql -uroot -p${DB_ROOT_PASS} ${DB_NAME} -e "UPDATE settings SET value='2' WHERE name='poller_type'"
}

# -- Fix file permissions
config_perms(){
mklog "Change file permissions and ownership"
find /usr/share/cacti -type d -exec chmod ug+x {} \;
chown -R root:root ${CACTI_WEBROOT}
chown -R www-data:www-data ${CACTI_WEBROOT}/rra
chmod -R ug+rw ${CACTI_WEBROOT}/rra
chown -R www-data.www-data /var/log/cacti /var/log/apache2 /var/lib/cacti
chown -R www-data.www-data ${CACTI_WEBROOT}/log
chown -R www-data.www-data ${CACTI_WEBROOT}/cache/boost
chown -R www-data.www-data ${CACTI_WEBROOT}/cache/mibcache
chown -R www-data.www-data ${CACTI_WEBROOT}/cache/realtime
chown -R www-data.www-data ${CACTI_WEBROOT}/cache/spikekill

# Temporarily writable during installation
mklog "Following folders should be readonly after installation"
chown -R www-data.www-data ${CACTI_WEBROOT}/resource
chown -R www-data.www-data ${CACTI_WEBROOT}/resource/snmp_queries/
chown -R www-data.www-data ${CACTI_WEBROOT}/resource/script_server/
chown -R www-data.www-data ${CACTI_WEBROOT}/resource/script_queries/
chown -R www-data.www-data ${CACTI_WEBROOT}/scripts/
chmod -R ug+rwx ${CACTI_WEBROOT}/resource/s*
chmod -R ug+rwx ${CACTI_WEBROOT}/scripts/*
}

## -- Test if $1 is set https://stackoverflow.com/questions/3601515/how-to-check-if-a-variable-is-set-in-bash
if ! [ -z ${1+x} ]; then

    if [ $1 == "migrate" ]; then
        mklog "Cacti db will be migrated"
        CACTI_DB_FILE=${CACTI_MIGRAT_SQL_PATH}
        do_db
        config_cacti_on_db
    elif [ $1 == "init" ] ; then
        mklog "Cacti db will be initialized"
        CACTI_DB_FILE=${CACTI_INIT_SQL}
        do_db
    else
        mklog "Unknown action \"$1\", quitting"
    fi
else mklog "Must provide \"migrate\" or \"init\" option, quitting" 
fi
}

## -- Install new fresh cacti
install_cacti(){
LASTFUNC=${FUNCNAME[0]}

    mklog "Delete existing cacti"
    rm -rf "${CACTI_WEBROOT}"
    mkdir -p "${CACTI_WEBROOT}"
    mklog "Extract latest cacti version"
    wget https://www.cacti.net/downloads/cacti-latest.tar.gz -O ${SRC_DIR}/cacti-latest.tar.gz
    tar -zxf ${CACTI_LATEST_TAR} --strip-components=1 -C "${CACTI_WEBROOT}"
}


migrate_cacti(){
LASTFUNC=${FUNCNAME[0]}
## -- Get latest cacti
    wget https://www.cacti.net/downloads/cacti-latest.tar.gz -O ${SRC_DIR}/cacti-latest.tar.gz
    tar -zxf ${CACTI_LATEST_TAR} --strip-components=1 -C "${CACTI_WEBROOT}"
    tar -zxf ${CACTI_MIGRAT_TAR} --strip-components=2 -C "${CACTI_MIGRAT_DIR}" 

## -- Fix permissions of migrated files
    chmod -R a-ts "${CACTI_MIGRAT_DIR}"
    chmod -R o-rwx "${CACTI_MIGRAT_DIR}"
    find "${CACTI_MIGRAT_DIR}" -type d -exec chmod ug+rx {} \;
    chown -R ${CACTI_USER}:${CACTI_GRUP} "${CACTI_MIGRAT_DIR}"

## -- Copy migrated files
    for i in resource rra scripts;
     do
        rsync -a --ignore-existing "${CACTI_MIGRAT_DIR}/site/${i}/" "${CACTI_WEBROOT}/${i}/"
     done
}


## -- Configure spine
config_spine(){
LASTFUNC=${FUNCNAME[0]}
mklog "Configure spine /etc/cacti/spine.conf"
sed -i s/^DB_User.*/DB_User\ ${DB_USER}/ /etc/cacti/spine.conf
sed -i s/^DB_Pass.*/DB_Pass\ ${DB_PASS}/ /etc/cacti/spine.conf
sed -i s/^DB_Host.*/DB_Host\ ${DB_HOST}/ /etc/cacti/spine.conf
sed -i s/^DB_Port.*/DB_Port\ ${DB_PORT}/ /etc/cacti/spine.conf
}

## -- Configure cacti
config_cacti(){
mklog "Configure cacti "
sed -i s/\$database_username\ =.*/\$database_username\ =\ \'${DB_USER}\'\;/ \
          ${CACTI_WEBROOT}/include/config.php
sed -i s/\$database_password\ =.*/\$database_password\ =\ \'${DB_PASS}\'\;/ \
          ${CACTI_WEBROOT}/include/config.php
sed -i s/\$database_hostname\ =.*/\$database_hostname\ =\ \'${DB_HOST}\'\;/ \
          ${CACTI_WEBROOT}/include/config.php
sed -i s/localhost/${DB_HOST}/ ${CACTI_WEBROOT}/include/global.php
}

install_info(){

mklog "Please go to http://185.118.24.6/cacti and follow the instructions."
mklog "WARNING!!! After the installation is complete, please run the following commands"
mklog "to avoid security risks"

echo "## ----------------------------------------------"
echo
echo chown -R root:root /usr/share/cacti/site/resource
echo                    /usr/share/cacti/site/scripts

echo chmod -R a-w /usr/share/cacti/site/resource
echo              /usr/share/cacti/site/scripts
echo
echo "## ----------------------------------------------"

}

prepare_dirs
# Create backup on ORIGINAL SERVER and TRANSFER here
config_ssh
create_backup

apt_install
config_php
config_mysql
systemctl restart mysql
migrate_cacti
create_db migrate
config_perms
config_spine
config_cacti
config_snmp

systemctl restart apache2 || systemctl start apache2
systemctl restart mariadb || systemctl start mariadb
systemctl start snmpd || systemctl start  snmpd

systemctl enable apache2
systemctl enable mariadb
systemctl enable snmpd

install_info
