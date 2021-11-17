#!/bin/bash

LOGFILE="/var/log/ceph_health.log"

if [ ! -e $LOGFILE ]; then
	touch $LOGFILE
	chmod 644 $LOGFILE
	chown zabbix:zabbix $LOGFILE
fi

while true
do
	now=$(date +'%Y/%m/%d-%H:%M:%S')
	health=$(ceph health detail)
	summary=`echo "${health}" | head -1`
	detail=${health#*$'\n'}
	detail=`echo "${detail}" | sed -n '/^\[/p'`
	echo "$now" "$summary"
	if [ "$summary" = "HEALTH_OK" ]; then
		echo "$summary" >> $LOGFILE
	else
		echo "$detail" >> $LOGFILE
	fi
	sleep 1
done
