#!/bin/bash

OSMFILE=${OSMFILE:=osm-file.osm.pbf}
BACKUPFILE=${BACKUPFILE:=pg-nominatim.tar.gz}
S3BACKUPFILE=${S3BACKUPFILE:=s3://soul-nominatim/$BACKUPFILE}
PGDIR=${PGDIR:=postgresqldata}
THREADS=${THREADS:=4}
SETUP_PHP_ARGS=${SETUP_PHP_ARGS:="--all --threads $THREADS"}

export AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
export AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION}

[[ $FORCE_NEW == "yes" ]] && rm -rf /data/$PGDIR

if [ ! -d /data/$PGDIR ] && aws s3 ls $S3BACKUPFILE > /dev/null; then
    aws s3 cp $S3BACKUPFILE /data/$BACKUPFILE
    mkdir -p /data/$PGDIR
    echo "Extracting /data/$BACKUPFILE to /data/$PGDIR..."
    tar -C /data/$PGDIR -zxf /data/$BACKUPFILE && echo "Done"
    chown -R postgres:postgres /data/$PGDIR
    rm /data/$BACKUPFILE
fi

if [ ! -d /data/$PGDIR ]; then
    [[ -n $PBF_URL && ! -f /data/$OSMFILE ]] && curl -L $PBF_URL --create-dirs -o /data/$OSMFILE
    mkdir -p /data/$PGDIR && chown postgres:postgres /data/$PGDIR
    export  PGDATA=/data/$PGDIR
    sudo -u postgres /usr/lib/postgresql/12/bin/initdb -D /data/$PGDIR
    sudo -u postgres /usr/lib/postgresql/12/bin/pg_ctl -D /data/$PGDIR start
    sudo -u postgres createuser -sD nominatim
    sudo -u postgres createuser -SDR www-data
    useradd -m -p password1234 nominatim && chown -R nominatim:nominatim ./src
    sudo -u nominatim ./src/build/utils/setup.php --osm-file /data/$OSMFILE $SETUP_PHP_ARGS && \
    sudo -u nominatim ./src/build/utils/check_import_finished.php || exit 1
    sudo -u nominatim ./src/build/utils/setup.php --drop
    sudo -u postgres /usr/lib/postgresql/12/bin/pg_ctl -D /data/$PGDIR stop
    chown -R postgres:postgres /data/$PGDIR
    [[ -n $PBF_URL ]] && rm /data/$OSMFILE
    echo "Making S3 backup /data/$PGDIR to $S3BACKUPFILE..."
    tar -C /data/$PGDIR -zcf /data/$BACKUPFILE . && echo "TAR.GZ archive done to /data/$BACKUPFILE"
    aws s3 cp /data/$BACKUPFILE $S3BACKUPFILE
    rm /data/$BACKUPFILE
fi
