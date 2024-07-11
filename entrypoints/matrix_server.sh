#!/bin/bash

if ! test -f "/data/homeserver.yaml"
then
/start.py generate -H $MATRIX_SERVER_NAME

replaceInConfig(){
  old=$1
  new=$2
  sed -i "/$old/c\\$new" /data/homeserver.yaml
}

fi

/start.py
