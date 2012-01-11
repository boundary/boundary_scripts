#!/bin/bash

APIHOST="api.boundary.com"
APICREDS=

function print_help() {
  echo "./create_annotation.sh -i APIID -a APIKEY"
  exit 0
}

function create_annotation() {

  local LOCATION=`curl -is -X POST -H "Content-Type: application/json" \
  -d '{"tags":["example","test","stuff"],"end_time":1320966015,"subtype":"test","type":"example","loc":{"city":"San Francisco","region":"California","lat":37.759965,"lon":-122.390289,"country":"US"},"start_time":1320965015}' \
  -u "$1:" $2  \
        | grep Location \
        | sed 's/Location: //' \
        | sed 's/\(.*\)./\1/'`

  echo $LOCATION
}

while getopts "h a:i:" opts
do
  case $opts in
    h) print_help;;
    i) APIID="$OPTARG";;
    a) APIKEY="$OPTARG";;
    [?]) print_help;;
  esac
done

if [ ! -z $APIID ]
  then
    if [ ! -z $APIKEY ]
      then
        URL="https://$APIHOST/$APIID/annotations"

        ANNOTATION_LOCATION=`create_annotation $APIKEY $URL`

        if [ ! -z $ANNOTATION_LOCATION ]
          then
            echo "An annotation was created at $ANNOTATION_LOCATION"
          else
            echo "No location header received, error creating annotation!"
            exit 1
        fi
      else
        print_help
      fi
else
  print_help
fi
