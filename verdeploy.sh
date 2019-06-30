#!/bin/bash
#
#
# This script will create a customized CentOS x86_64 minimal installation
# CD image that includes VERDE in the installations.
# The script should be used from an existing CentOS x86_64 installation.
# If the EPEL repository is not present on the system this script will install/create it.
#
#
# If you have a local mirror that you prefer to use, modify and uncomment the
# line(s) below.
#CENTOSMIRROR="http://10.1.1.240/centos/"
#EPELMIRROR="http://10.1.1.240/epel/"
#ELREPOMIRROR="http://10.1.1.240/elrepo/"
#PGRPM91MIRROR="http://10.1.1.240/pgrpm-91/"

# Set the VERDEVERSION variable to the version of VERDE you would like
# to create an installation disk for.
# Valid values are "r550" and "r650"
VERDEVERSION="r650"

# Modification below this point shouldn't be necessary

# Function to install packages on build system if they aren't already present
function install_package {
  rpm -q $1 > /dev/null
  if [ $? -eq 1 ] ; then
    echo "$(date) - Installing $1 package" | tee -a $SILVEREYELOGFILE
    yum -y install $1
  else
    echo "$(date) - $1 package already installed" | tee -a $SILVEREYELOGFILE
  fi
}

# Exit if the script is not run with root privileges
if [ "$EUID" != "0" ] ; then
  echo "This script must be run with root privileges."
  exit 1
fi

# Create the build directory structure and cd into it
ELVERSION=`cat /etc/redhat-release | sed -e 's/.* \([56]\).*/\1/'`
DATESTAMP=`date +%s.%N | rev | cut -b 4- | rev`
PACKAGESDIR="CentOS"
if [ $ELVERSION -ne 6 ] ; then
  echo "$(date)- Error: This script must be run on CentOS version 6" | tee -a $SILVEREYELOGFILE
  exit 1
fi

mkdir -p verdeploy_build.${DATESTAMP}/isolinux/{${PACKAGESDIR},images,ks}
mkdir -p verdeploy_build.${DATESTAMP}/isolinux/images/pxeboot

cd verdeploy_build.$DATESTAMP
BUILDDIR=`pwd`
SILVEREYELOGFILE="${BUILDDIR}/verdeploy.$DATESTAMP.log"
echo "$(date) - Created $BUILDDIR directory structure" | tee -a $SILVEREYELOGFILE

# Install curl and wget if they aren't already installed
install_package curl
install_package wget

#Set the mirror to use for retrieving files
if [ -z "$CENTOSMIRROR" ] ; then
  FETCHMIRROR=`curl -s http://mirrorlist.centos.org/?release=${ELVERSION}\&arch=x86_64\&repo=os | grep -vE '(^#|^ftp)' | head -n 1`
else
  FETCHMIRROR="${CENTOSMIRROR}${ELVERSION}/os/x86_64/"
fi
echo "$(date) - Using $FETCHMIRROR for downloads" | tee -a $SILVEREYELOGFILE

# Retrieve the comps.xml file
echo "$(date) - Retrieving files" | tee -a $SILVEREYELOGFILE
COMPSFILE=`curl -s ${FETCHMIRROR}repodata/ | grep 'comps.xml\"' | sed -e 's/.*href=\"\(.*comps.xml\)\".*/\1/'`
wget ${FETCHMIRROR}/repodata/${COMPSFILE}

# Retrieve the files for the root filesystem of the CD
wget ${FETCHMIRROR}/.discinfo -O isolinux/.discinfo

# Retrieve the files for the isolinux directory
COMMONISOLINUXFILES="
isolinux/boot.msg
isolinux/initrd.img
isolinux/isolinux.bin
isolinux/isolinux.cfg
isolinux/memtest
isolinux/vmlinuz
"
for FILE in $COMMONISOLINUXFILES ; do
wget ${FETCHMIRROR}/${FILE} -O ${FILE}
done

ISOLINUXFILES="
isolinux/grub.conf
isolinux/splash.jpg
isolinux/vesamenu.c32
"

