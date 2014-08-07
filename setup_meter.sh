#!/usr/bin/env bash
set -o pipefail

##
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

PLATFORMS=("Ubuntu" "Debian" "CentOS" "Amazon" "RHEL" "SmartOS" "openSUSE" "FreeBSD" "LinuxMint" "Gentoo" "Oracle")

# Put additional version numbers here.
# These variables take the form ${platform}_VERSIONS, where $platform matches
# the tags in $PLATFORMS
Ubuntu_VERSIONS=("10.04" "10.10" "11.04" "11.10" "12.04" "12.10" "13.04" "13.10" "14.04")
Debian_VERSIONS=("5" "6" "7")
CentOS_VERSIONS=("5" "6")
Amazon_VERSIONS=("2012.09" "2013.03")
RHEL_VERSIONS=("5" "6")
SmartOS_VERSIONS=("1" "12" "13")
openSUSE_VERSIONS=("12.1" "12.3" "13.1")
FreeBSD_VERSIONS=("8.2-RELEASE 8.3-RELEASE 8.4-RELEASE 9.0-RELEASE 9.1-RELEASE 9.2-RELEASE")
LinuxMint_VERSIONS=("13", "14", "15", "16")
Gentoo_VERSIONS=("1.12.11.1")
Oracle_VERSIONS=("5" "6")

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
map Ubuntu 12.10 quantal
map Ubuntu 13.04 raring
map Ubuntu 13.10 saucy
map Ubuntu 14.04 trusty
map Debian 5 lenny
map Debian 6 squeeze
map Debian 7 wheezy
map RHEL 5 Tikanga
map RHEL 6 Santiago

# For version number updates you hopefully don't need to modify below this line
# -----------------------------------------------------------------------------

APIHOST="api.boundary.com"
APICREDS=
TARGET_DIR="/etc/bprobe"

METERTAGS=

SUPPORTED_ARCH=0
SUPPORTED_PLATFORM=0

APT="apt.boundary.com"
YUM="yum.boundary.com"
SMARTOS="smartos.boundary.com"
FREEBSD="freebsd.boundary.com"
GENTOO="gentoo.boundary.com"

APT_CMD="apt-get -q -y --force-yes"
YUM_CMD="yum -d0 -e0 -y"

STAGING="false"

trap "exit" INT TERM EXIT

