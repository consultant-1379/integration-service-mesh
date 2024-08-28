#!/usr/bin/expect

set timeout 5 
spawn kubectl exec eric-nrf-kvdb-ag-locator-0 -ti /bin/bash -n 5g-integration
expect "*bash*"
send "gfsh\r"
expect "*gfsh>*"
send "connect\r"
expect "*Successfully connected*"
send "destroy index --member=eric-nrf-kvdb-ag-server-0\r"
expect "*Destroyed all indexes*"
sleep 10
send "exit\r"
expect eof