for FILE in $ISOLINUXFILES ; do
wget ${FETCHMIRROR}/${FILE} -O ${FILE}
done

IMAGESFILES="
efiboot.img
efidisk.img
install.img
pxeboot/initrd.img
pxeboot/vmlinuz
"


for FILE in $IMAGESFILES ; do
wget ${FETCHMIRROR}/images/${FILE} -O ./isolinux/images/${FILE}
done

## Kickstart
cat > ${BUILDDIR}/isolinux/ks/verde.cfg <<"EOFVERDEKICKSTART"

# Example for installing VERDE and required packages
# might want to either include @Base or at least various troubleshooting tools - bind-utils, bind-libs

# Install OS instead of upgrade
install
cdrom
network --activate
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
timezone  --utc America/Chicago
# System bootloader configuration
bootloader --location=mbr --driveorder=sda --append="crashkernel=auto rhgb quiet"
#Clear the Master Boot Record
zerombr
# Partition clearing information
clearpart --all --initlabel 
autopart


# Network information
network --device eth0 --onboot yes --bootproto dhcp --hostname=verde-demo


%packages
@Base
@Core
system-config-network-tui
unzip
libaio
libXrandr
libXfixes
java-1.6.0-openjdk
ghostscript
genisoimage
%end

%pre
# can I put the %post stuff in here, instead?  Would that allow the verde users to be created before trying to install %packages?
%end

%post --log=/mnt/sysimage/root/verde-nochroot.log --nochroot
cp /mnt/source/CentOS/VERDE-6.6-r660.16697.x86_64.rpm /mnt/sysimage/root/
%end

%post --log=/root/verde-post.log
groupadd --gid 5000 vb-verde
useradd -m --uid 5000 --gid 5000 vb-verde
EOFVERDEKICKSTART

if [ "$VERDEVERSION" = "r550" ]; then
cat >> ${BUILDDIR}/isolinux/ks/verde.cfg <<"EOFVERDEKICKSTART"
PW=mcadmin1
ENCPW=$(echo $PW| openssl passwd -1 -stdin)
groupadd --gid 6000 mcadmin1
useradd -m --uid 6000 --gid 6000 -p $ENCPW mcadmin1
EOFVERDEKICKSTART
fi

cat >> ${BUILDDIR}/isolinux/ks/verde.cfg <<"EOFVERDEKICKSTART"
rpm -ivh /root/VERDE-6.6-r660.16697.x86_64.rpm
service VERDE stop

# change TTY to show MC address
cp /etc/issue /etc/issue-standard
# Create get-ip-address script
cat >> /usr/local/bin/get-ip-address <<"EOFGETIPADDRESS"
ip addr show | grep -v vbinat0 | grep -v "127.0.0.1" | grep "inet " | awk '{ print $2 }' | awk -F/ '{ print $1 }'
EOFGETIPADDRESS
chmod +x /usr/local/bin/get-ip-address

sed -i 's/exit \$rc//' /etc/init.d/network
echo "cp /etc/issue-standard /etc/issue" >> /etc/init.d/network
echo "echo \"To access the VERDE Management Console, please visit - https://\"\$(/usr/local/bin/get-ip-address)\":8443/mc\" >> /etc/issue" >> /etc/init.d/network
echo "echo \"\" >> /etc/issue" >> /etc/init.d/network
echo "" >> /etc/init.d/network
echo "exit \$rc" >> /etc/init.d/network

%end

EOFVERDEKICKSTART

cat > ${BUILDDIR}/isolinux/ks/minimal.cfg <<"EOFMINIMALKICKSTART"
# Kickstart file

install
cdrom
network --device=eth0 --bootproto=query
firewall --disabled
authconfig --enableshadow --enablemd5                                                                                                                                                         
selinux --disabled

%packages
@Core

EOFMINIMALKICKSTART

cat > ${BUILDDIR}/isolinux/ks/core.cfg <<"EOFCOREKICKSTART"
# Kickstart file

install
cdrom
network --device=eth0 --bootproto=query
firewall --disabled
authconfig --enableshadow --enablemd5
selinux --disabled

