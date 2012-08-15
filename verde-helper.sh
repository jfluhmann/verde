#!/bin/bash
set -- `getopt -n$0 -u -a --longoptions="uc-logout: uc-advanced: node-logging:" "h" "$@"` || usage 
[ $# -eq 0 ] && usage

usage() {
	echo "Usuage: $0 [OPTIONS]"
        echo
        echo "Options:"
        echo "    --uc-logout true|false        Sets auto-logout of user console after last session disconnects"
        echo "    --uc-advanced true|false      Enables/Disables advanced settings in user console, allowing"
        echo "                                  user to change connection settings in RDP,NX before connecting"
        echo "    --node-logging note|info      Set node logging information to note or info"
	exit 1;
}

check_root() {
	# We need to run this script with root privileges
	if [ "$EUID" != "0" ] ; then
	  echo "This script must be run with root privileges....exiting"
	  exit 1
	fi
}

UC_PROPERTIES_FILE="/usr/lib/verde/etc/apache-tomcat/webapps/VIA/WEB-INF/classes/uc.properties"
SETTINGS_CLUSTER_FILE="/home/vb-verde/.verde-local/settings.cluster"
SETTINGS_NODE_FILE="/var/lib/verde/settings.node"

while [ $# -gt 0 ]
do
    case "$1" in
       --uc-logout)   
           uc_logout=$2;shift
           check_root
           chmod 666 $UC_PROPERTIES_FILE
           if [ $uc_logout = "true" ] || [ $uc_logout = "false" ]; then
               if [ -f $UC_PROPERTIES_FILE ]; then
                   echo "Setting logout on disconnect to $uc_logout"
                   sed -i "s/^logout.ondissconnect = [[:alpha:]]*/logout.ondissconnect = $uc_logout/" $UC_PROPERTIES_FILE
               else
                   echo "Cannont find $UC_PROPERTIES_FILE.  Is VERDE installed?"; exit 1;
               fi
           else
               usage
           fi
           chmod 444 $UC_PROPERTIES_FILE
           ;;
       --uc-advanced) 
           uc_advanced=$2;shift
           check_root
           if [ $uc_advanced = "true" ]; then
               mode="yes"
           elif [ $uc_advanced = "false" ]; then
               mode="no"
           else
               usage
           fi
           if [ -f $SETTINGS_CLUSTER_FILE ]; then
               if [ $(egrep -c "UC_ADVANCED_MODE" $SETTINGS_CLUSTER_FILE) -gt 0 ]; then
                   # UC_ADVANCED_MODE exists.  change the value
                   echo "Changing UC_ADVANCED_MODE to $mode"
                   sed -i "s/^UC_ADVANCED_MODE=\"*[[:alpha:]]*\"*/UC_ADVANCED_MODE=\"$mode\"/" $SETTINGS_CLUSTER_FILE
               else
                   # UC_ADVANCED_MODE does not exist.  Add it
                   echo "Adding UC_ADVANCED_MODE with value set to $mode"
                   cat "UC_ADVANCED_MODE=\"$mode\"" >> $SETTINGS_CLUSTER_FILE
               fi
           else
               echo "Cannot find $SETTINGS_CLUSTER_FILE.  Is VERDE installed?"; exit 1
           fi
           ;;
       --node-logging)
           node_logging=$2;shift
           check_root
           if [ -f $SETTINGS_NODE_FILE ]; then
               if [ $node_logging = "note" ] || [ $node_logging = "info" ]; then
                   echo "Setting WIN4_DBG_MOD_ALL to $node_logging"
                   sed -i "s/^WIN4_DBG_MOD_ALL=\"*[[:alpha:]]*\"*/WIN4_DBG_MOD_ALL=\"$node_logging\"/" $SETTINGS_NODE_FILE
               else
                   usage
               fi
           else
               echo "Cannot find $SETTINGS_NODE_FILE.  Is VERDE installed?"; exit 1
           fi
           ;;
       -h)        usage;;
       --)        shift;break;;
       -*)        usage;;
       *)         break;;            #better be the crawl directory
    esac
    shift
done

