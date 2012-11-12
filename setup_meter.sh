#!/bin/bash
set -o pipefail

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

# ARCHS=("i686" "x86_64")
PLATFORMS=("Ubuntu" "Debian" "CentOS")

# Put additional version numbers here.
# These variables take the form ${platform}_VERSIONS, where $platform matches
# the tags in $PLATFORMS
Ubuntu_VERSIONS=("10.04" "10.10" "11.04" "11.10" "12.04")
Debian_VERSIONS=("5" "6")
CentOS_VERSIONS=("5" "6")

# sed strips out obvious things in a version number that can't be used as
# a bash variable
function map() { eval "$1"`echo $2 | sed 's/[\. -]//g'`='$3' ; }
function get() { eval echo '${'"$1`echo $2 | sed 's/[\. -]//g'`"'#hash}' ; }

# Map distributions to common strings.
map Ubuntu 10.04 lucid
map Ubuntu 10.10 maverick
map Ubuntu 11.04 natty
map Ubuntu 11.10 oneiric
map Ubuntu 12.04 precise
map Debian 5 lenny
map Debian 6 squeeze

# For version number updates you hopefully don't need to modify below this line
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
    echo "Supported platforms are:"
    for d in ${PLATFORMS[*]}
    do
        echo -n " * $d:"
        foo="\${${d}_VERSIONS[*]}"
        versions=`eval echo $foo`
        for v in $versions
        do
            echo -n " $v"
        done
        echo ""
    done
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
    echo "   $0 [-d] -i ORGID:APIKEY"
    echo "      -i: Required input for authentication. The ORGID and APIKEY can be found"
    echo "          in the Account Settings in the Boundary WebUI."
    echo "      -d: Optional flag to install all dependencies, such as curl and"
    echo "          apt-transport-https, required for Meter Install."
    exit 0
}

function create_meter() {

    RESULT=`$CURL --connect-timeout 5 -i -s -X POST \
        -H "Content-Type: application/json" \
        -d "{\"name\": \"$HOSTNAME\"}" -u "$1:" \
        https://$APIHOST/$2/meters \
        | tr -d "\r" \
        | awk '/^HTTP\/1\./ {split($0,a," "); http=a[2]} /^Location: https:\/\// {split($0,a," "); url=a[2]} END {print http; print url}'`

    exit_status=$?

    # an exit status of 1 indicates an unsupported protocol. (e.g.,
    # https hasn't been baked in.)
    if [ "$exit_status" -eq "1" ]; then
        echo "Your local version of curl has not been built with HTTPS support: `which curl`"
        exit 1

    # if the exit code is 7, that means curl couldnt connect so we can bail
    elif [ "$exit_status" -eq "7" ]; then
        echo "Could not connect to create meter"
        exit 1

    # it appears that an exit code of 28 is also a can't connect error
    elif [ "$exit_status" -eq "28" ]; then
        echo "Could not connect to create meter"
        exit 1

    elif [ "$exit_status" -ne "0" ]; then
        echo "Error connecting to $APIHOST; status $exit_status."
        exit 1
    fi

    STATUS=`echo $RESULT | awk '{print $1}'`

    if [ "$STATUS" = "" ]; then
        echo "Unknown error communicating with $APIHOST."
        exit 1

    elif [ "$STATUS" = "401" ]; then
        echo "Authentication error, bad Org ID or API key (http status $STATUS)."
        echo "Verify that you have passed in the correct credentials.  The ORGID and APIKEY"
        echo "can be found in the Account Settings in the Boundary WebUI."
        exit 1

    elif [ "$STATUS" = "403" ]; then
        echo "Forbidden error (http status $STATUS)."
        echo "Verify that you have not exceeded your meter limit."
        echo "If you haven't, please contact support at support@boundary.com."
        exit 1

    else
        if [ "$STATUS" = "201" ] || [ "$STATUS" = "409" ]; then
            echo $RESULT | awk '{print $2}'
        else
            echo "An Error occurred during the meter creation (http status $STATUS)."
            echo "Please contact support at support@boundary.com."
            exit 1
        fi
    fi
}

