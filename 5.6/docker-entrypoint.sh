#!/usr/local/bin/dumb-init /bin/bash
set -eo pipefail
shopt -s nullglob

_initialize_database() {
	if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
		echo >&2 'error: You need to specify MYSQL_ROOT_PASSWORD.'
		exit 1
	fi
	mkdir -p "$DATADIR"

	echo 'Running mysql_install_db'
	mysql_install_db --user=mysql --wsrep_on=OFF --datadir="$DATADIR" --rpm --keep-my-cnf
	chown -R mysql:mysql "$DATADIR"
	echo 'Finished mysql_install_db'

	"$@" --no-defaults --user=mysql --datadir="$DATADIR" --skip-networking --wsrep_on=OFF &
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
		SET @@SESSION.SQL_LOG_BIN=0;

		DELETE FROM mysql.user ;
		CREATE USER 'root'@'%' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
		GRANT ALL ON *.* TO 'root'@'%' WITH GRANT OPTION ;

		CREATE USER 'xtrabackup'@'localhost' IDENTIFIED BY '$XTRABACKUP_PASSWORD';
		GRANT RELOAD,PROCESS,LOCK TABLES,REPLICATION CLIENT ON *.* TO 'xtrabackup'@'localhost';

		DROP DATABASE IF EXISTS test ;
		FLUSH PRIVILEGES;
	EOSQL

	if [ ! -z "$MYSQL_ROOT_PASSWORD" ]; then
		mysql+=( -p"${MYSQL_ROOT_PASSWORD}" )
	fi

	if [ "$MYSQL_DATABASE" ]; then
		echo "CREATE DATABASE IF NOT EXISTS \`$MYSQL_DATABASE\` ;" | "${mysql[@]}"
		mysql+=( "$MYSQL_DATABASE" )
	fi

	if [ "$MYSQL_USER" -a "$MYSQL_PASSWORD" ]; then
		echo "CREATE USER '$MYSQL_USER'@'%' IDENTIFIED BY '$MYSQL_PASSWORD' ;" | "${mysql[@]}"

		if [ "$MYSQL_DATABASE" ]; then
			echo "GRANT ALL ON \`$MYSQL_DATABASE\`.* TO '$MYSQL_USER'@'%' ;" | "${mysql[@]}"
		fi

		echo 'FLUSH PRIVILEGES ;' | "${mysql[@]}"
	fi

	if ! kill -s TERM "$pid" || ! wait "$pid"; then
		echo >&2 'MySQL init process failed.'
		exit 1
	fi
}

_exec_entrypoints() {
	mysql=( mysql --protocol=socket -uroot -p$MYSQL_ROOT_PASSWORD )

	for f in /docker-entrypoint-initdb.d/*; do
		case "$f" in
			*.sh)     echo "$0: running $f"; . "$f" ;;
			*.sql)    echo "$0: running $f"; "${mysql[@]}" < "$f"; echo ;;
			*.sql.gz) echo "$0: running $f"; gunzip -c "$f" | "${mysql[@]}"; echo ;;
			*)        echo "$0: ignoring $f" ;;
		esac
		echo
	done
}

_check_config() {
	toRun=( "$@" --wsrep-recover --verbose --help --log-bin-index="$(mktemp -u)" )
	if ! errors="$("${toRun[@]}" 2>&1 >/dev/null)"; then
		cat >&2 <<-EOM
			ERROR: mysqld failed while attempting to check config
			command was: "${toRun[*]}"
			$errors
		EOM
		exit 1
	fi
}

# if command starts with an option, prepend mysqld
if [ "${1:0:1}" = '-' ]; then
	set -- mysqld "$@"
fi

if [ "$1" = 'mysqld' ]; then
	if [ -z "$CLUSTER_NAME" ]; then
		echo >&2 'Error:  You need to specify CLUSTER_NAME'
		exit 1
	fi

	_check_config "$@"

	DATADIR="$($@ --wsrep-recover --verbose --help 2>/dev/null | awk '$1 == "datadir" { print $2; exit }')"

	if [ ! -e "$DATADIR/mysql" ]; then
		echo "Initializing database..."
		_initialize_database "$@"
		_exec_entrypoints "$@"

		echo
		echo 'Database is initialized!'
		echo
	fi

	chown -R mysql:mysql "$DATADIR"

	ARGS+=(
		--user=mysql
		--wsrep_cluster_name=$CLUSTER_NAME
		--wsrep_cluster_address="gcomm://$CLUSTER_JOIN"
		--wsrep_sst_method=xtrabackup-v2
		--wsrep_sst_auth="xtrabackup:$XTRABACKUP_PASSWORD"
	)
fi

exec "$@" ${ARGS[@]}
