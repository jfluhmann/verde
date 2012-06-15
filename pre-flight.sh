#!/bin/bash

echo ""
# We need to run this script with root privileges
if [ "$EUID" != "0" ] ; then
  echo "This script must be run with root privileges....exiting"
  exit 1
fi

# Is the CPU virtualization capable?
###### Using most of kvm-ok - Begin kvm-ok based code here....
# kvm-ok - check whether the CPU we're running on supports KVM acceleration
# Copyright (C) 2008-2010 Canonical Ltd.
#
# Authors:
#  Dustin Kirkland <kirkland@canonical.com>
#  Kees Cook <kees.cook@canonical.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3,
# as published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# check cpu flags for capability
virt=$(egrep -m1 -w '^flags[[:blank:]]*:' /proc/cpuinfo | egrep -wo '(vmx|svm)') || true
[ "$virt" = "vmx" ] && brand="intel"
[ "$virt" = "svm" ] && brand="amd"

if [ -z "$virt" ]; then
	echo "INFO: Your CPU does not support KVM extensions"
	echo "This server cannot be a VDI node (but could be a Management Console or Gateway)"
	exit 1
fi

# Now, check that the device exists
if [ -e /dev/kvm ]; then
	echo "INFO: /dev/kvm exists"
	echo "KVM acceleration can be used"
else
	echo "INFO: /dev/kvm does not exist"
	echo "HINT:   sudo modprobe kvm_$brand"
	echo "HINT:   Then re-run this script if modprobe doesn't return errors"
	echo "Failing the above HINT, enter your BIOS setup and verify that "
	echo "      Virtualization Technology (VT) is enabled,"
	echo "      and then hard poweroff/poweron your system"
	exit 1
fi

# Prepare MSR access
msr="/dev/cpu/0/msr"
if [ ! -r "$msr" ]; then
	modprobe msr
fi

echo "INFO: Your CPU supports KVM extensions"

disabled=0
# check brand-specific registers
if [ "$virt" = "vmx" ]; then
        BIT=$(rdmsr --bitfield 0:0 0x3a 2>/dev/null || true)
        if [ "$BIT" = "1" ]; then
                # and FEATURE_CONTROL_VMXON_ENABLED_OUTSIDE_SMX clear (no tboot)
                BIT=$(rdmsr --bitfield 2:2 0x3a 2>/dev/null || true)
                if [ "$BIT" = "0" ]; then
			disabled=1
                fi
        fi

elif [ "$virt" = "svm" ]; then
        BIT=$(rdmsr --bitfield 4:4 0xc0010114 2>/dev/null || true)
        if [ "$BIT" = "1" ]; then
		disabled=1
        fi
else
	echo "FAIL: Unknown virtualization extension: $virt"
	echo "KVM acceleration can NOT be used"
	echo "This server cannot be a VDI node (but could be a Management Console or Gateway)"
	exit 1
fi

if [ "$disabled" -eq 1 ]; then
	echo "INFO: KVM ($virt) is disabled by your BIOS"
	echo "HINT: Enter your BIOS setup and enable Virtualization Technology (VT),"
	echo "      and then hard poweroff/poweron your system"
	exit 1
fi
#.... End kvm-ok based code here
#####

# Architecture needs to be 64-bit
ARCH=$(uname -m)  # Should be x86_64
if [ $ARCH != 'x86_64' ]; then
    echo "VERDE requires 64-bit architecture....exiting"; echo ""
    exit 1
fi

# What distro are we running?
if [ -f /etc/lsb-release ]; then
    export DISTRO=$(lsb_release -i | awk -F: '{print $2}' | sed -e 's/\t//')  # Should be Ubuntu
    export RELEASE=$(lsb_release -r | awk -F: '{print $2}' | sed -e 's/\t//') # Should be 10.04
elif [ -f /etc/redhat-release ]; then
    export DISTRO=$(cat /etc/redhat-release | sed s/\ release.*//)                     # CentOS returns CentOS  (need to test RedHat)
    export RELEASE=$(cat /etc/redhat-release | sed s/.*release\ // | sed s/\ .*//)     # CentOS returns 6.2     (need to test RedHat)
else
    echo "You need one of the following OSes"
    echo "Ubuntu 10.04"
    echo "RHEL/CentOS 6.x"
    echo "....exiting"; echo ""
    exit 1
fi
MAJOR=$(echo $RELEASE | awk -F. '{print $1}')

echo "Distribution:  $DISTRO"
echo "Release:       $RELEASE"

case $DISTRO in
    'Ubuntu')
        if [ $MAJOR != '10' ]; then
            echo "VERDE requires Ubuntu 10.04....exiting"; echo ""
            exit 1
        fi
        # Do Ubuntu specific tasks
        # - OS updates
        echo "Updating OS...."
        apt-get update > /dev/null 2>&1 && apt-get upgrade -y > /dev/null 2>&1
        
        # - VERDE required packages
        echo "Installing packages needed by VERDE"
        apt-get remove -y chkconfig
        apt-get install -y libaio1 libpng12-0 libjpeg62 libsm6 libice6 libxt6 zip
        apt-get install -y openjdk-6-jre ghostscript
        VERDE_PKG="verde_5.5-r550.16048_amd64.deb"
        ;;
    'CentOS')
        if [ $MAJOR != '6' ]; then
            echo "VERDE requires CentOS 6.x ....exiting"; echo ""
            exit 1
        fi
        # Do CentOS specific tasks
        # disable SELinux
        setenforce 0
        sed -i -e 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
        sed -i -e 's/SELINUX=permissive/SELINUX=disabled/' /etc/selinux/config
        
        # turn off firewall (or make appropriate adjustments??)
        service iptables save
        service iptables stop
        chkconfig iptables off
        
        # - OS updates
        echo "Updating OS...."
        # Suppress the noise - need simple progress indicator #####
        yum upgrade -y > /dev/null 2>&1
        yum -y install wget > /dev/null 2>&1
        
        # - VERDE required packages
        echo "Installing packages needed by VERDE"
        yum install -y libaio libXrandr libXfixes zip
        yum install -y java-1.6.0 ghostscript
        VERDE_PKG="VERDE-5.5-r550.16048.x86_64.rpm"
        
        ;;
    *)
        echo "You need one of the following OSes"
        echo "Ubuntu 10.04"
        echo "RHEL/CentOS 6.x"
        echo "....exiting"; echo ""
        exit 1
