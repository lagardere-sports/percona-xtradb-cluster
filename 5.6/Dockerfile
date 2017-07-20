# vim:set ft=dockerfile:
FROM percona/percona-xtradb-cluster:5.6.36

COPY docker-entrypoint.sh /usr/local/bin/

ENTRYPOINT ["docker-entrypoint.sh"]

EXPOSE 3306
CMD ["mysqld"]
