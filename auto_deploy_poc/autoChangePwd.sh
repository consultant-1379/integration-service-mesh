#!/usr/bin/expect

set timeout 3
set NODE_IP [lindex $argv 0]
set YANG_PORT [lindex $argv 1]
spawn ssh admin@$NODE_IP -p $YANG_PORT
expect "*Password*"
send "EricSson@12-3\r"
expect "*Current Password*"
send "EricSson@12-3\r"
expect "*New Password:"
send "EricSson@12-34\r"
expect "Reenter new Password:"
send "EricSson@12-34\r"
sleep 30
expect eof