function print_supported_platforms() {
	echo
    echo "Supported platforms by the installation script are:"
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

EC2_INTERNAL="http://169.254.169.254/latest/meta-data"
EC2_TAGS="instance-type placement/availability-zone"
EC2_DESC_TAGS=
which euca-describe-tags > /dev/null 2>&1
if [ $? -eq 0 ]; then
    EC2_DESC_TAGS=euca-describe-tags
else
    which ec2-describe-tags > /dev/null 2>&1
    if [ $? -eq 0 ]; then
	    EC2_DESC_TAGS=ec2-describe-tags
    fi
fi

function ec2_find_tags() {
    echo -n "Checking this is an ec2 environment..."
    EC2=`curl -s --connect-timeout 5 "$EC2_INTERNAL"`
    exit_code=$?

    if [ "$exit_code" -eq "0" ]; then
        echo "yes."
        echo "Auto generating ec2 tags for this meter."
    else
        echo "no."
        return 0
    fi

    METERTAGS=ec2

    for tag in $EC2_TAGS; do
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
            METERTAGS=$METERTAGS,$an_tag
        done
    done

    # extract additional tags if the commands and access variables are set
    if [ -n "$EC2_DESC_TAGS" -a -n "$EC2_ACCESS_KEY" -a -n "$EC2_SECRET_KEY" -a -n "$EC2_URL" ]; then
        for an_tag in `${EC2_DESC_TAGS} --filter "resource-id=\`curl -s http://169.254.169.254/latest/meta-data/instance-id\`" | grep -v Name | sed 's/[ \t]/ /g' | cut -d " " -f 5-`; do
            METERTAGS=$METERTAGS,$an_tag
        done
    fi
    echo Discovered ec2 tags: $METERTAGS
}

function check_distro_version() {
    PLATFORM=$1
    DISTRO=$2
    VERSION=$3

    TEMP="\${${DISTRO}_versions[*]}"
    VERSIONS=`eval echo $TEMP`
    VERSION_CMP=

    if [ $DISTRO = "Ubuntu" ]; then
        MAJOR_VERSION=`echo $VERSION | awk -F. '{print $1}'`
        MINOR_VERSION=`echo $VERSION | awk -F. '{print $2}'`
        VERSION_CMP=$MAJOR_VERSION.$MINOR_VERSION

    elif [ $DISTRO = "CentOS" ] || [ $DISTRO = "RHEL" ] || [ $DISTRO = "Oracle" ]; then
        MAJOR_VERSION=`echo $VERSION | awk -F. '{print $1}'`
        VERSION_CMP=$MAJOR_VERSION

    elif [ $DISTRO = "Amazon" ]; then
        VERSION=`echo $PLATFORM | awk '{print $5}'`
        # Some of these include minor numbers. Trim.
        VERSION_CMP=${VERSION:0:7}

    elif [ $DISTRO = "Debian" ]; then
        MAJOR_VERSION=`echo $VERSION | awk -F. '{print $1}'`
        VERSION_CMP=$MAJOR_VERSION
	else
        VERSION_CMP=$VERSION
    fi

    TEMP="\${${DISTRO}_VERSIONS[*]}"
    VERSIONS=`eval echo $TEMP`
    for v in $VERSIONS ; do
        if [ "$VERSION_CMP" = "$v" ]; then
            return 0
        fi
    done

    echo "Detected $DISTRO but with an untested version ($VERSION)"
    return 1
}

function print_help() {
    echo "   $0 [-s] -i ORGID:APIKEY"
    echo "      -i: Required input for authentication. The ORGID and APIKEY can be found"
    echo "          in the Account Settings in the Boundary WebUI."
    echo "      -s: Install the latest testing meter from the staging repositories"
    exit 0
}

function do_install() {
    export INSTALLTOKEN="${APICREDS}"
    export PROVISIONTAGS="${METERTAGS}"
    if [ "$DISTRO" = "Ubuntu" ] || [ $DISTRO = "Debian" ]; then
		APT_STRING="deb https://${APT}/ubuntu/ `get $DISTRO $MAJOR_VERSION.$MINOR_VERSION` universe"
		if [ "$DISTRO" = "Debian" ]; then
			APT_STRING="deb https://${APT}/debian/ `get $DISTRO $MAJOR_VERSION` main"
		fi
        echo "Adding repository $APT_STRING"
        sh -c "echo \"$APT_STRING\" > /etc/apt/sources.list.d/boundary.list"

        $CURL -s https://${APT}/APT-GPG-KEY-Boundary | apt-key add -
        if [ $? -gt 0 ]; then
            echo "Error downloading GPG key from https://${APT}/APT-GPG-KEY-Boundary!"
            exit 1
        fi

        echo "Updating apt repository cache..."
        $APT_CMD update > /dev/null
        $APT_CMD install bprobe
        return $?

    elif [ "$DISTRO" = "openSUSE" ]; then
        ARCH_STR="x86_64/"

        $CURL -s https://$YUM/RPM-GPG-KEY-Boundary > RPM-GPG-KEY-Boundary
        if [ $? -gt 0 ]; then
            echo "Error downloading GPG key from https://$YUM/RPM-GPG-KEY-Boundary!"
            exit 1
        fi
        rpm --import ./RPM-GPG-KEY-Boundary

        echo "Adding repository http://${YUM}/opensuse/os/$VERSION/$ARCH_STR"
        zypper addrepo -c -k -f -g http://${YUM}/opensuse/os/$VERSION/$ARCH_STR boundary

        zypper install -y bprobe
        return $?

    elif [ "$DISTRO" = "CentOS" ] || [ $DISTRO = "Amazon" ] || [ $DISTRO = "RHEL" ] || [ $DISTRO = "Oracle" ]; then
        GPG_KEY_LOCATION=/etc/pki/rpm-gpg/RPM-GPG-KEY-Boundary
        if [ "$MACHINE" = "i686" ]; then
            ARCH_STR="i386/"
        elif [ "$MACHINE" = "x86_64" ]; then
            ARCH_STR="x86_64/"
        fi

        # Amazon hack: we know the Amazon Linux AMIs are binary
        # compatible with CentOS
        if [ $DISTRO = "Amazon" ]; then
            MAJOR_VERSION=6
        fi

        echo "Adding repository http://${YUM}/centos/os/$MAJOR_VERSION/$ARCH_STR"

        sh -c "cat - > /etc/yum.repos.d/boundary.repo <<EOF
[boundary]
name=boundary
baseurl=http://${YUM}/centos/os/$MAJOR_VERSION/$ARCH_STR
gpgcheck=1
gpgkey=file://$GPG_KEY_LOCATION
enabled=1
EOF"

        $CURL -s https://$YUM/RPM-GPG-KEY-Boundary | tee /etc/pki/rpm-gpg/RPM-GPG-KEY-Boundary > /dev/null
        if [ $? -gt 0 ]; then
            echo "Error downloading GPG key from https://$YUM/RPM-GPG-KEY-Boundary!"
            exit 1
        fi

        $YUM_CMD install bprobe
        return $?

    elif [ "$DISTRO" = "SmartOS" ]; then
      grep "http://${SMARTOS}/${MACHINE}" /opt/local/etc/pkgin/repositories.conf > /dev/null

      if [ "$?" = "1" ]; then
        echo "http://${SMARTOS}/${MACHINE}/" >> /opt/local/etc/pkgin/repositories.conf
      fi

      pkgin -fy up
      pkgin -y install bprobe
      # Enable promiscuous mode on SmartOS by default.
      # Non-promiscuous mode is not very useful because the OS only forwards
      # received traffic.
      if [ -f /opt/local/etc/bprobe/bprobe.default -a ! -f /opt/local/etc/bprobe/bprobe.defaults ]; then
          sed -e 's/PCAP_PROMISC=0/PCAP_PROMISC=1/' /opt/local/etc/bprobe/bprobe.default > /opt/local/etc/bprobe/bprobe.defaults
          rm /opt/local/etc/bprobe/bprobe.default
      fi
      svccfg import /opt/custom/smf/boundary-meter.xml
      svcadm enable boundary/meter
      return $?

    elif [ "$DISTRO" = "FreeBSD" ]; then
        fetch "https://${FREEBSD}/${VERSION:0:3}/${MACHINE}/bprobe-current.tgz"
        pkg_add bprobe-current.tgz
    elif [ "$DISTRO" = "Gentoo" ]; then
        if [ -e bprobe ]; then
	    echo
            echo "The installation script needs to create a 'bprobe' directory in the current"
	    echo "working directory for installation to proceed. Please run this script from"
	    echo "another location or remove the currently-existing 'bprobe' file or directory"
	    echo "and try again."
	    echo
            return 1
        fi
        mkdir bprobe
        (cd bprobe;
         wget "http://${GENTOO}/engineyard/latest"
         wget "http://${GENTOO}/engineyard/`cat latest`")
        ebuild --skip-manifest bprobe/`cat bprobe/latest` merge
        rm -fr bprobe
    fi
}

function pre_install_sanity() {
    if [ $DISTRO = "SmartOS" ]; then
      TARGET_DIR="/opt/local/etc/bprobe"
    fi

    which curl > /dev/null
    if [ $? -gt 0 ]; then
		echo "Installing curl ..."

		if [ $DISTRO = "Ubuntu" ] || [ $DISTRO = "Debian" ]; then
			echo "Updating apt repository cache..."
			$APT_CMD update > /dev/null
			$APT_CMD install curl

		elif [ $DISTRO = "CentOS" ] || [ $DISTRO = "Amazon" ] || [ $DISTRO = "RHEL" ] || [ $DISTRO = "Oracle" ]; then
			if [ "$MACHINE" = "i686" ]; then
				$YUM_CMD install curl.i686
			fi

			if [ "$MACHINE" = "x86_64" ]; then
				$YUM_CMD install curl.x86_64
			fi

		elif [ $DISTRO = "FreeBSD" ]; then
			pkg_add -r curl
		fi
    fi

    if [ $DISTRO = "SmartOS" ]; then
        CURL="`which curl` -k"
    else
        CURL="`which curl` --sslv3"
    fi

    if [ $DISTRO = "Ubuntu" ] || [ $DISTRO = "Debian" ]; then
        test -f /usr/lib/apt/methods/https
        if [ $? -gt 0 ];then
            echo "apt-transport-https is not installed to access Boundary's HTTPS based APT repository ..."
			echo "Updating apt repository cache..."
			$APT_CMD update > /dev/null
			echo "Installing apt-transport-https ..."
			$APT_CMD install apt-transport-https
        fi
    fi
}

# Grab some system information
if [ -f /etc/redhat-release ] ; then
    PLATFORM=`cat /etc/redhat-release`
    DISTRO=`echo $PLATFORM | awk '{print $1}'`
    if [ "$DISTRO" = "Fedora" ]; then
       DISTRO="RHEL"
       VERSION="6"
    else
       if [ "$DISTRO" != "CentOS" ]; then
           if [ "$DISTRO" = "Enterprise" ] || [ -f /etc/oracle-release ]; then
                # Oracle "Enterprise Linux"/"Linux"
                DISTRO="Oracle"
                VERSION=`echo $PLATFORM | awk '{print $7}'`
           elif [ "$DISTRO" = "Red" ]; then
                DISTRO="RHEL"
                VERSION=`echo $PLATFORM | awk '{print $7}'`
           else
                DISTRO="unknown"
                PLATFORM="unknown"
                VERSION="unknown"
           fi
       elif [ "$DISTRO" = "CentOS" ]; then
           VERSION=`echo $PLATFORM | awk '{print $3}'`
       fi
    fi
    MACHINE=`uname -m`
elif [ -f /etc/system-release ]; then
    PLATFORM=`cat /etc/system-release | head -n 1`
    DISTRO=`echo $PLATFORM | awk '{print $1}'`
    VERSION=`echo $PLATFORM | awk '{print $5}'`
    MACHINE=`uname -m`
elif [ -f /etc/lsb-release ] ; then
    #Ubuntu version lsb-release - https://help.ubuntu.com/community/CheckingYourUbuntuVersion
    . /etc/lsb-release
    PLATFORM=$DISTRIB_DESCRIPTION
    DISTRO=$DISTRIB_ID
    VERSION=$DISTRIB_RELEASE
    MACHINE=`uname -m`
    if [ "$DISTRO" = "LinuxMint" ]; then
       DISTRO="Ubuntu"
       VERSION="12.04"
    fi
elif [ -f /etc/debian_version ] ; then
    #Debian Version /etc/debian_version - Source: http://www.debian.org/doc/manuals/debian-faq/ch-software.en.html#s-isitdebian
    DISTRO="Debian"
    VERSION=`cat /etc/debian_version`
    INFO="$DISTRO $VERSION"
    PLATFORM=$INFO
    MACHINE=`uname -m`
elif [ -f /etc/os-release ] ; then
    . /etc/os-release
    PLATFORM=$PRETTY_NAME
    DISTRO=$NAME
    VERSION=$VERSION_ID
    MACHINE=`uname -m`
elif [ -f /etc/gentoo-release ] ; then
    PLATFORM="Gentoo"
    DISTRO="Gentoo"
    VERSION=`cat /etc/gentoo-release | cut -d ' ' -f 5`
    MACHINE=`uname -m`
else
    PLATFORM=`uname -sv | grep 'SunOS joyent'` > /dev/null
    if [ "$?" = "0" ]; then
      PLATFORM="SmartOS"
      DISTRO="SmartOS"
      MACHINE="i386"
      VERSION=13
      if [ -f /etc/product ]; then
        grep "base64" /etc/product > /dev/null
        if [ "$?" = "0" ]; then
            MACHINE="x86_64"
        fi
        VERSION=`grep 'Image' /etc/product | awk '{ print $3}' | awk -F. '{print $1}'`
      fi
    elif [ "$?" != "0" ]; then
        uname -sv | grep 'FreeBSD' > /dev/null
        if [ "$?" = "0" ]; then
            PLATFORM="FreeBSD"
            DISTRO="FreeBSD"
            VERSION=`uname -r`
            MACHINE=`uname -m`
        else
            uname -sv | grep 'Darwin' > /dev/null
            if [ "$?" = "0" ]; then
                PLATFORM="Darwin"
                DISTRO="OS X"
                VERSION=`uname -r`
                MACHINE=`uname -m`
            fi
        fi
    fi
fi

while getopts "hdsi:f:" opts; do
    case $opts in
        h) print_help;;
        s) STAGING="true";;
        i) APICREDS="$OPTARG";;
        f) echo "WARNING! You are OVERRIDING this script's OS detection."
           echo "On unsupported platforms, your mileage may vary!"
           print_supported_platforms
           echo "Please contact support@boundary.com to request support for your architecture."

           # This takes input basically of the form "OS VERSION" for the OS
           # you're mimicking.
           # E.g., "CentOS 6.2", "Ubuntu 11.10", etc.
           PLATFORM="$OPTARG"
           DISTRO=`echo $PLATFORM | awk '{print $1}'`
           VERSION=`echo $PLATFORM | awk '{print $2}'`

           echo "Script will masquerade as \"$PLATFORM\""
           ;;
        [?]) print_help;;
    esac
