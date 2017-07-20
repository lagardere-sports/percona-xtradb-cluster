#!/bin/bash
WSREP_STATUS=$(
  mysql -h localhost -p$MYSQL_ROOT_PASSWORD -nNE -e "SHOW GLOBAL STATUS LIKE 'wsrep_local_state_comment'" 2>/dev/null | \
  sed -n -e '3p' | \
  tr '\n' ' '
)

exec test WSREP_STATUS = 'Synced'
