#!/bin/bash

#Var
service="Private Access" #Jamf Trust typically will be Private Access
service_to_turn_off=$(networksetup -listallnetworkservices | grep "${service}")

#Script
#General search incase its been installed more than once in the past.
if [[ "${service_to_turn_off}" =~ "Private Access" ]]; then
	echo "Service Found"
#switch it off/disable
/usr/sbin/networksetup -setnetworkserviceenabled ${service_to_turn_off} off
#kill Jamf Trust
/usr/bin/killall "Jamf Trust"
#enable the service incase its used. Line 12 disables it.
/usr/sbin/networksetup -setnetworkserviceenabled ${service_to_turn_off} on
else 
	echo "no service found"
exit 0
fi