done

if [ $STAGING = "true" ]; then
    APT="apt-staging.boundary.com"
    YUM="yum-staging.boundary.com"
    SMARTOS="smartos-staging.boundary.com"
    FREEBSD="freebsd-staging.boundary.com"
    GENTOO="gentoo-staging.boundary.com"
fi

if [ "$MACHINE" = "i686" ] ||
   [ "$MACHINE" = "i586" ] ||
   [ "$MACHINE" = "i386" ] ; then
    ARCH="32"
    SUPPORTED_ARCH=1
fi

#determine hard vs. soft float using readelf
if [[ "$MACHINE" == arm* ]] ; then
	if [ -x /usr/bin/readelf ] ; then
		HARDFLOAT=`readelf -a /proc/self/exe | grep armhf`
		if [ -z "$HARDFLOAT" ]; then
			if [ "$MACHINE" = "armv7l" ] ||
			   [ "$MACHINE" = "armv6l" ] ||
			   [ "$MACHINE" = "armv5tel" ] ||
			   [ "$MACHINE" = "armv5tejl" ] ; then
				ARCH="32"
				SUPPORTED_ARCH=1
				echo "Detected $MACHINE running armel"
			fi
		else
			if [ "$MACHINE" = "armv7l" ] ; then
				ARCH="32"
				SUPPORTED_ARCH=1
				echo "Detected $MACHINE running armhf"
			else
				echo "$MACHINE with armhf ABI is not supported. Try the armel ABI"
			fi
		fi
	else
		echo "Cannot determine ARM ABI, please install the 'binutils' package"
	fi