%packages --nobase --excludedocs
@Core

EOFCOREKICKSTART



# Install/configure yum repositories
# Configure CentOS repository
if [ -n "$CENTOSMIRROR" ] ; then
  sed -i -e 's%^mirrorlist=http.*%#\0%g' /etc/yum.repos.d/CentOS-*.repo
  sed -i -e "s%#baseurl=http://mirror.centos.org/centos/%baseurl=${CENTOSMIRROR}%g" /etc/yum.repos.d/CentOS-*.repo
fi

# Install yum-utils if it isn't already installed
install_package yum-utils

# Install/configure EPEL repository
rpm -q epel-release > /dev/null
if [ $? -eq 1 ] ; then
  echo "$(date) - Installing EPEL package" | tee -a $SILVEREYELOGFILE
  if [ -z "$EPELMIRROR" ] ; then
    EPELFETCHMIRROR=`curl -s http://mirrors.fedoraproject.org/mirrorlist?repo=epel-${ELVERSION}\&arch=x86_64 | grep -vE '(^#|^ftp)' | head -n 1`
  else
    EPELFETCHMIRROR="${EPELMIRROR}${ELVERSION}/x86_64/"
  fi
  case "$ELVERSION" in
  "5")
    wget ${EPELFETCHMIRROR}epel-release-5-4.noarch.rpm
    ;;
  "6")
    wget ${EPELFETCHMIRROR}epel-release-6-7.noarch.rpm
    ;;
  esac
  rpm -Uvh epel-release-*.noarch.rpm
  rm -f epel-release-*.noarch.rpm
else
  echo "$(date) - EPEL package already installed" | tee -a $SILVEREYELOGFILE
fi
if [ -n "$EPELMIRROR" ] ; then
  sed -i -e 's%^mirrorlist=http.*%#\0%g' /etc/yum.repos.d/epel.repo
  sed -i -e "s%#baseurl=http://download.fedoraproject.org/pub/epel/%baseurl=${EPELMIRROR}%g" /etc/yum.repos.d/epel.repo
fi




