#!/bin/bash


set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: <setup|run>"
  echo "  setup: Import and configure required datasets. [Init db and import .osm.pbf file]"
  echo "  run:   Run all necessary services such as a Apache and PostgreSQL with Renderd daemon"
  exit 1
fi

set -x


function createPostgresConfig() {
  cp /etc/postgresql/$PG_VERSION/main/postgresql.custom.conf.tmpl /etc/postgresql/$PG_VERSION/main/conf.d/postgresql.custom.conf
  echo "autovacuum = $AUTOVACUUM" >> /etc/postgresql/$PG_VERSION/main/conf.d/postgresql.custom.conf
  cat /etc/postgresql/$PG_VERSION/main/conf.d/postgresql.custom.conf
}


if [ "$1" == "setup" ]; then

  if [ -d /data/database ] && [ -n "$(ls -A /data/database)" ]; then
    echo "Directory /data/database is already existing. Exit ...."
    exit 1
  fi


  mkdir -p /data/database/postgres/
  chown -R postgres: /var/lib/postgresql/ /data/database/postgres
  su - postgres -c "/usr/lib/postgresql/$PG_VERSION/bin/pg_ctl -D /data/database/postgres/ initdb -o \"--locale C.UTF-8\""
  
  createPostgresConfig
  service postgresql start
  su - postgres -c "createuser renderd"
  su - postgres -c "createdb -E UTF8 -O renderd gis"
  su - postgres -c "psql -d gis -c \"CREATE EXTENSION postgis;\""
  su - postgres -c "psql -d gis -c \"CREATE EXTENSION hstore;\""
  su - postgres -c "psql -d gis -c \"ALTER TABLE geometry_columns OWNER TO renderd;\""
  su - postgres -c "psql -d gis -c \"ALTER TABLE spatial_ref_sys OWNER TO renderd;\""

  if [ ! -f /data/region.osm.pbf ]; then
    echo "WARNING: PBF File is not loaded"
    exit 1
  fi

  su - renderd -c "osm2pgsql -d gis --create --slim  -G --hstore --tag-transform-script /home/renderd/src/openstreetmap-carto/openstreetmap-carto.lua -C 2500 --number-processes 1 -S /home/renderd/src/openstreetmap-carto/openstreetmap-carto.style /data/region.osm.pbf"
  su - renderd -c "psql -d gis -f /home/renderd/src/openstreetmap-carto/indexes.sql"
  su - renderd -c "python3 /home/renderd/src/openstreetmap-carto/scripts/get-external-data.py -c /home/renderd/src/openstreetmap-carto/external-data.yml -D /home/renderd/src/openstreetmap-carto/data"

  service postgresql stop

  exit 0

fi


if [ "$1" == "run" ]; then

  rm -rf /tmp/*
  
  chown -R postgres: /var/lib/postgresql/ /data/database/postgres/

  createPostgresConfig
  service postgresql start
  service apache2 start

  stop_handler() {
    kill -TERM "$child"
  }
  trap stop_handler SIGTERM

  su - renderd -c "renderd -f -c /etc/renderd.conf &"
  child=$!
  wait "$child"

  service postgresql stop
  service apache2 stop

  exit 0

fi

exit 1