esac
VERDE_LINK="http://vbridges.com/pub/pkg/linux/5.5SP5/$VERDE_PKG"

# Create the mcadmin1 and vb-verde users/groups
# Need to do some checking for the existence of vb-verde user/group
VBGID=$(egrep "^vb-verde" /etc/group | awk -F: '{print $3}')
VBUID=$(egrep "^vb-verde" /etc/passwd | awk -F: '{print $3}')
if [ -z $VBGID ]; then
    VBGID=$(awk -F: '{uid[$3]=1}END{for(x=5000; x<=5999; x++) {if(uid[x] != ""){}else{print x; exit;}}}' /etc/group)
    echo "Adding group vb-verde ($VBGID)"
    groupadd --gid $VBGID vb-verde
else
    echo "Group 'vb-verde' exists: GID=$VBGID"
fi

if [ -z $VBUID ]; then
    VBUID=$(awk -F: '{uid[$3]=1}END{for(x=5000; x<=5999; x++) {if(uid[x] != ""){}else{print x; exit;}}}' /etc/passwd)
    echo "Adding user vb-verde ($VBUID)"
    useradd -m --uid $VBUID --gid $VBGID vb-verde
else
    echo "User 'vb-verde' exists: UID=$VBUID"
fi


# Need to do some checking for the existence of mcadmin1 user/group
MCGID=$(egrep "^mcadmin1" /etc/group | awk -F: '{print $3}')
MCUID=$(egrep "^mcadmin1" /etc/passwd | awk -F: '{print $3}')
if [ -z $MCGID ]; then
    MCGID=$(awk -F: '{uid[$3]=1}END{for(x=6000; x<=6999; x++) {if(uid[x] != ""){}else{print x; exit;}}}' /etc/group)
    echo "Adding group mcadmin1 ($MCGID)"
    groupadd --gid $MCGID mcadmin1
else
    echo "Group 'mcadmin1' exists: GID=$MCGID"
fi

if [ -z $MCUID ]; then
    MCUID=$(awk -F: '{uid[$3]=1}END{for(x=6000; x<=6999; x++) {if(uid[x] != ""){}else{print x; exit;}}}' /etc/passwd)
    echo "Adding user mcadmin1 ($MCUID)"
    useradd -m --uid $MCUID --gid $MCGID mcadmin1
    echo "Please set the password for the MC User - mcadmin1"
    passwd mcadmin1
    #echo "Please enter a password for the mcadmin1 user: "
    #read PW
    #PW=mcadmin1
    #ENCPW=$(echo $PW|mkpasswd -s)
    #ENCPW=$(echo $PW| openssl passwd -1 -stdin)
    #useradd -m --uid $MCUID --gid $MCGID -p $ENCPW mcadmin1
else
    echo "User 'mcadmin1' exists: UID=$MCUID"
fi


# Download the VERDE package
download()
{
    local url=$1
    echo -n "    "
    wget --progress=dot $url 2>&1 | grep --line-buffered "%" | \
        sed -u -e "s,\.,,g" | awk '{printf("\b\b\b\b%4s", $2)}'
    echo -ne "\b\b\b\b"
    echo " DONE"
}

echo -n "Downloading $VERDE_PKG:"
download $VERDE_LINK
echo "Installing $VERDE_PKG"
case $DISTRO in
    'Ubuntu')
        dpkg -i $VERDE_PKG
        ;;
    'CentOS')
        rpm -ivh $VERDE_PKG
        ;;
    *)
        exit 1;
esac

# Show link to MC console at login prompt
# change TTY to show MC address
#cp /etc/issue /etc/issue-standard
# Create get-ip-address script
echo "ip addr show | grep -v vbinat0 | grep -v \"127.0.0.1\" | grep \"inet \" | awk '{ print \$2 }' | awk -F/ '{print \$1 }'" > /usr/local/bin/get-ip-address
chmod +x /usr/local/bin/get-ip-address
        
echo "To access the VERDE Management Console, please visit - https://$(/usr/local/bin/get-ip-address):8443/mc"
