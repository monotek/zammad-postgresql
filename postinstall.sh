#!/bin/bash
#
# packager.io postinstall script
#

PATH=/opt/zammad/bin:/opt/zammad/vendor/bundle/bin:/sbin:/bin:/usr/sbin:/usr/bin:

ZAMMAD_DIR="/opt/zammad"
ZAMMAD_POSTGRESQL_DIR="/opt/zammad-postgresql"
DB="zammad_production"
DB_USER="zammad"

# check which init system is used
if [ -n "$(which initctl)" ]; then
    INIT_CMD="initctl"
elif [ -n "$(which systemctl)" ]; then
    INIT_CMD="systemctl"
else
    function sysvinit () {
	service $2 $1
    }
    INIT_CMD="sysvinit"
fi

# check if database.yml exists
if [ -f ${ZAMMAD_DIR}/database.yml ]; then
    # db migration
    echo "database.yml exists. Nothing to do..."
else
    # create new password
    DB_PASS="$(tr -dc A-Za-z0-9 < /dev/urandom | head -c10)"

    if [ -n "$(which postgresql-setup)" ]; then
	echo "preparing postgresql server"
	postgresql-setup initdb
	
	echo "backuping postgres config"
	test -f /var/lib/pgsql/data/pg_hba.conf.bak || cp /var/lib/pgsql/data/pg_hba.conf /var/lib/pgsql/data/pg_hba.conf.bak

	echo "allow login via username and password in postgresql"
	egrep -v "^#.*$" < /var/lib/pgsql/data/pg_hba.conf.bak | sed 's/ident/trust/g' > /var/lib/pgsql/data/pg_hba.conf

	echo "restarting postgresql server"
	${INIT_CMD} restart postgresql

	echo "create postgresql bootstart"
	${INIT_CMD} enable postgresql.service
    fi

    # create database
    echo "# database.yml not found. Creating new db..."
    su - postgres -c "createdb -E UTF8 ${DB}"

    # create postgres user
    echo "CREATE USER \"${DB_USER}\" WITH PASSWORD '${DB_PASS}';" | su - postgres -c psql 

    # grant privileges
    echo "GRANT ALL PRIVILEGES ON DATABASE \"${DB}\" TO \"${DB_USER}\";" | su - postgres -c psql

    # update configfile
    sed "s/.*password:.*/  password: ${DB_PASS}/" < ${ZAMMAD_POSTGRESQL_DIR}/database.psql > ${ZAMMAD_POSTGRESQL_DIR}/database.yml
fi