fi

if [ "$MACHINE" = "x86_64" ] || [ "$MACHINE" = "amd64" ]; then
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
    if [ "$DISTRO" = "$d" ]; then
        SUPPORTED_PLATFORM=1
        break
    fi
done
if [ $SUPPORTED_PLATFORM -eq 0 ]; then
    echo "Your platform is not supported by this script at this time."
	echo "Please check https://app.boundary.com/docs/meter_install for alternate installation instructions."
    print_supported_platforms
    exit 1
fi


APIID=`echo $APICREDS | awk -F: '{print $1}'`
APIKEY=`echo $APICREDS | awk -F: '{print $2}'`
if [ "${#APIID}" -lt 10 -o "${#APIKEY}" -lt 10 ]; then
	echo "Please enter a valid installation token"
	echo "Expected APIID:APIKEY, got: '${APICREDS}'"
	echo

	print_help
fi

if [ -z $APICREDS ]; then
    print_help
fi

# If this script is being run by root for some reason, don't use sudo.
if [ "$(id -u)" != "0" ]; then
	SUDO=`which sudo`
	if [ $? -ne 0 ]; then
		echo "This script must be executed as the 'root' user or with sudo"
		echo "in order to install the Boundary meter."
		echo
		echo "Please install sudo or run again as the 'root' user."
		echo "For assistance, support@boundary.com"
		exit 1
	else
		sudo -E $0 $@
		exit 0
	fi
