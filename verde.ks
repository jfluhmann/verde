# Example for installing VERDE and required packages

# Install OS instead of upgrade
install
# add: automatically proceed
autostep
# Firewall configuration
firewall --disabled

# Root password
rootpw --iscrypted "$1$V1naUAVE$810/g.9IvLfbylJ/qGiJJ1"
# System authorization information
auth  --useshadow  --passalgo=sha512
# Use text mode install
text
firstboot --disable

# System keyboard
keyboard us
# System language
lang en_US
# SELinux configuration
selinux --disabled
# Installation logging level
logging --level=info

# Reboot after installation
reboot
# System timezone
#timezone  --utc America/Chicago
timezone  --utc US/Eastern

# System bootloader configuration
bootloader --location=mbr --driveorder=sda --append="crashkernel=auto rhgb quiet"
#Clear the Master Boot Record
zerombr
# Partition clearing information
clearpart --all --initlabel 
autopart


# Network information
network --device eth0 --onboot yes --bootproto dhcp --hostname=verde01


%packages
@Base
@Core
system-config-network-tui
wget
unzip
libaio
libXrandr
libXfixes
java-1.6.0
ghostscript
ntp
%end

%pre
%end

%post
cd /root
wget https://raw.github.com/jfluhmann/verde/master/pre-flight.sh
chmod +x /root/pre-flight.sh
%end

