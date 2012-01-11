#!/bin/bash

APIHOST="api.boundary.com"
TARGET_DIR="/etc/bprobe"

EC2_INTERNAL="http://169.254.169.254/latest/meta-data"
TAGS="instance-type placement/availability-zone security-groups"

test -f /etc/issue

if [ $? -eq 0 ]; then
  PLATFORM=`cat /etc/issue | head -n 1`
  DISTRO=`echo $PLATFORM | awk '{print $1}'`
  MACHINE=`uname -m`
else
  PLATFORM="unknown"
  DISTRO="unknown"
  MACHINE=`uname -m`
fi

SUPPORTED_ARCH=0
SUPPORTED_PLATFORM=0

APT="apt.boundary.com"
YUM="yum.boundary.com"

DEPS="false"

trap "exit" INT TERM EXIT

function print_help() {
  echo "   ./meter_setup.sh [-d] -i ORGID:APIKEY"
  echo "      -i: Required input for authentication. The ORGID and APIKEY can be found in the Account Settings in the Boundary WebUI"
  echo "      -d: Optional flag to install all dependencies, such as curl and apt-transport-https, required for Meter Install"
  exit 0
}

function create_meter() {
  RESULT=`curl --connect-timeout 5 -i -s -X POST \
    -H "Content-Type: application/json" \
    -d "{\"name\": \"$HOSTNAME\"}" -u "$1:" \
    https://$APIHOST/$2/meters \
    | tr -d "\r" \
    | awk '{split($0,a," "); print a[2]}'`

  STATUS=`echo $RESULT | awk '{print $1}'`

  exit_status=$?

  # if the exit code is 7, that means curl couldnt connect so we can bail
  if [ "$exit_status" -eq "7" ]; then
    echo "Could not connect to create meter"
    exit 1
  fi

  # it appears that an exit code of 28 is also a can't connect error
  if [ "$exit_status" -eq "28" ]; then
    echo "Could not connect to create meter"
    exit 1
  fi

  if [ "$STATUS" = "401" ]; then
    echo "Authentication error, bad Org ID or API key (http status $STATUS)."
    echo "Verify that you have passed in the correct credentials.  The ORGID and APIKEY can be found in the Account Settings in the Boundary WebUI"
    exit 1
  else
    if [ "$STATUS" = "201" ] || [ "$STATUS" = "409" ]; then
      echo $RESULT | awk '{print $2}'
    else
      echo "An Error occurred during the meter creation (http status $STATUS).  Please contact support at support@boundary.com."
      exit 1
    fi
  fi
}

function setup_cert_key() {
  trap "exit" INT TERM EXIT

  test -d $TARGET_DIR

  if [ $? -eq 1 ]; then
    echo "Creating meter config directory ($TARGET_DIR) ..."
    sudo mkdir $TARGET_DIR
  fi

  test -f $TARGET_DIR/key.pem

  if [ $? -eq 1 ]; then
    echo "Key file is missing, attempting to download ..."
    echo "Downloading meter key for $2"
    sudo curl -s -u $1: $2/key.pem | sudo tee $TARGET_DIR/key.pem > /dev/null

    if [ $? -gt 0 ]; then
      echo "Error downloading key ..."
      exit 1
    fi

    sudo chmod 600 $TARGET_DIR/key.pem
  fi

  test -f $TARGET_DIR/cert.pem

  if [ $? -eq 1 ]; then
    echo "Cert file is missing, attempting to download ..."
    echo "Downloading meter certificate for $2"
    sudo curl -s -u $1: $2/cert.pem | sudo tee $TARGET_DIR/cert.pem > /dev/null

    if [ $? -gt 0 ]; then
      echo "Error downloading certificate ..."
      exit 1
    fi

    sudo chmod 600 $TARGET_DIR/cert.pem
  fi
}

function cert_key_check() {
  SIZE=`du $TARGET_DIR/cert.pem | awk '{print $1}'`

  if [ $SIZE -lt 1 ]; then
    echo "Error downloading certificate (file size 0) ..."
    exit 1
  fi

  SIZE=`du $TARGET_DIR/key.pem | awk '{print $1}'`

  if [ $SIZE -lt 1 ]; then
    echo "Error downloading key (file size 0) ..."
    exit 1
  fi
}

function ec2_tag() {
  trap "exit" INT TERM EXIT

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

while getopts "h di:" opts; do
  case $opts in
    h) print_help;;
    d) DEPS="true";;
    i) APICREDS="$OPTARG";;
    [?]) print_help;;
  esac
done

