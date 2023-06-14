FROM ubuntu:jammy

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8
ENV AUTOVACUUM=on
ENV UPDATES=disabled
ENV PG_VERSION 14

RUN apt update \
    && apt install -y locate libapache2-mod-tile renderd tar unzip wget bzip2 apache2 lua5.1 mapnik-utils python3-mapnik python3-psycopg2 python3-yaml gdal-bin npm fonts-noto-cjk fonts-noto-hinted fonts-noto-unhinted fonts-unifont fonts-hanazono postgresql postgresql-contrib postgis postgresql-$PG_VERSION-postgis-3 postgresql-$PG_VERSION-postgis-3-scripts osm2pgsql net-tools curl \
    && apt-get clean autoclean \
    && apt-get autoremove --yes \
    && rm -rf /var/lib/{apt,dpkg,cache,log}/


RUN adduser --disabled-password --gecos "" renderd

RUN npm install -g carto

RUN echo "LoadModule tile_module /usr/lib/apache2/modules/mod_tile.so" >> /etc/apache2/conf-available/mod_tile.conf && \
    echo "LoadModule headers_module /usr/lib/apache2/modules/mod_headers.so" >> /etc/apache2/conf-available/mod_headers.conf && \
    a2enconf mod_tile && \
    a2enconf mod_headers

COPY apache.conf /etc/apache2/sites-available/000-default.conf
RUN ln -sf /dev/stdout /var/log/apache2/access.log && \
    ln -sf /dev/stderr /var/log/apache2/error.log

COPY postgresql.custom.conf.tmpl /etc/postgresql/$PG_VERSION/main/
RUN chown -R postgres:postgres /var/lib/postgresql \
&& chown postgres:postgres /etc/postgresql/$PG_VERSION/main/postgresql.custom.conf.tmpl \
&& echo "host all all 0.0.0.0/0 scram-sha-256" >> /etc/postgresql/$PG_VERSION/main/pg_hba.conf \
&& echo "host all all ::/0 scram-sha-256" >> /etc/postgresql/$PG_VERSION/main/pg_hba.conf

RUN echo '[light] \n\
URI=/tile/ \n\
TILEDIR=/var/cache/renderd/tiles \n\
XML=/home/renderd/src/openstreetmap-carto/mapnik.xml \n\
HOST=localhost \n\
TILESIZE=256 \n\
MINZOOM=14\n\
MAXZOOM=18' >> /etc/renderd.conf

RUN mkdir -p /data/database/ \
    && chown -R renderd: /data/

RUN mkdir -p /home/renderd/src \
    && git clone https://github.com/gravitystorm/openstreetmap-carto /home/renderd/src/openstreetmap-carto 

RUN mkdir /home/renderd/src/openstreetmap-carto/data \
    && chown -R renderd: /home/renderd/src/openstreetmap-carto
  
RUN cd /var/www/html/ && \
    wget https://github.com/Leaflet/Leaflet/releases/download/v1.9.4/leaflet.zip && \
    unzip leaflet.zip && \
    rm leaflet.zip

COPY index.html /var/www/html/index.html

COPY setup.sh /
RUN chmod a+x ./setup.sh
ENTRYPOINT ["/setup.sh"]
EXPOSE 80
