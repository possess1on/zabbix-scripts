#!/bin/bash

#this is tested and works together with fresh CentOS-7-x86_64-Minimal-1708.iso

#open 80 and 443 into firewall
systemctl enable firewalld
systemctl start firewalld

firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --add-port=162/udp --permanent
firewall-cmd --add-port=3000/tcp --permanent #for grafana reporting server https://www.digitalocean.com/community/tutorials/how-to-install-and-configure-grafana-to-plot-beautiful-graphs-from-zabbix-on-centos-7
firewall-cmd --reload

#update system
yum update -y

#install SELinux debuging utils
yum install policycoreutils-python -y

#install mariadb (mysql database engine for CentOS 7)
yum install mariadb-server -y

#start mariadb service
systemctl start mariadb
if [ $? -ne 0 ]; then
echo cannot start mariadb
else

#set new root password
/usr/bin/mysqladmin -u root password '5sRj4GXspvDKsBXW'
if [ $? -ne 0 ]; then
echo cannot set root password for mariadb
else

#show existing databases
mysql -h localhost -uroot -p5sRj4GXspvDKsBXW -P 3306 -s <<< 'show databases;' | grep zabbix
if [ $? -eq 0 ]; then
echo zabbix database already exist. cannot continue
else
#create zabbix database
mysql -h localhost -uroot -p5sRj4GXspvDKsBXW -P 3306 -s <<< 'create database zabbix character set utf8 collate utf8_bin;'

#create user zabbix and allow user to connect to the database with only from localhost
mysql -h localhost -uroot -p5sRj4GXspvDKsBXW -P 3306 -s <<< 'grant all privileges on zabbix.* to zabbix@localhost identified by "TaL2gPU5U9FcCU2u";'

#refresh permissions
mysql -h localhost -uroot -p5sRj4GXspvDKsBXW -P 3306 -s <<< 'flush privileges;'

#show existing databases
mysql -h localhost -uroot -p5sRj4GXspvDKsBXW -P 3306 -s <<< 'show databases;' | grep zabbix

#enable to start MySQL automatically at next boot
systemctl enable mariadb

#add zabbix 3.2 repository
rpm -ivh http://repo.zabbix.com/zabbix/3.4/rhel/7/x86_64/zabbix-release-3.4-2.el7.noarch.rpm
if [ $? -ne 0 ]; then
echo cannot install zabbix repository
else

#install zabbix server which are supposed to use MySQL as a database
yum install zabbix-server-mysql -y
if [ $? -ne 0 ]; then
echo zabbix-server-mysql package not found
else

#create zabbix database structure
ls -l /usr/share/doc/zabbix-server-mysql*/
zcat /usr/share/doc/zabbix-server-mysql*/create.sql.gz | mysql -uzabbix -pTaL2gPU5U9FcCU2u zabbix
if [ $? -ne 0 ]; then
echo cannot insert zabbix sql shema into database
else
#check if there is existing password line in config
grep "DBPassword=" /etc/zabbix/zabbix_server.conf
if [ $? -eq 0 ]; then
#change the password
sed -i "s/^.*DBPassword=.*$/DBPassword=TaL2gPU5U9FcCU2u/g" /etc/zabbix/zabbix_server.conf
fi

#show zabbix server conf file
grep -v "^$\|^#" /etc/zabbix/zabbix_server.conf
echo

systemctl status zabbix-server
if [ $? -eq 3 ]; then
echo zabbix-server service is installed but not stared yet. lets start it now..

setenforce 0

#start zabbix-server instance
systemctl start zabbix-server
#if not started succesfully then check for selinux errors
if [ $? -ne 0 ]; then
grep "denied.*zabbix.*server" /var/log/audit/audit.log | audit2allow -M zabbix_server
semodule -i zabbix_server.pp
fi

systemctl status zabbix-server
if [ $? -eq 0 ]; then
#if service was succesfully started then anable it on next boot
echo enabling zabbix-server to start automatically at next boot
systemctl enable zabbix-server
fi
fi

#empty log file
> /var/log/zabbix/zabbix_server.log

#restart zabbix server
systemctl restart zabbix-server
sleep 1

#output all
cat /var/log/zabbix/zabbix_server.log

#enable rhel-7-server-optional-rpms repository. This is neccessary to successfully install frontend
yum install yum-utils -y
yum-config-manager --enable rhel-7-server-optional-rpms

#install zabbix frontend
yum install httpd -y
yum install zabbix-web-mysql -y
#configure timezone
sed -i "s/^.*php_value date.timezone .*$/php_value date.timezone Europe\/Riga/" /etc/httpd/conf.d/zabbix.conf

getsebool -a | grep "httpd_can_network_connect \|zabbix_can_network"
setsebool -P httpd_can_network_connect on
setsebool -P zabbix_can_network on
getsebool -a | grep "httpd_can_network_connect \|zabbix_can_network"

curl https://support.zabbix.com/secure/attachment/53320/zabbix_server_add.te > zabbix_server_add.te
checkmodule -M -m -o zabbix_server_add.mod zabbix_server_add.te
semodule_package -m zabbix_server_add.mod -o zabbix_server_add.pp
semodule -i zabbix_server_add.pp

#configure zabbix to host on root
grep "^Alias" /etc/httpd/conf.d/zabbix.conf
if [ $? -ne 0 ]; then
echo Alias not found in "/etc/httpd/conf.d/zabbix.conf". Something is out of order.
else
#replace one line:
#Alias /zabbix /usr/share/zabbix-agent
#with two lines
#<VirtualHost *:80>
#DocumentRoot /usr/share/zabbix
sed -i "s/Alias \/zabbix \/usr\/share\/zabbix/<VirtualHost \*:80>\nDocumentRoot \/usr\/share\/zabbix/" /etc/httpd/conf.d/zabbix.conf

#add to the end of the file:
#</VirtualHost>
grep "</VirtualHost>" /etc/httpd/conf.d/zabbix.conf
if [ $? -eq 0 ]; then
echo "</VirtualHost>" already exists in the file /etc/httpd/conf.d/zabbix.conf
else
echo "</VirtualHost>" >> /etc/httpd/conf.d/zabbix.conf
fi

sed -i "s/^/#/g" /etc/httpd/conf.d/welcome.conf

systemctl restart httpd
systemctl enable httpd

yum install zabbix-agent -y
systemctl start zabbix-agent
systemctl enable zabbix-agent
fi #httpd document root not configured
fi #cannot insert zabbix sql shema into database
fi #zabbix-server-mysql package not found
fi #cannot install zabbix repository
fi #zabbix database already exist
fi #cannot set root password for mariadb
fi #mariadb is not running

