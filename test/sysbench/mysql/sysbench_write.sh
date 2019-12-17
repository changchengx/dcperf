#!/bin/bash

host=192.168.100.187
port=3306
user=root
passwd=intel123

db_name=ceph_rwl
thread_count=1
db_table_num=1
db_size_per_table=5000000
duration=1800
report_interval=600
#db_size_per_table=5000
#duration=20
#report_interval=6

#print a log and then exit
function EXIT() {
    [ $# -ne 0 ] && [ "$1" != "" ] && printf "$1\n"
    exit 1
}

#create database
echo "**************Create Database*****************"
mysql -u$user -p$passwd -h $host -P $port -e "create database if not exists $db_name;"
[ $? -eq 0 ] || EXIT "Create database FAILED!"

echo "**************Prepare data********************"
# prepare data
sysbench --rand-type=uniform --db-driver=mysql --mysql-db=$db_name --mysql-host=$host --mysql-port=$port --mysql-user=$user --mysql-password=$passwd --report-interval=$report_interval --events=0 /usr/share/sysbench/oltp_write_only.lua --tables=$db_table_num --table-size=$db_size_per_table prepare
[ $? -eq 0 ] || EXIT "Prepare data FAILED!"

echo "*************Run test*************************"
# execute test
sysbench --rand-type=uniform --db-driver=mysql --mysql-db=$db_name --mysql-host=$host --mysql-port=$port --mysql-user=$user --mysql-password=$passwd --report-interval=$report_interval --events=0 --threads=$thread_count --time=$duration --percentile=99 /usr/share/sysbench/oltp_write_only.lua --tables=$db_table_num --table-size=$db_size_per_table --sum_ranges=0 --order_ranges=0 --distinct_ranges=0 --index_updates=100 --non_index_updates=0 --point_selects=0 run
[ $? -eq 0 ] || EXIT "Start benchmark FAILED!"

echo "************Clean env**************************"
# cleanup environment
sysbench --db-driver=mysql --mysql-db=$db_name --mysql-host=$host --mysql-port=$port --mysql-user=$user --mysql-password=$passwd --report-interval=$report_interval --events=0 --threads=$thread_count /usr/share/sysbench/oltp_write_only.lua --tables=$db_table_num --table-size=$db_size_per_table cleanup
[ $? -eq 0 ] || EXIT "Cleanup FAILED!"