function do_install() {
    if [ "$DISTRO" = "Ubuntu" ]; then
        sudo $APT_CMD update > /dev/null

        APT_STRING="deb https://apt.boundary.com/ubuntu/ `get $DISTRO $MAJOR_VERSION.$MINOR_VERSION` universe"
        echo "Adding repository $APT_STRING"
        sudo sh -c "echo \"$APT_STRING\" > /etc/apt/sources.list.d/boundary.list"

        $CURL -s https://$APT/APT-GPG-KEY-Boundary | sudo apt-key add -
        if [ $? -gt 0 ]; then
            echo "Error downloading GPG key from https://$APT/APT-GPG-KEY-Boundary!"
            exit 1
        fi

        sudo $APT_CMD update > /dev/null
        sudo $APT_CMD install bprobe
        return $?
    elif [ "$DISTRO" = "Debian" ]; then
        sudo $APT_CMD update > /dev/null

        APT_STRING="deb https://apt.boundary.com/debian/ `get $DISTRO $MAJOR_VERSION` main"
        echo "Adding repository $APT_STRING"
        sudo sh -c "echo \"$APT_STRING\" > /etc/apt/sources.list.d/boundary.list"

        $CURL -s https://$APT/APT-GPG-KEY-Boundary | sudo apt-key add -
        if [ $? -gt 0 ]; then
            echo "Error downloading GPG key from https://$APT/APT-GPG-KEY-Boundary!"
            exit 1
        fi

        sudo $APT_CMD update > /dev/null
        sudo $APT_CMD install bprobe
        return $?
    elif [ "$DISTRO" = "CentOS" ]; then
        GPG_KEY_LOCATION=/etc/pki/rpm-gpg/RPM-GPG-KEY-Boundary
        if [ $MACHINE = "i686" ]; then
            ARCH_STR="i386/"
        elif [ $MACHINE = "x86_64" ]; then
            ARCH_STR="x86_64/"
        fi

        echo "Adding repository http://yum.boundary.com/centos/os/$MAJOR_VERSION/$ARCH_STR"

        sudo sh -c "cat - > /etc/yum.repos.d/boundary.repo <<EOF
[boundary]
name=boundary
baseurl=http://yum.boundary.com/centos/os/$MAJOR_VERSION/$ARCH_STR
gpgcheck=1
gpgkey=file://$GPG_KEY_LOCATION
enabled=1
EOF"

        $CURL -s https://$YUM/RPM-GPG-KEY-Boundary | sudo tee /etc/pki/rpm-gpg/RPM-GPG-KEY-Boundary > /dev/null
        if [ $? -gt 0 ]; then
            echo "Error downloading GPG key from https://$YUM/RPM-GPG-KEY-Boundary!"
            exit 1
        fi

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
        $CURL -s -u $1: $2/key.pem | sudo tee $TARGET_DIR/key.pem > /dev/null

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
        $CURL -s -u $1: $2/cert.pem | sudo tee $TARGET_DIR/cert.pem > /dev/null

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

    EC2=`$CURL -s --connect-timeout 5 "$EC2_INTERNAL"`
    exit_code=$?

    if [ "$exit_code" -eq "0" ]; then
        # check to see if we *really* are on EC2
        $CURL -is --connect-timeout 5 "$EC2_INTERNAL" | grep 'Server: EC2ws' > /dev/null
        exit_code=$?

        if [ "$exit_code" -eq "0" ]; then
            echo -n "Auto generating ec2 tags for this meter...."
        else
            return 0
        fi
    else
        return 0
    fi

    for tag in $TAGS; do
        local AN_TAG
        local exit_code

        AN_TAG=`$CURL -s --connect-timeout 5 "$EC2_INTERNAL/$tag"`
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
            $CURL -H "Content-Type: application/json" -s -u "$1:" -X PUT "$2/tags/$an_tag"
        done
    done

    $CURL -H "Content-Type: application/json" -s -u "$1:" -X PUT "$2/tags/ec2"
    echo "done."
}

