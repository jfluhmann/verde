# Create the mcadmin1 and vb-verde users/groups

groupadd --gid 5000 vb-verde
useradd -m --uid 5000 --gid 5000 vb-verde

PW=mcadmin1
ENCPW=$(echo $PW|mkpasswd -s)
groupadd --gid 6000 mcadmin1
useradd -m --uid 6000 --gid 6000 -p $ENCPW mcadmin1


# install Likewise-open
LIKEWISE_PKG=/root/LikewiseOpen-6.0.0.8388-linux-amd64-deb.sh
chmod +x $LIKEWISE_PKG
$LIKEWISE_PKG install

# install verde
VERDE_PKG=/root/verde_5.5-r550.10886_amd64.deb
dpkg -i $VERDE_PKG

## change TTY to show MC address
#echo "To access the VERDE Management Console, please visit - https://\n\o:8443/mc" >> /etc/issue
#echo "" >> /etc/issue

# change TTY to show MC address
cp /etc/issue /etc/issue-standard
mv /root/get-ip-address /usr/local/bin/get-ip-address
chmod +x /usr/local/bin/get-ip-address
mv /root/show-ip-at-login /etc/network/if-up.d/show-ip-at-login
chmod +x /etc/network/if-up.d/show-ip-at-login
