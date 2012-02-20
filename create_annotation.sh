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
  echo "./create_annotation.sh -i ORGID -a APIKEY"
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