if [ ! -z $APICREDS ]; then

  CURL=`which curl`

  if [ $? -gt 0 ]; then
    echo "The 'curl' command is either not installed or not on the PATH ..."

    if [ $DEPS = "true" ]; then
      echo "Installing curl ..."

      if [ $DISTRO = "Ubuntu" ]; then
        sudo apt-get update > /dev/null
        sudo apt-get install curl
      fi

      if [ $DISTRO = "CentOS" ]; then
        if [ $MACHINE = "i686" ]; then
          sudo yum install curl.i686
        fi

        if [ $MACHINE = "x86_64" ]; then
          sudo yum install curl.x86_64
        fi
      fi

    else
      echo "To automatically install required components for Meter Install, rerun setup_meter.sh with -d flag."
      exit 1
    fi
  fi

  APIID=`echo $APICREDS | awk -F: '{print $1}'`
  APIKEY=`echo $APICREDS | awk -F: '{print $2}'`

  if [ $MACHINE = "i686" ]; then
    ARCH="32"
    SUPPORTED_ARCH=1
  fi

  if [ $MACHINE = "x86_64" ]; then
    ARCH="64"
    SUPPORTED_ARCH=1
  fi

  if [ $SUPPORTED_ARCH -eq 0 ]; then
    echo "Unsupported architecture ($MACHINE) ..."
    echo "This is an unsupported platform for the Boundary Meter. Please contact support@boundary.com to request support for this architecture."
    exit 1
  fi

  if [ $DISTRO = "Ubuntu" ]; then
    SUPPORTED_PLATFORM=1
  fi

  if [ $DISTRO = "CentOS" ]; then
    SUPPORTED_PLATFORM=1
  fi

  if [ $SUPPORTED_PLATFORM -eq 0 ]; then
    echo "Unsupported OS ($DISTRO) ..."
    echo "This is an unsupported OS for the Boundary Meter. Please contact support@boundary.com to request support for this operating system."
    exit 1
  fi

  if [ "$HOSTNAME" == "localhost" ] || [ -z $HOSTNAME ]; then
    echo "Hostname set to localhost or null, exiting."
    echo "This script uses hostname as the meter name.  The hostname must be set to something other than localhost or null."
    echo " "
    echo "Set the hostname for this instance and re-run this script."
    exit 1
  fi

  #
  # Ubuntu Install
  #

  if [ $DISTRO = "Ubuntu" ]; then
    test -f /usr/lib/apt/methods/https

    if [ $? -gt 0 ];then
      echo "apt-transport-https is not installed to access Boundary's HTTPS based APT repository ..."

      if [ $DEPS = "true" ]; then
        if [ $DISTRO = "Ubuntu" ]; then
          echo "Installing apt-transport-https ..."

          sudo apt-get update > /dev/null
          sudo apt-get install apt-transport-https
        fi
      else
        echo "To automatically install required components for Meter Install, rerun setup_meter.sh with -d flag."
        exit 1
      fi

    fi

    VERSION=`echo $PLATFORM | awk '{print $2}'`

    MAJOR_VERSION=`echo $VERSION | awk -F. '{print $1}'`
    MINOR_VERSION=`echo $VERSION | awk -F. '{print $2}'`
    PATCH_VERSION=`echo $VERSION | awk -F. '{print $3}'`

    if [ "$MAJOR_VERSION.$MINOR_VERSION" = "10.04" ]; then
      echo "Detected ubuntu 10.04 (lucid) ..."
      echo ""

      METER_LOCATION=`create_meter $APIKEY $APIID`

      if [ $? -gt 0 ]; then
        echo "Error creating meter, $METER_LOCATION ..."
        exit 1
      fi

      KEY_CERT=`setup_cert_key $APIKEY $METER_LOCATION`

      if [ $? -eq 1 ]; then
        echo "Error setting up cert and/or key ..."
        echo $KEY_CERT
        exit 1
      fi

      CERT_KEY_CHECK=`cert_key_check`

      if [ $? -eq 1 ]; then
        echo "Error setting up cert and/or key ..."
        echo $CERT_KEY_CHECK
        exit 1
      fi

      ec2_tag $APIKEY $METER_LOCATION

      sudo apt-get update > /dev/null
      curl -s https://$APT/boundary.list | sudo tee /etc/apt/sources.list.d/boundary.list > /dev/null
      curl -s https://$APT/ubuntu/APT-GPG-KEY-Boundary | sudo apt-key add -
      sudo apt-get update > /dev/null
      sudo apt-get install bprobe
    else
      echo "Detected ubuntu but with an unsupported version ($MAJOR_VERSION.$MINOR_VERSION)"
      echo "Boundary Meters can only be installed on Ubuntu 10.04.  For additional Operating System support, please contact support@boundary.com"
      exit 1
    fi
  fi

  #
  # CentOS Install
  #

  if [ $DISTRO = "CentOS" ]; then
    VERSION=`echo $PLATFORM | awk '{print $3}'`

    MAJOR_VERSION=`echo $VERSION | awk -F. '{print $1}'`
    MINOR_VERSION=`echo $VERSION | awk -F. '{print $2}'`

    if [ "$MAJOR_VERSION" = "5" ]; then
      echo "Detected centos 5 ..."
      echo ""

      METER_LOCATION=`create_meter $APIKEY $APIID`

      if [ $? -gt 0 ]; then
        echo "Error creating meter, $METER_LOCATION ..."
        exit 1
      fi

      KEY_CERT=`setup_cert_key $APIKEY $METER_LOCATION`

      if [ $? -eq 1 ]; then
        echo "Error setting up cert and/or key ..."
        echo $KEY_CERT
        exit 1
      fi

      CERT_KEY_CHECK=`cert_key_check`

      if [ $? -eq 1 ]; then
        echo "Error setting up cert and/or key ..."
        echo $CERT_KEY_CHECK
        exit 1
      fi

      ec2_tag $APIKEY $METER_LOCATION

      curl -s https://$YUM/boundary_"$ARCH"bit.repo | sudo tee /etc/yum.repos.d/boundary.repo > /dev/null
      curl -s https://$YUM/RPM-GPG-KEY-Boundary | sudo tee /etc/pki/rpm-gpg/RPM-GPG-KEY-Boundary > /dev/null
      sudo yum install bprobe
    else
      echo "Detected centos but with an unsupported version ($MAJOR_VERSION)"
      echo "Boundary Meters can only be installed on CentOS 5.x.  For additional Operating System support, please contact support@boundary.com"
      exit 1
    fi
  fi
else
  print_help
fi
