#!/bin/bash
###
### Copyright 2014, Boundary
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

##
## Constants
##
BOUNDARY_API_HOST="api.boundary.com"

##
## Write the usage of the script to standard error
## then exits.
##
function Usage() {
  echo "Usage: $(basename $0) <api_key>" >&2
  exit 2
}

##
## Check to determine if the meter is installed on the system
##
## ARGS
##  None
##
function MeterInstalled() {
  if [ -d /etc/bprobe -o -d /etc/boundary ]
  then
    return 1
  else
   return 0
  fi
}

##
## Extracts the meter version based the name of directory in /etc
##
## ARGS
##  None
##
function MeterVersion() {
   local -i version=0

   if [ -d /etc/bprobe ] 
   then
      version=2
   elif [ -d /etc/boundary ]
   then
      version=3
   fi
   echo $version
}

##
## Determines if a program or command is available
##
## ARGS
##  $1 - Name of program or command
##
function ExecAvailable() {
  local -r exec=$1
  local result=0

  type "$exec" > /dev/null 2>&1
  if [ $? -ne 0 ]
  then
    echo "$exec is required but not in path"
    result=1
  fi
  return $result
}

##
## Determines if all the prequiste software and/or commands
## are available that this script depends on to run.
##
## ARGS
##  None
##
function CheckPrerequisites() {

  for exec in curl openssl
  do
    ExecAvailable $exec
  done
}

##
## Stops the meter on the host
##
## ARGS
##  None
##
function StopMeter() {
  $METER_INITD stop
}

##
## Starts the meter on the host
##
## ARGS
##  None
##
function StartMeter() {
  $METER_INITD start
}

##
## Initializes data and performs checks before
## the core of the script runs
##
## ARGS
##  None
##
function Initialize() {

  # Check to see if meter is installed and if print error message and exit.
  if [ MeterInstalled -eq 0 ]
  then
    echo "Meter is not installed" 2>&1
    exit 1
  fi

  # If we do not have the api key then print usage and exit
  if [ $# -lt 1 ]
  then
    Usage
  else
    # Make API_KEY read-only
    typeset -r API_KEY="$1"
  fi

  # Check for dependent commands or other software to run this script
  if [ CheckPrerequisites -eq 0 ]
  then
    exit 1
  fi

  # Setup meter version specific information
  meter_version=$(MeterVersion)

  case "$meter_version" in
    2)
      METER_ETC=/etc/bprobe
      CERT_FILE=$METER_ETC/cert.pem
      METER_INITD=/etc/init.d/bprobe
    ;;
    3)
      METER_ETC=/etc/boundary
      CERT_FILE=$METER_ETC/ca.pem
      METER_INITD=/etc/init.d/boundary-meter
    ;;
    *)
      echo "Unknown meter version exiting"
    ;;
  esac
}

##
## Extracts the certification version number from the certificate file
##
## ARGS
##  $1 - Path to the certificate file
##
function CertificateVersion() {
  local -r cert_file=$1
  cert_version=$(openssl x509 -in $cert_file -noout -text | grep 'Version:' | awk '{print $2}')
  echo "$cert_version"
}

##
## Returns the Subject of the certificate from the certificate file
##
## ARGS
##  $1 - Path to the certificate file
##
function CertificateSubject() {
  local -r cert_file=$1
  subject=$(openssl x509 -in $cert_file -noout -text | grep 'Subject:' | awk '{print $NF}')
  echo "$subject"
}

##
## Extracts the organization id from the certificate file
##
## ARGS
##  $1 - Path to the certificate file
##
function CertificateOrgId() {
  local -r cert_file=$1
  local org_id=$(echo "$(CertificateSubject)" | cut -d'/' -f1 | cut -d'=' -f2)
  echo "$org_id"
}

##
## Extracts the meter id from the certificate file
##
## ARGS
##  $1 - Path to the certificate file
##
function CertificateMeterId() {
  local -r cert_file=$1
  local meter_id=$(echo "$(CertificateSubject $cert_file)" | cut -d'/' -f2 | cut -d'=' -f2)
  echo "$meter_id"
}

##
## Calls the Boundary API to delete the meter's certificate
##
## ARGS
##  $1 - API key
##  $2 - Organization Id
##  $3 - Meter Id
##

function MeterCertficateDelete() {
  local -r api_key=$1
  local -r org_id=$2
  local -r meter_id=$3

   curl -f -u "$api_key:" -X DELETE https://$BOUNDARY_API_HOST/$org_id/meters/$meter_id/cert.pem
}

#
# Update the version 1 certs on the meter host
#
# ARGS
#   $1 - Path to the certificate file
#
function UpdateCerts() {
  local -r api_key=$1
  local -r cert_file=$2
  local certdir=$(dirname "$cert_file")
  local cert_version=$(CertificateVersion "$cert_file")

  case "$cert_version" in
    1)
      echo "Certificate $cert_file is invalid: $cert_version"

      ORG_ID=$(CertificateOrgId "$cert_file")
      METER_ID=$(CertificateMeterId "$cert_file")
      echo "Organization ID: $ORG_ID, Meter ID: $METER_ID"

      # Stop the meter so we can update the certificates
      StopMeter

      MeterCertificateDelete "$API_KEY" "$ORG_ID" "$METER_ID"

      cp -p $certdir/cert.pem $certdir/cert.pem.old
      curl -f -u "$API_KEY:" -o $certdir/cert.pem https://$BOUNDARY_API_HOST/$ORG_ID/meters/$METER_ID/cert.pem

      cp -p $certdir/key.pem $certdir/key.pem.old
      curl -f -u "$API_KEY:" -o $certdir/key.pem https://$BOUNDARY_API_HOST/$ORG_ID/meters/$METER_ID/key.pem

      # Start the meter with the new certificates
      StartMeter

      ;;
    3)
      echo "Certificate $cert_file is OK: $cert_version"
      ;;
    *)
      echo "Certificate $cert_file has unknown cert version: $cert_version" >&2
      exit 1
  esac
}

##
## Entry point to the script
##
## ARGS
##   $* - Arguments passed to the script
##
function Main() {

   Initialize $*

   UpdateCerts "$API_KEY"
}

#
# Execute the script
#
#Main $*
