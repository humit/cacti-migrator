# Cacti upgrade & migration script for ubuntu (Tested on Ubuntu 18.04)

`cacti-migrator.sh` script can backup a remote Cacti server via SSH connection.
The remote Cacti server's IP or FQDN MUST be specified in ORIG_CACTI_SERVER 
variable. Also the correct path for cacti webroot folder MUST be set as ORIG_CACTI_WEBROOT.

After the backup is complete, script will install the required packages from ubuntu repositories
and then download and install the `latest` version of cacti from https://www.cacti.net/downloads/cacti-latest.tar.gz

For the new cacti server the following variables must be set inside the script:

```
DB_USER="cacti_user"
DB_PASS="CACTI_PASSWORD"
DB_NAME="cacti"
DB_HOST="localhost"
DB_PORT="3306"
DB_ROOT_PASS="DB_ROOT_PASSWORD"
CACTI_USER="www-data"
CACTI_GRUP="www-data"
CACTI_WEBROOT="/usr/share/cacti/site"
```

The script also configures a local read-only snmp community specified with SNMP_RO_COMMUNITY. 
The snmp installation can be tested with the following command:

    ```
    sudo snmpwalk -v 2c -c ${SNMP_RO_COMMUNITY} localhost system
    ```

For debugging purposes you can check LOGFILE="/tmp/cacti-migrator.log".