# Retrieve the RPMs for CentOS, VERDE, and dependencies
# Set list of RPMs to download
RPMS="MAKEDEV.x86_64 acl.x86_64 acpid.x86_64 aic94xx-firmware aic94xx-firmware.noarch \
     alsa-lib.x86_64 atk.x86_64 atmel-firmware atmel-firmware.noarch attr.x86_64 \
     audit-libs-python.x86_64 audit-libs.x86_64 audit.x86_64 authconfig.x86_64 \
     autofs.x86_64 avahi-libs.x86_64 b43-openfwwf.noarch basesystem.noarch bash.x86_64 \
     bfa-firmware.noarch binutils.x86_64 bridge-utils.x86_64 bzip2-libs.x86_64 bzip2.x86_64 \
     ca-certificates.noarch cairo.x86_64 centos-release.x86_64 checkpolicy.x86_64 \
     chkconfig.x86_64 chrony.x86_64 cifs-utils.x86_64 cjkuni-fonts-common \
     cjkuni-ukai-fonts cjkuni-uming-fonts compat-libevent14.x86_64 compat-openldap.x86_64 \
     coreutils-libs.x86_64 coreutils.x86_64 cpio.x86_64 cpuspeed.x86_64 \
     cracklib-dicts.x86_64 cracklib.x86_64 crda.x86_64 cronie-anacron.x86_64 \
     cronie.x86_64 crontabs.noarch cups-libs.x86_64 curl.x86_64 cyrus-sasl-lib.x86_64 \
     cyrus-sasl-md5.x86_64 cyrus-sasl.x86_64 dash.x86_64 db4-utils.x86_64 db4.x86_64 \
     dbus-glib.x86_64 dbus-libs.x86_64 dbus-python.x86_64 dbus.x86_64 deltarpm.x86_64 \
     device-mapper-event-libs.x86_64 device-mapper-event.x86_64 device-mapper-libs.x86_64 \
     device-mapper.x86_64 dhclient.x86_64 dhcp-common.x86_64 dhcp.x86_64 diffutils.x86_64 \
     dracut-kernel.noarch dracut.noarch e2fsprogs-libs.x86_64 e2fsprogs.x86_64 \
     efibootmgr.x86_64 eject.x86_64 elfutils-libelf.x86_64 epel-release.noarch \
     ethtool.x86_64 expat.x86_64 file.x86_64 file-libs.x86_64 filesystem.x86_64 findutils.x86_64 \
     fipscheck-lib.x86_64 fipscheck.x86_64 flac.x86_64 fontconfig.x86_64 \
     fontpackages-filesystem.noarch freetype.x86_64 ftp.x86_64 gamin.x86_64 gawk.x86_64 \
     gdbm.x86_64 genisoimage.x86_64 ghostscript.x86_64 ghostscript-fonts.noarch giflib.x86_64 \
     glib2.x86_64 glibc-common.x86_64 glibc.i686 glibc.x86_64 gmp.x86_64 gnupg2.x86_64 \
     gnutls.x86_64 gpgme.x86_64 grep.x86_64 groff.x86_64 grub.x86_64 grubby.x86_64 gtk2.x86_64 \
     gzip.x86_64 hdparm.x86_64 hesiod.x86_64 hicolor-icon-theme.noarch hwdata.noarch info.x86_64 \
     initscripts.x86_64 iproute.x86_64 iptables-ipv6.x86_64 iptables.x86_64 iputils.x86_64 \
     ipw2100-firmware.noarch ipw2200-firmware.noarch irqbalance.x86_64 iscsi-initiator-utils.x86_64 \
     ivtv-firmware.noarch iw.x86_64 iwl100-firmware.noarch iwl1000-firmware.noarch \
     iwl3945-firmware.noarch iwl4965-firmware.noarch iwl5000-firmware.noarch \
     iwl5150-firmware.noarch iwl6000-firmware.noarch iwl6000g2a-firmware.noarch \
     iwl6000g2b-firmware.noarch iwl6050-firmware.noarch jasper-libs.x86_64 \
     java-1.6.0-openjdk jline.noarch jpackage-utils.noarch jre kbd-misc.noarch \
     kbd.x86_64 kernel-firmware.noarch kernel.x86_64 keyutils-libs.x86_64 \
     keyutils.x86_64 krb5-libs.x86_64 less.x86_64 libICE.x86_64 libSM.x86_64 \
     libX11-common.noarch libX11.x86_64 libXau.x86_64 libXcomposite.x86_64 \
     libXcursor.x86_64 libXdamage.x86_64 libXext.x86_64 libXfixes.x86_64 libXfont.x86_64 \
     libXft.x86_64 libXi.x86_64 libXinerama.x86_64 libXrandr.x86_64 libXrender.x86_64 \
     libXt.x86_64 libXtst.x86_64 libacl.x86_64 libaio.x86_64 libart_lgpl.x86_64 libasyncns.x86_64 \
     libattr.x86_64 libblkid.x86_64 libcap-ng.x86_64 libcap.x86_64 libcgroup.x86_64 \
     libcom_err.x86_64 libcurl.x86_64 libdrm.x86_64 libedit.x86_64 \
     libertas-usb8388-firmware.noarch libevent.x86_64 libffi.x86_64 libfontenc.x86_64 libgcc.i686 \
     libgcc.x86_64 libgcj.x86_64 libgcrypt.x86_64 libglade2.x86_64 libgomp.x86_64 \
     libgpg-error.x86_64 libgssglue.x86_64 libibverbs.x86_64 libidn.x86_64 libjpeg.x86_64 \
     libnih.x86_64 libnl.x86_64 libogg.x86_64 libpcap.x86_64 libpciaccess.x86_64 \
     libpng.x86_64 librdmacm.x86_64 libselinux-python.x86_64 libselinux-utils.x86_64 \
     libselinux.x86_64 libsemanage.x86_64 libsepol.x86_64 libsndfile.x86_64 libss.x86_64 \
     libssh2.x86_64 libstdc++.x86_64 libsysfs.x86_64 libtalloc.x86_64 libtasn1.x86_64 \
     libthai.x86_64 libtiff.x86_64 libtinfo libtirpc.x86_64 libudev.x86_64 libusb.x86_64 \
     libuser.x86_64 libutempter.x86_64 libuuid.x86_64 libvorbis.x86_64 libxcb.x86_64 \
     libxml2-python.x86_64 libxml2.x86_64 libxslt.x86_64 libzip.x86_64 logrotate.x86_64 \
     lsof.x86_64 lua.x86_64 lvm2-libs.x86_64 lvm2.x86_64 m2crypto.x86_64 m4.x86_64 \
     mailx.x86_64 mdadm.x86_64 mingetty.x86_64 module-init-tools.x86_64 mysql-libs.x86_64 \
     ncurses-base.x86_64 ncurses-libs.x86_64 ncurses.x86_64 net-tools.x86_64 \
     newt-python.x86_64 newt.x86_64 nfs-utils-lib.x86_64 nfs-utils.x86_64 nspr.x86_64 nss.x86_64 \
     nss-softokn-freebl.i686 nss-softokn-freebl.x86_64 nss-softokn.x86_64 nss-sysinit.x86_64 \
     nss-tools.x86_64 nss-util.x86_64 nss.x86_64 nxclient openldap.x86_64 openssh-clients.x86_64 \
     openssh-server.x86_64 openssh.x86_64 openssl.x86_64 pam.x86_64 pam_ldap.x86_64 \
     pango.x86_64 passwd.x86_64 pciutils-libs.x86_64 pciutils.x86_64 pcre.x86_64 \
     pinentry.x86_64 pixman.x86_64 pkgconfig.x86_64 plymouth-core-libs.x86_64 plymouth-scripts.x86_64 \
     plymouth.x86_64 policycoreutils.x86_64 popt-devel.x86_64 popt-static.x86_64 popt.x86_64 \
     portreserve.x86_64 postfix.x86_64 prelink.x86_64 procmail.x86_64 procps.x86_64 psmisc.x86_64 pth.x86_64 \
     pulseaudio-libs.x86_64 pygpgme.x86_64 python-ethtool.x86_64 python-iniparse.noarch \
     python-iwlib.x86_64 python-libs.x86_64 python-pycurl.x86_64 python-urlgrabber.noarch \
     python.x86_64 ql2100-firmware.noarch ql2200-firmware.noarch ql23xx-firmware.noarch \
     ql2400-firmware.noarch ql2500-firmware.noarch readahead.x86_64 readline.x86_64 \
     redhat-logos.noarch rhino.noarch rinetd rootfiles.noarch rpcbind.x86_64 rpm-libs.x86_64 \
     rpm-python.x86_64 rpm.x86_64 rsyslog.x86_64 rt61pci-firmware.noarch \
     rt73usb-firmware.noarch sed.x86_64 selinux-policy-targeted.noarch \
     selinux-policy.noarch sendmail.x86_64 setup.noarch shadow-utils.x86_64 \
     slang.x86_64 smartmontools.x86_64 sos sqlite.x86_64 strace.x86_64 sudo.x86_64 \
     sysstat.x86_64 system-config-firewall-base.noarch system-config-network-tui.noarch \
     sysvinit-tools.x86_64 tar.x86_64 tcp_wrappers-libs.x86_64 tftp-server.x86_64 \
     tzdata-java.noarch tzdata.noarch udev.x86_64 un-core-batang-fonts \
     un-core-dinaru-fonts un-core-dotum-fonts un-core-fonts-common.noarch \
     un-core-graphic-fonts un-core-gungseo-fonts un-core-pilgi-fonts unzip.x86_64 \
     upstart.x86_64 urw-fonts.noarch usermode.x86_64 ustr.x86_64 util-linux-ng.x86_64 vconfig.x86_64 \
     vim-minimal.x86_64 vlgothic-fonts vlgothic-fonts-common.noarch vlgothic-p-fonts \
     wget.x86_64 which.x86_64 wireless-tools.x86_64 wqy-zenhei-fonts xinetd.x86_64 \
     xml-common.noarch xorg-x11-drv-ati-firmware.noarch xorg-x11-font-utils.x86_64 \
     xz-libs.x86_64 xz.x86_64 yum-metadata-parser.x86_64 yum-plugin-fastestmirror.noarch \
     yum-presto yum-updateonboot yum-utils.noarch yum.noarch zd1211-firmware.noarch \
     zip.x86_64 zlib.x86_64"
