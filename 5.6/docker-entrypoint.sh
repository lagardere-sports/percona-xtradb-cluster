#!/usr/local/bin/dumb-init /bin/bash
set -e

# if command starts with an option, prepend mysqld
if [ "${1:0:1}" = '-' ]; then
	set -- mysqld "$@"
fi

if [ "$1" != 'mysqld' ]; then
	exec "$@"
	exit $?
fi

if [ -z "$CLUSTER_NAME" ]; then
	echo >&2 'Error:  You need to specify CLUSTER_NAME'
	exit 1
fi

DATADIR="$($@ --verbose --wsrep_on=OFF --help 2>/dev/null | awk '$1 == "datadir" { print $2; exit }')"

_initialize_database() {
	if [ -z "$MYSQL_ROOT_PASSWORD" -a -z "$MYSQL_ALLOW_EMPTY_PASSWORD" -a -z "$MYSQL_RANDOM_ROOT_PASSWORD" ]; then
		echo >&2 'error: database is uninitialized and password option is not specified '
		echo >&2 '  You need to specify one of MYSQL_ROOT_PASSWORD, MYSQL_ALLOW_EMPTY_PASSWORD and MYSQL_RANDOM_ROOT_PASSWORD'
		exit 1
	fi
	mkdir -p "$DATADIR"

	echo 'Running mysql_install_db'
	mysql_install_db --user=mysql --wsrep_on=OFF --datadir="$DATADIR" --rpm --keep-my-cnf
	echo 'Finished mysql_install_db'

	"$@" --user=mysql --datadir="$DATADIR" --skip-networking --wsrep_on=OFF &
	pid="$!"

	mysql=( mysql --protocol=socket -uroot )

	for i in {30..0}; do
		if echo 'SELECT 1' | "${mysql[@]}" &> /dev/null; then
			break
		fi
		echo 'MySQL init process in progress...'
		sleep 1
	done
	if [ "$i" = 0 ]; then
		echo >&2 'MySQL init process failed.'
		exit 1
	fi

	# sed is for https://bugs.mysql.com/bug.php?id=20545
	mysql_tzinfo_to_sql /usr/share/zoneinfo | sed 's/Local time zone must be set--see zic manual page/FCTY/' | "${mysql[@]}" mysql

	"${mysql[@]}" <<-EOSQL
		-- What's done in this file shouldn't be replicated
		--  or products like mysql-fabric won't work
		SET @@SESSION.SQL_LOG_BIN=0;
		CREATE USER 'root'@'%' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
		GRANT ALL ON *.* TO 'root'@'%' WITH GRANT OPTION ;
		ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
		CREATE USER 'xtrabackup'@'localhost' IDENTIFIED BY '$XTRABACKUP_PASSWORD';
		GRANT RELOAD,PROCESS,LOCK TABLES,REPLICATION CLIENT ON *.* TO 'xtrabackup'@'localhost';
		FLUSH PRIVILEGES;
	EOSQL
	mysql+=( -p"${MYSQL_ROOT_PASSWORD}" )

	echo "CREATE DATABASE IF NOT EXISTS \`$MYSQL_DATABASE\` ;" | "${mysql[@]}"
	mysql+=( "$MYSQL_DATABASE" )

	echo "CREATE USER '"$MYSQL_USER"'@'%' IDENTIFIED BY '"$MYSQL_PASSWORD"' ;" | "${mysql[@]}"
	echo "GRANT ALL ON \`"$MYSQL_DATABASE"\`.* TO '"$MYSQL_USER"'@'%' ;" | "${mysql[@]}"
	echo 'FLUSH PRIVILEGES ;' | "${mysql[@]}"

	if ! kill -s TERM "$pid" || ! wait "$pid"; then
		echo >&2 'MySQL init process failed.'
		exit 1
	fi
}

_recover_backup() {
	echo
	echo -n 'Recovering Backup...'

	curl "$BACKUP_URL" -# -o /tmp/mysql_backup.tar

	tar -xf /tmp/mysql_backup.tar -C /tmp
	tar -xzf /tmp/mediacenter_mysql/databases/MySQL.tar.gz -C /tmp
	rm -rf $DATADIR/*
	innobackupex --copy-back /tmp/MySQL.bkpdir

	cat > /tmp/init.sql <<-EOSQL
		DELETE FROM mysql.user ;

		CREATE USER 'root'@'%' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
		GRANT ALL ON *.* TO 'root'@'%' WITH GRANT OPTION ;
		ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
		CREATE USER 'xtrabackup'@'localhost' IDENTIFIED BY '$XTRABACKUP_PASSWORD';
		GRANT RELOAD,PROCESS,LOCK TABLES,REPLICATION CLIENT ON *.* TO 'xtrabackup'@'localhost';
		GRANT REPLICATION CLIENT ON *.* TO monitor@'%' IDENTIFIED BY 'monitor';
		GRANT PROCESS ON *.* TO monitor@localhost IDENTIFIED BY 'monitor';
		DROP DATABASE IF EXISTS test ;
		FLUSH PRIVILEGES;
	EOSQL

	echo 'Done'
	echo

	CLUSTER_JOIN=""
	INITARG=--init-file=/tmp/init.sql
}

if [ ! -e "$DATADIR/mysql" ]; then
	_initialize_database

	if [ ! -z "$BACKUP_URL" ]; then
		_recover_backup
	fi

	echo 'MySQL init process done.'
fi

chown -R mysql:mysql "$DATADIR"
exec "$@" --user=mysql --wsrep_cluster_name=$CLUSTER_NAME --wsrep_cluster_address="gcomm://$CLUSTER_JOIN" --wsrep_sst_method=xtrabackup-v2 --wsrep_sst_auth="xtrabackup:$XTRABACKUP_PASSWORD" --wsrep_node_address="$ipaddr" $INITARG
