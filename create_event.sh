###
### Copyright 2011, Boundary
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
APICREDS=

function print_help() {
  echo "./create_event.sh -i ORGID -a APIKEY"
  exit 0
}

function create_event() {

  local LOCATION=`curl -is -X POST -H "Content-Type: application/json" \
  -d '{ "severity":"ERROR", "status":"OPEN","source":{"ref":"sample","type":"meter","name":"samplesource"} \
  , "sender":{"ref":"sample","type":"samplescript","name":"create_event.sh"} \
  , "properties":{ "eventKey":"123423" }, "tags":["example","test","stuff"],"title": "sample event" \
  , "message":"details of the event","fingerprintFields":["eventKey"] }' \
  -u "$1:" $2 \
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
        URL="https://$APIHOST/$APIID/events"
        EVENT_LOCATION=`create_event $APIKEY $URL`
        if [ ! -z $EVENT_LOCATION ]
          then
            echo "An event was created at $EVENT_LOCATION"
          else
            echo "No location header received, error creating event!"
            exit 1
        fi
      else
        print_help
      fi
else
  print_help
fi
