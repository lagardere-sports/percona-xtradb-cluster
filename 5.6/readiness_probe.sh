#!/bin/bash
WSREP_STATUS=($(
  mysql -h localhost -p$MYSQL_ROOT_PASSWORD -nNE -e "SHOW GLOBAL STATUS LIKE 'wsrep_%'" 2>/dev/null | \
  grep -A1 -E "wsrep_ready$|wsrep_connected$|wsrep_local_state_comment$" | \
  sed -n -e '2p' -e '5p' -e '8p' | \
  tr '\n' ' '
))

exec test ${WSREP_STATUS[0]} = 'Synced' -a ${WSREP_STATUS[1]} = 'ON' -a ${WSREP_STATUS[2]} = 'ON'
