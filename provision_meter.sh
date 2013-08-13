###
### Copyright 2011-2013, Boundary
###
### Licensed under the Apache License, Version 2.0 (the "License");
### you may not use this file except in compliance with the License.
### You may obtain a copy of the License at
###
###     http://www.apache.org/licenses/LICENSE-2.0
###
### Unless required by applicable law or agreed to in writing, software
### distributed under the License is distributed on an "AS IS" BASIS,
### WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
### See the License for the specific language governing permissions and
### limitations under the License.
###

#!/bin/bash

APIHOST="api.boundary.com"
TARGET_DIR="/tmp"
EC2_INTERNAL="http://169.254.169.254/latest/meta-data"
TAGS="instance-type placement/availability-zone"

function print_help() {
  echo "./provision_meter.sh -i ORGID:APIKEY"
  exit 0
}

function create_meter() {
  local LOCATION=`curl -is -X POST -H "Content-Type: application/json" -d "{\"name\": \"$HOSTNAME\"}" -u "$1:" $2  \
        | grep Location \
        | sed 's/Location: //' \
        | sed 's/\(.*\)./\1/'`

  echo $LOCATION
}

function download_certificate() {
  echo "downloading meter certificate for $2"
  curl -s -u "$1:" $2/cert.pem > $TARGET_DIR/cert.pem
  chmod 600 $TARGET_DIR/cert.pem
}

function download_key() {
  echo "downloading meter key for $2"
  curl -s -u "$1:" $2/key.pem > $TARGET_DIR/key.pem
  chmod 600 $TARGET_DIR/key.pem
}

function ec2_tag() {
  EC2=`curl -s --connect-timeout 5 "$EC2_INTERNAL"`
  exit_code=$?

  if [ "$exit_code" -eq "0" ]; then
    echo -n "Auto generating ec2 tags for this meter...."
  else
    return 0
  fi

  for tag in $TAGS; do
    local AN_TAG
    local exit_code

    AN_TAG=`curl -s --connect-timeout 5 "$EC2_INTERNAL/$tag"`
    exit_code=$?

    # if the exit code is 7, that means curl couldnt connect so we can bail
    # since we probably are not on ec2.
    if [ "$exit_code" -eq "7" ]; then
      # do nothing
      return 0
    fi

    # it appears that an exit code of 28 is also a can't connect error
    if [ "$exit_code" -eq "28" ]; then
       # do nothing
      return 0
    fi

    # otherwise, maybe there was as timeout or something, skip that tag.
    if [ "$exit_code" -ne "0" ]; then
      continue
    fi

    for an_tag in $AN_TAG; do
      # create the tag
      curl -H "Content-Type: application/json" -s -u "$1:" -X PUT "$2/tags/$an_tag"
    done
  done

  curl -H "Content-Type: application/json" -s -u "$1:" -X PUT "$2/tags/ec2"
  echo "done."
}

while getopts "h a:d:i:" opts
do
  case $opts in
    h) print_help;;
    i) APICREDS="$OPTARG";;
    d) TARGET_DIR="$OPTARG";;
    [?]) print_help;;
  esac
done

if [ ! -z $APICREDS ]
  then
    APIID=`echo $APICREDS | awk -F: '{print $1}'`
    APIKEY=`echo $APICREDS | awk -F: '{print $2}'`

    if [ "$HOSTNAME" == "localhost" ] || [ -z $HOSTNAME ]
      then
        echo "Hostname set to localhost or null, exiting."
        exit 1
    else
      URL="https://$APIHOST/$APIID/meters"

      METER_LOCATION=`create_meter $APIKEY $URL`

      if [ ! -z $METER_LOCATION ]
        then
          echo "Meter created at $METER_LOCATION"
          download_certificate $APIKEY $METER_LOCATION
          download_key $APIKEY $METER_LOCATION
          ec2_tag $APIKEY $METER_LOCATION
        else
          echo "No location header received, error creating meter!"
          exit 1
      fi
    fi
else
  print_help
fi