function pre_install_sanity() {
    SUDO=`which sudo`
    if [ $? -ne 0 ]; then
        echo "This script requires that sudo be installed and configured for your user."
        echo "Please install sudo. For assistance, support@boundary.com"
        exit 1
    fi

    which curl > /dev/null
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
            echo "To automatically install required components for Meter Install, rerun $0 with -d flag."
            exit 1
        fi
    fi
    CURL="`which curl` --sslv3"

    if [ $DISTRO = "Ubuntu" ] || [ $DISTRO = "Debian" ]; then
        test -f /usr/lib/apt/methods/https
        if [ $? -gt 0 ];then
            echo "apt-transport-https is not installed to access Boundary's HTTPS based APT repository ..."

            if [ $DEPS = "true" ]; then
                echo "Installing apt-transport-https ..."
                sudo $APT_CMD update > /dev/null
                sudo $APT_CMD install apt-transport-https
            else
                echo "To automatically install required components for Meter Install, rerun $0 with -d flag."
                exit 1
            fi
        fi
    fi
}

# Grab some system information
if [ -f /etc/redhat-release ] ; then
    PLATFORM=`cat /etc/redhat-release`
    DISTRO=`echo ${PLATFORM:0:6}`
    VERSION=`echo ${PLATFORM:15:3}`
    MACHINE=`uname -m`
elif [ -f /etc/lsb-release ] ; then
    #Ubuntu version lsb-release - https://help.ubuntu.com/community/CheckingYourUbuntuVersion
    . /etc/lsb-release
    PLATFORM=$DISTRIB_DESCRIPTION
    DISTRO=$DISTRIB_ID
    VERSION=$DISTRIB_RELEASE
    MACHINE=`uname -m`
elif [ -f /etc/debian_version ] ; then
    #Debian Version /etc/debian_version - Source: http://www.debian.org/doc/manuals/debian-faq/ch-software.en.html#s-isitdebian
    PLATFORM=`cat /etc/debian_version | head -n 1`
    DISTRO=`echo $PLATFORM | awk '{print $1}'`
    MACHINE=`uname -m`
else
    PLATFORM="unknown"
    DISTRO="unknown"
    MACHINE=`uname -m`
fi


while getopts "h di:f:" opts; do
    case $opts in
        h) print_help;;
        d) DEPS="true";;
        i) APICREDS="$OPTARG";;
        f) echo "WARNING! You are OVERRIDING this script's OS detection."
           echo "On unsupported platforms, your mileage may vary!"
           print_supported_platforms
           echo "Please contact support@boundary.com to request support for your architecture."

           # This takes input basically of the form
           # "`cat /etc/issue | head -n1`", for the OS you're mimicking.
           # Examples include "CentOS release 6.2"; "Ubuntu 11.10".
           PLATFORM="$OPTARG"
           DISTRO=`echo $PLATFORM | awk '{print $1}'`

           echo "Script will masquerade as \"$PLATFORM\""
           ;;
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
    echo "Your platform is not supported."
    print_supported_platforms
    exit 0
fi

# Check the version number
check_distro_version "$PLATFORM" $DISTRO
if [ $? -ne 0 ]; then
    echo "This version is not supported."
    print_supported_platforms
    exit 0
fi

echo "Detected $DISTRO $VERSION..."
echo ""

# At this point, we think we have a supported OS.
pre_install_sanity $d $v

METER_LOCATION=`create_meter $APIKEY $APIID`

if [ $? -gt 0 ]; then
    echo "Error creating meter:"
    echo "$METER_LOCATION"
    echo "Please contact support@boundary.com"
    exit 1
fi

KEY_CERT=`setup_cert_key $APIKEY $METER_LOCATION`
if [ $? -eq 1 ]; then
    echo "Error setting up cert and/or key ..."
    echo "Please contact support@boundary.com"
    echo $KEY_CERT
    exit 1
fi

CERT_KEY_CHECK=`cert_key_check`

if [ $? -eq 1 ]; then
    echo "Error setting up cert and/or key ..."
    echo "Please contact support@boundary.com"
    echo $CERT_KEY_CHECK
    exit 1
fi

ec2_tag $APIKEY $METER_LOCATION

do_install

if [ $? -ne 0 ]; then
    echo "I added the correct repositories, but the meter installation failed."
    echo "Please contact support@boundary.com about this problem."
    exit 1
fi


echo ""
echo "The meter has been installed successfully!"