## rinetd fbterm fbterm-udevrules nxclient compat-libevent14 libtinfo
        ## Took out the following
        ## firstboot
        
        #### Packages needed to run VERDE bits
        ###VERDE
        ###verde-spice
        ####nxclient
        ###kmod-openvswitch


# Download the base rpms
cd ${BUILDDIR}/isolinux/${PACKAGESDIR}
echo "$(date) - Retrieving packages" | tee -a $SILVEREYELOGFILE
yumdownloader ${RPMS}

##### Download rpms that vary according to VERDE version
case "$VERDEVERSION" in
    "r550")
        wget http://vbridges.com/pub/pkg/linux/5.5SP5/VERDE-5.5-r550.16048.x86_64.rpm
        ;;
    "r650")
        wget http://vbridges.com/pub/pkg/linux/6.6/VERDE-6.6-r660.16697.x86_64.rpm
        ;;
esac


# Test the installation of the RPMs to verify that we have all dependencies
echo "$(date) - Verifying package dependencies are met" | tee -a $SILVEREYELOGFILE
mkdir -p ${BUILDDIR}/tmprpmdb
rpm --initdb --dbpath ${BUILDDIR}/tmprpmdb
rpm --test --dbpath ${BUILDDIR}/tmprpmdb -Uvh ${BUILDDIR}/isolinux/${PACKAGESDIR}/*.rpm
if [ $? -ne 0 ] ; then
  echo "$(date) - Package dependencies not met! Exiting." | tee -a $SILVEREYELOGFILE
  exit 1
else
  echo "$(date) - Package dependencies are OK" | tee -a $SILVEREYELOGFILE
fi
rm -rf ${BUILDDIR}/tmprpmdb

# Create a repository
install_package createrepo
echo "$(date) - Creating repodata" | tee -a $SILVEREYELOGFILE
cd ${BUILDDIR}/isolinux
declare -x discinfo="$DATESTAMP"
createrepo -u "media://$discinfo" -g ${BUILDDIR}/${COMPSFILE} .
echo "$(date) - Repodata created" | tee -a $SILVEREYELOGFILE

# Extract the VERDE logo and use it for the boot logo
install_package ImageMagick
install_package syslinux
install_package java-1.6.0-openjdk-devel
echo "$(date) - Creating boot logo" | tee -a $SILVEREYELOGFILE
### TODO - VERDE Logo junk

# edit the boot menu
cd ${BUILDDIR}/isolinux
sed -i -e '/  menu default/d' isolinux.cfg
sed -i -e 's/^\(  menu label Boot from .*drive\)$/\1\n  menu default/g' isolinux.cfg
sed -i -e 's/label linux/label verde/' isolinux.cfg
sed -i -e 's/menu label ^Install or upgrade an existing system/menu label Install CentOS 6 with VERDE ^Node/' isolinux.cfg
sed -i -e 's%^  append initrd=initrd.img$%  append initrd=initrd.img ks=cdrom:/ks/verde.cfg%' isolinux.cfg
sed -i -e 's%^\(label rescue\)$%label minimal\n  menu label Install a ^minimal CentOS 6 without VERDE\n  kernel vmlinuz\n  append initrd=initrd.img ks=cdrom:/ks/minimal.cfg\n\1%' isolinux.cfg

# Create the .iso image
install_package anaconda
cd ${BUILDDIR}
mkisofs -o verdeploy.${DATESTAMP}.iso -b isolinux.bin -c boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -R -J -v -T -joliet-long isolinux/
/usr/bin/implantisomd5 verdeploy.${DATESTAMP}.iso
mv verdeploy.${DATESTAMP}.iso ../

