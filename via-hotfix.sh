#!/usr/bin/env bash

VIA_FIX="http://www.vbridges.com/pub/pkg/linux/5.5SP5/fixpacks/VIA.war"

check_root() {
    # We need to run this script with root privileges
    if [ "$EUID" != "0" ] ; then
        echo "This script must be run with root privileges....exiting"
        exit 1
    fi
}

check_root

# Install wget if not installed yet
yum -y install wget

DOWNLOAD_LOCATION=$(pwd)
echo "Dowload location = $DOWNLOAD_LOCATION"

# Download VIA hotfix
echo "Downloading hotfix...."
wget $VIA_FIX

# Stop Tomcat
echo "Stopping Tomcat...."
/usr/lib/verde/bin/verde-start-tomcat.sh stop

# Change into the webapps folder
cd /usr/lib/verde/etc/apache-tomcat/webapps/

# Backup or move the current "VIA" folder
mv VIA /tmp/

# Remove the existing folder: rm -rf VIA
rm -rf VIA

# Copy the new VIA.war to the webapps folder
echo "Extracting new VIA folder...."
unzip $DOWNLOAD_LOCATION/VIA.war -d VIA/

# Start Tomcat
echo "Starting Tomcat...."
/usr/lib/verde/bin/verde-start-tomcat.sh start

