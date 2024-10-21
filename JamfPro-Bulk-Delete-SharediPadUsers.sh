#!/bin/bash

#Bulk-delete-users Version 1.1
#This is a AS IS SCRIPT.
#Hard Code the varibles.
##Varibles
username='' #Jamf Pro User Name 
password='' #Jamf Pro Password
url='' #Jamf Pro URL including https://
groupname_raw=''
groupname=$(printf "%s\n" "${groupname_raw}" | sed 's/ /%20/g' )
#Variable declarations
bearerToken=""
tokenExpirationEpoch="0"
#Functions
getBearerToken() {
	response=$(curl -s -u "$username":"$password" "$url"/api/v1/auth/token -X POST)
	bearerToken=$(echo "$response" | plutil -extract token raw -)
	tokenExpiration=$(echo "$response" | plutil -extract expires raw - | awk -F . '{print $1}')
	tokenExpirationEpoch=$(date -j -f "%Y-%m-%dT%T" "$tokenExpiration" +"%s")
}

checkTokenExpiration() {
	nowEpochUTC=$(date -j -f "%Y-%m-%dT%T" "$(date -u +"%Y-%m-%dT%T")" +"%s")
	if [[ tokenExpirationEpoch -gt nowEpochUTC ]]
	then
		echo "Token valid until the following epoch time: " "$tokenExpirationEpoch"
	else
		echo "No valid token available, getting new token"
		getBearerToken
	fi
}

invalidateToken() {
	responseCode=$(curl -w "%{http_code}" -H "Authorization: Bearer ${bearerToken}" $url/api/v1/auth/invalidate-token -X POST -s -o /dev/null)
	if [[ ${responseCode} == 204 ]]
	then
		echo "Token successfully invalidated"
		bearerToken=""
		tokenExpirationEpoch="0"
	elif [[ ${responseCode} == 401 ]]
	then
		echo "Token already invalid"
	else
		echo "An unknown error occurred invalidating the token"
	fi
}
prerun() {
	if [ -d "/Users/Shared/mass_delete_users" ]; then
		echo "$(date +'%Y-%m-%d %H:%M:%S') its there nothing to do moving on"
	else
		mkdir /Users/Shared/mass_delete_users
	fi
}
#Script Below
#build log path
prerun
#getting auth
getBearerToken
echo "$(date +'%Y-%m-%d %H:%M:%S') Authenticating to Jamf Pro" >> /Users/Shared/mass_delete_users/bulk_remove.log
#get list of devices via Classic API local copy less api actions
echo "$(date +'%Y-%m-%d %H:%M:%S') Getting device list" >> /Users/Shared/mass_delete_users/bulk_remove.log
curl -s -H "Authorization: Bearer ${bearerToken}" $url/JSSResource/mobiledevicegroups/name/${groupname}  | xmllint --format - > /Users/Shared/mass_delete_users/Mobile_device_list.xml
mobiledeviceidraw=$(cat /Users/Shared/mass_delete_users/Mobile_device_list.xml | xpath -e '//mobile_device_group/mobile_devices/mobile_device/id'  2>&1 | awk -F'<id>|</id>' '{print $2}')
invalidateToken 
for mdid in {$mobiledeviceidraw}; do
echo "$(date +'%Y-%m-%d %H:%M:%S') Getting Mobile Device Management ID for device id $mdid" >> /Users/Shared/mass_delete_users/bulk_remove.log
getBearerToken
echo "$(date +'%Y-%m-%d %H:%M:%S') Getting new token for new run" >> /Users/Shared/mass_delete_users/bulk_remove.log
mdr=$(curl -s -H "Authorization: Bearer ${bearerToken}" $url/api/v2/mobile-devices/$mdid -H "accept: application/json")
mdmid=$(echo $mdr | plutil -extract managementId raw -)
echo "$(date +'%Y-%m-%d %H:%M:%S') Targeting device with management id $mdmid" >> /Users/Shared/mass_delete_users/bulk_remove.log
postdelete=$(curl -s -H "Authorization: Bearer ${bearerToken}" $url/api/v2/mdm/commands -H "content-type: application/json" --data "{\"commandData\": {\"commandType\": \"DELETE_USER\",\"forceDeletion\": true,\"deleteAllUsers\": true},\"clientData\": [{\"managementId\": \"$mdmid\"}]}")
echo "$(date +'%Y-%m-%d %H:%M:%S') sent mass delete to $mdmid $postdelete)" >> /Users/Shared/mass_delete_users/bulk_remove.log
invalidateToken
echo "$(date +'%Y-%m-%d %H:%M:%S') token expired" >> /Users/Shared/mass_delete_users/bulk_remove.log
done
echo "$(date +'%Y-%m-%d %H:%M:%S') completed script, invalidating tokens" >> /Users/Shared/mass_delete_users/bulk_remove.log
