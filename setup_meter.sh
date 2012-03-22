##
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

# ARCHS=("i686" "x86_64")
PLATFORMS=("Ubuntu" "Debian" "CentOS")

# Put additional version numbers here.
# These variables take the form ${platform}_VERSIONS, where $platform matches
# the tags in $PLATFORMS
Ubuntu_VERSIONS=("10.10" "11.04" "11.10")
Debian_VERSIONS=("5" "6")
CentOS_VERSIONS=("5" "6")

# -----------------------------------------------------------------------------


APIHOST="api.boundary.com"
TARGET_DIR="/etc/bprobe"

EC2_INTERNAL="http://169.254.169.254/latest/meta-data"
TAGS="instance-type placement/availability-zone security-groups"

SUPPORTED_ARCH=0
SUPPORTED_PLATFORM=0

APT="apt.boundary.com"
YUM="yum.boundary.com"

APT_CMD="apt-get -q -y --force-yes"
YUM_CMD="yum -d0 -e0 -y"

DEPS="false"

trap "exit" INT TERM EXIT

function print_supported_platforms() {
    echo "Your platform is not supported. Supported platforms are:"
    for d in ${PLATFORMS[*]}
    do
	echo -n $d:
	foo="\${${d}_VERSIONS[*]}"
	versions=`eval echo $foo`
	for v in $versions
	do
	    echo -n " $v"
	done
	echo ""
    done

    exit 0
}

function check_distro_version() {
    PLATFORM=$1
    DISTRO=$2

    TEMP="\${${DISTRO}_versions[*]}"
    VERSIONS=`eval echo $TEMP`

    if [ $DISTRO = "Ubuntu" ]; then
	VERSION=`echo $PLATFORM | awk '{print $2}'`

	MAJOR_VERSION=`echo $VERSION | awk -F. '{print $1}'`
	MINOR_VERSION=`echo $VERSION | awk -F. '{print $2}'`
	PATCH_VERSION=`echo $VERSION | awk -F. '{print $3}'`

	TEMP="\${${DISTRO}_VERSIONS[*]}"
	VERSIONS=`eval echo $TEMP`
	for v in $VERSIONS ; do
	    if [ "$MAJOR_VERSION.$MINOR_VERSION" = "$v" ]; then
		return 0
	    fi
	done

    elif [ $DISTRO = "CentOS" ]; then
	# Works for centos 5
	VERSION=`echo $PLATFORM | awk '{print $3}'`
 
        # Hack for centos 6
	if [ $VERSION = "release" ]; then
	    VERSION=`echo $PLATFORM | awk '{print $4}'`
	fi

	MAJOR_VERSION=`echo $VERSION | awk -F. '{print $1}'`
	MINOR_VERSION=`echo $VERSION | awk -F. '{print $2}'`

	TEMP="\${${DISTRO}_VERSIONS[*]}"
	VERSIONS=`eval echo $TEMP`
	for v in $VERSIONS ; do
	    if [ "$MAJOR_VERSION" = "$v" ]; then
		return 0
	    fi
	done

    elif [ $DISTRO = "Debian" ]; then
	VERSION=`echo $PLATFORM | awk '{print $3}'`

	MAJOR_VERSION=`echo $VERSION | awk -F. '{print $1}'`
	MINOR_VERSION=`echo $VERSION | awk -F. '{print $2}'`

	TEMP="\${${DISTRO}_VERSIONS[*]}"
	VERSIONS=`eval echo $TEMP`
	for v in $VERSIONS ; do
	    if [ "$MAJOR_VERSION" = "$v" ]; then
		return 0
	    fi
	done
    fi

    echo "Detected $DISTRO but with an unsupported version ($MAJOR_VERSION.$MINOR_VERSION)"
    return 1
}

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

function do_install() {
    if [ "$DISTRO" = "Debian" ] || [ "$DISTRO" = "Ubuntu" ]; then
	sudo $APT_CMD update > /dev/null
	curl -s https://$APT/boundary.list | sudo tee /etc/apt/sources.list.d/boundary.list > /dev/null
	curl -s https://$APT/APT-GPG-KEY-Boundary | sudo apt-key add -
	sudo $APT_CMD update > /dev/null
	sudo $APT_CMD install bprobe

	return $?
    elif [ "$DISTRO" = "CentOS" ]; then
	curl -s https://$YUM/boundary_centos"$MAJOR_VERSION"_"$ARCH"bit.repo | sudo tee /etc/yum.repos.d/boundary.repo > /dev/null
	curl -s https://$YUM/RPM-GPG-KEY-Boundary | sudo tee /etc/pki/rpm-gpg/RPM-GPG-KEY-Boundary > /dev/null
	sudo $YUM_CMD install bprobe

	return $?
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

function pre_install_sanity() {
    CURL=`which curl`

    if [ $? -gt 0 ]; then
	echo "The 'curl' command is either not installed or not on the PATH ..."

	if [ $DEPS = "true" ]; then
	    echo "Installing curl ..."

	    if [ $DISTRO = "Ubuntu" ] || [ $DISTRO = "Debian" ]; then
		sudo $APT_CMD update > /dev/null
		sudo $APT_CMD install curl

	    elif [ $DISTRO = "CentOS" ]; then
		if [ $MACHINE = "i686" ]; then
		    sudo $YUM_CMD install curl.i686
		fi

		if [ $MACHINE = "x86_64" ]; then
		    sudo $YUM_CMD install curl.x86_64
		fi
	    fi
	else
	    echo "To automatically install required components for Meter Install, rerun setup_meter.sh with -d flag."
	    exit 1
	fi
    fi

    if [ $DISTRO = "Ubuntu" ] || [ $DISTRO = "Debian" ]; then
	test -f /usr/lib/apt/methods/https
	if [ $? -gt 0 ];then
	    echo "apt-transport-https is not installed to access Boundary's HTTPS based APT repository ..."

	    if [ $DEPS = "true" ]; then
		echo "Installing apt-transport-https ..."
		sudo $APT_CMD update > /dev/null
		sudo $APT_CMD install apt-transport-https
	    else
		echo "To automatically install required components for Meter Install, rerun setup_meter.sh with -d flag."
		exit 1
	    fi
	fi
    fi
}

# Grab some system information
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


while getopts "h di:" opts; do
    case $opts in
	h) print_help;;
	d) DEPS="true";;
	i) APICREDS="$OPTARG";;
	[?]) print_help;;
    esac
done

if [ -z $APICREDS ]; then
    print_help
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
    echo "This is an unsupported platform for the Boundary Meter."
    echo "Please contact support@boundary.com to request support for this architecture."
    exit 1
fi

# Check the distribution
for d in ${PLATFORMS[*]} ; do
    if [ $DISTRO = $d ]; then
	SUPPORTED_PLATFORM=1
	break
    fi
done
if [ $SUPPORTED_PLATFORM -eq 0 ]; then
    print_supported_platforms
fi

# Check the version number
check_distro_version "$PLATFORM" $DISTRO
if [ $? -ne 0 ]; then
    print_supported_platforms
fi

echo "Detected $DISTRO $VERSION..."
echo ""

# At this point, we think we have a supported OS.
pre_install_sanity $d $v

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

do_install

if [ $? -ne 0 ]; then
    echo "Part of the installation failed. Please contact support@boundary.com"
    exit 1
fi