fi

echo "Detected $DISTRO $VERSION..."

# Check the version number
UNSUPPORTED_RELEASE=0
check_distro_version "$PLATFORM" $DISTRO $VERSION
if [ $? -ne 0 ]; then
    UNSUPPORTED_RELEASE=1
    echo "Detected $PLATFORM $DISTRO $VERSION"
fi

# The version number hasn't been found; let's just try and masquerade
# (and tell users what we're doing)
if [ $UNSUPPORTED_RELEASE -eq 1 ] ; then
    TEMP="\${${DISTRO}_VERSIONS[*]}"
    VERSIONS=`eval echo $TEMP`
    # Assume ordered list; grab latest version
    VERSION=`echo $VERSIONS | awk '{print $NF}'`
    MAJOR_VERSION=`echo $VERSION | awk -F. '{print $1}'`
    MINOR_VERSION=`echo $VERSION | awk -F. '{print $2}'`

    echo ""
    echo "Continuing; for reference, script is masquerading as: $DISTRO $VERSION"
    echo ""
fi

# At this point, we think we have a supported OS.
pre_install_sanity $d $v

ec2_find_tags

do_install

if [ $? -ne 0 ]; then
    echo "The meter installation failed."
    echo "For help, please contact support@boundary.com describing the problem."
    exit 1
fi

echo ""
echo "The meter has been installed successfully!"
