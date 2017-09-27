# About this Repo

[![Build Status](https://travis-ci.org/lagardere-sports/percona-xtradb-cluster.svg?branch=master)](https://travis-ci.org/lagardere-sports/percona-xtradb-cluster)
[![Docker Pull Badge](https://img.shields.io/docker/pulls/keepr/percona-xtradb-cluster.svg)](https://hub.docker.com/r/keepr/percona-xtradb-cluster)

This is the git repo of the docker image of percona-xtradb-cluster. It's based on [original image](https://hub.docker.com/r/percona/percona-xtradb-cluster/) and is inspired by [community image](https://hub.docker.com/_/percona/).

## Environment Variables

### `CLUSTER_NAME`
Name of the cluster. *MUST* be equal on each node.

### `CLUSTER_JOIN`
Empty variables will start a new cluster. To join an existing cluster, set `CLUSTER_JOIN` to the list of IP addresses running cluster nodes.

### `MYSQL_ROOT_PASSWORD`
This variable is mandatory and specifies the password that will be set for the Percona root superuser account.

### `XTRABACKUP_PASSWORD`
This variable is mandatory and specifies the password that will be set for the SST user account.

## Initializing a fresh instance
When a container is started for the first time, a new database with the specified name will be created and initialized with the provided configuration variables. Furthermore, it will execute files with extensions `.sh`, `.sql` and `.sql.gz` that are found in `/docker-entrypoint-initdb.d`. Files will be executed in alphabetical order. You can easily populate your percona services by mounting a SQL dump into that directory and provide custom images with contributed data.
