#!/bin/bash

#Create By: pip-b0y
#Name: VPP Manager
#Version: 2.0
#UseCase - This script is intended to turn off VPP Globally for Device deployments. This script does not impact end devices.
#Its intended usage is for VPP Legacy token migrations to ASM or ABM. Given Some Orgs have Hundereds of applications and or
#dont have the time to turn them all off, Yes it can be done via the database just as easy. But, going via the API ensures
#we are not doing anything wrong
#Updates, added in modern authentication, more granular settings.

username='' #Jamf Pro User Name
password='' #Jamf Pro Password
url='' #Jamf Pro URL including https://
mode='' #off = switches off ManagedDistribution for the app. on = switches it back on.
type='' #mobiledevice = mobile device apps. computer = macOS Apps
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
	if [ -d "/Users/Shared/VPP_Tool" ]; then
		echo "$(date +'%Y-%m-%d %H:%M:%S') its there nothing to do moving on"
	else
		mkdir /Users/Shared/VPP_Tool
	fi
}

MobileDeviceOff() {
	echo "$(date +'%Y-%m-%d %H:%M:%S') Authenticating to $url" >> /Users/Shared/VPP_Tool/VPP_Migrator_tool.log
	getBearerToken
	#Mobile Device Applications
	echo "$(date +'%Y-%m-%d %H:%M:%S') Starting Kessel run now. Getting a list of Mobile Device Apps and backing them up" >> /Users/Shared/VPP_Tool/VPP_Migrator_tool.log
	curl -s -H "Authorization: Bearer ${bearerToken}" $url/JSSResource/mobiledeviceapplications | xmllint --format - > /Users/Shared/VPP_Tool/mobile_device_app_list_raw.xml
	mobiledeviceidraw=$(cat /Users/Shared/VPP_Tool/mobile_device_app_list_raw.xml | xpath -e '//mobile_device_application/id' 2>&1 | awk -F'<id>|</id>' '{print $2}')
	for mdid in ${mobiledeviceidraw}; do
		if [ -f "/Users/Shared/VPP_Tool/$mdid-MobileDeviceApp.xml" ]; then
			echo "$(date +'%Y-%m-%d %H:%M:%S') Mobile Device App ID ${mdid} has been backed up and is likely off. Skipping." >> /Users/Shared/VPP_Tool/VPP_Migrator_tool.log
		else
		echo ${mdid} >> /Users/Shared/VPP_Tool/MobileDeviceAppID.log
		curl -s -H "Authorization: Bearer ${bearerToken}" $url/JSSResource/mobiledeviceapplications/id/$mdid -X GET | xmllint --format - > /Users/Shared/VPP_Tool/$mdid-MobileDeviceApp.xml
		mdappname=$(cat /Users/Shared/VPP_Tool/$mdid-MobileDeviceApp.xml | xpath -e '//mobile_device_application/general/name' 2>&1 | awk -F'<name>|</name>' '{print $2}')
		echo "$(date +'%Y-%m-%d %H:%M:%S') Back up has been created for $mdappname app record. Has been created. Switching off now" >> /Users/Shared/VPP_Tool/VPP_Migrator_tool.log
	curl -s -H "Authorization: Bearer ${bearerToken}" $url/JSSResource/mobiledeviceapplications/id/$mdid -X PUT -H "Content-Type: application/xml" -d "<mobile_device_application><vpp><assign_vpp_device_based_licenses>false</assign_vpp_device_based_licenses><vpp_admin_account_id>-1</vpp_admin_account_id></vpp></mobile_device_application>"
		fi
	done
}

MobileDeviceOn() {
	echo "$(date +'%Y-%m-%d %H:%M:%S') Authenticating to $url" >> /Users/Shared/VPP_Tool/VPP_Migrator_tool.log
	getBearerToken
	#Mobile Device Applications
	echo "$(date +'%Y-%m-%d %H:%M:%S') All Wings Report In, Starting Trench run" >> /Users/Shared/VPP_Tool/VPP_Migrator_tool.log
	curl -s -H "Authorization: Bearer ${bearerToken}" $url/JSSResource/mobiledeviceapplications | xmllint --format - > /Users/Shared/VPP_Tool/mobile_device_app_list_raw.xml
	while IFS= read mdid2; do
	mvpptokenid=$(cat /Users/Shared/VPP_Tool/$mdid2-MobileDeviceApp.xml | xpath -e '//mobile_device_application/vpp/vpp_admin_account_id' 2>&1 | awk -F'<vpp_admin_account_id>|</vpp_admin_account_id>' '{print $2}')
	mdaname2=$(cat /Users/Shared/VPP_Tool/$mdid2-MobileDeviceApp.xml | xpath -e '//mobile_device_application/general/name' 2>&1 | awk -F'<name>|</name>' '{print $2}')
		if [ "${mvpptokenid}" -eq "-1" ]; then
			echo "$(date +'%Y-%m-%d %H:%M:%S') Mobile Device app $mdaname2 has a VPP token of -1, means it was off from the start" >> /Users/Shared/VPP_Tool/VPP_Migrator_tool.log
		else
			echo "$(date +'%Y-%m-%d %H:%M:%S') Turning back on Mobile Device App ${mdaname2}" >> /Users/Shared/VPP_Tool/VPP_Migrator_tool.log
		curl -s -H "Authorization: Bearer ${bearerToken}" $url/JSSResource/mobiledeviceapplications/id/$mdid2 -X PUT -H "Content-Type: application/xml" -d "<mobile_device_application><vpp><assign_vpp_device_based_licenses>true</assign_vpp_device_based_licenses><vpp_admin_account_id>${mvpptokenid}</vpp_admin_account_id></vpp></mobile_device_application>"
		fi
	done < /Users/Shared/VPP_Tool/MobileDeviceAppID.log
}

MacAppsOff() {
	echo "$(date +'%Y-%m-%d %H:%M:%S') Authenticating to $url" >> /Users/Shared/VPP_Tool/VPP_Migrator_tool.log
	getBearerToken
	#Computer Applications
	echo "$(date +'%Y-%m-%d %H:%M:%S') Starting Kessel run now. Getting a list of MacOS Apps and backing them up" >> /Users/Shared/VPP_Tool/VPP_Migrator_tool.log
	curl -s -H "Authorization: Bearer ${bearerToken}" $url/JSSResource/macapplications -X GET | xmllint --format - > /Users/Shared/VPP_Tool/computer_app_list_raw.xml
	computerappidraw=$(cat /Users/Shared/VPP_Tool/computer_app_list_raw.xml | xpath -e '//mac_application/id' 2>&1 | awk -F'<id>|</id>' '{print $2}')
for caid in ${computerappidraw}; do
	if [ -f "/Users/Shared/VPP_Tool/$caid-ComputerApp.xml" ]; then
		echo "Mac App ID ${caid} already has been back up and is likely off. Skipping." >> /Users/Shared/VPP_Tool/VPP_Migrator_tool.log
	else
		echo "${caid}" >> /Users/Shared/VPP_Tool/ComputerAppID.log
	curl -s -H "Authorization: Bearer ${bearerToken}" $url/JSSResource/macapplications/id/${caid} -X GET | xmllint --format - > /Users/Shared/VPP_Tool/$caid-ComputerApp.xml
	macappname=$(cat /Users/Shared/VPP_Tool/$caid-ComputerApp.xml | xpath -e '//mac_application/general/name' 2>&1 | awk -F'<name>|</name>' '{print $2}')
	echo "$(date +'%Y-%m-%d %H:%M:%S') Backup has been created for $macappname app record. Has been created. Switching off now" >> /Users/Shared/VPP_Tool/VPP_Migrator_tool.log
curl -s -H "Authorization: Bearer ${bearerToken}" $url/JSSResource/macapplications/id/$caid -X PUT -H "Content-Type: application/xml" -d "<mac_application><vpp><assign_vpp_device_based_licenses>false</assign_vpp_device_based_licenses><vpp_admin_account_id>-1</vpp_admin_account_id></vpp></mac_application>"
	fi
done
}
MacAppsOn() {
	echo "$(date +'%Y-%m-%d %H:%M:%S') Authenticating to $url" >> /Users/Shared/VPP_Tool/VPP_Migrator_tool.log
	echo "$(date +'%Y-%m-%d %H:%M:%S') Turning back on VPP for MacOS Apps. This aint like dusting crops" >> /Users/Shared/VPP_Tool/VPP_Migrator_tool.log
	getBearerToken
	while IFS= read caid2; do
	cvpptokenid=$(cat /Users/Shared/VPP_Tool/${caid2}-ComputerApp.xml | xpath -e '//mac_application/vpp/vpp_admin_account_id' 2>&1 | awk -F'<vpp_admin_account_id>|</vpp_admin_account_id>' '{print $2}')
	macappname2=$(cat /Users/Shared/VPP_Tool/$caid2-ComputerApp.xml | xpath -e '//mac_application/general/name' 2>&1 | awk -F'<name>|</name>' '{print $2}')
	if [ "${cvpptokenid}" -eq "-1" ]; then
		echo "$(date +'%Y-%m-%d %H:%M:%S') computer app $macappname2 has a VPP token of -1, means it was off from the start" >> /Users/Shared/VPP_Tool/VPP_Migrator_tool.log
	else
		echo "$(date +'%Y-%m-%d %H:%M:%S') Turning back on VPP app $macappname2 to the original VPP ID of ${cvpptokenid} " >> /Users/Shared/VPP_Tool/VPP_Migrator_tool.log
		curl -s -H "Authorization: Bearer ${bearerToken}" $url/JSSResource/macapplications/id/$caid2 -X PUT -H "Content-Type: application/xml" -d "<mac_application><vpp><assign_vpp_device_based_licenses>true</assign_vpp_device_based_licenses><vpp_admin_account_id>${cvpptokenid}</vpp_admin_account_id></vpp></mac_application>"
	fi
		done < /Users/Shared/VPP_Tool/ComputerAppID.log

}
###### Functions End
##Script start
prerun
shopt -s nocasematch
echo "Mode Set = ${mode} and targeting ${type}"
if [[ "$type" == "mobiledevice" ]]; then
	echo "$(date +'%Y-%m-%d %H:%M:%S') Kicking off Mobile Device App Mode" >> /Users/Shared/VPP_Tool/VPP_Migrator_tool.log
if [[ "$mode" == "off" ]]; then
	echo "$(date +'%Y-%m-%d %H:%M:%S') Kicking off Mobile Device App Mode - Switching off VPP" >> /Users/Shared/VPP_Tool/VPP_Migrator_tool.log
MobileDeviceOff
else
if [[ "$mode" == "on" ]]; then
	echo "$(date +'%Y-%m-%d %H:%M:%S') Kicking off Mobile Device App Mode - Switching on VPP" >> /Users/Shared/VPP_Tool/VPP_Migrator_tool.log
MobileDeviceOn
else
	echo "neither on or off was detected please check the varibles"
fi
fi
else
	echo "$(date +'%Y-%m-%d %H:%M:%S') check for Computer App Mode" >> /Users/Shared/VPP_Tool/VPP_Migrator_tool.log
if [[ "$type" == "computer" ]]; then
	echo "$(date +'%Y-%m-%d %H:%M:%S') Computer App Mode Detected checking mode" >> /Users/Shared/VPP_Tool/VPP_Migrator_tool.log
if [[ "$mode" == "off" ]]; then
	echo "$(date +'%Y-%m-%d %H:%M:%S') Computer App Mode running - Switching off VPP" >> /Users/Shared/VPP_Tool/VPP_Migrator_tool.log
MacAppsOff
else
if [[  "$mode" == "on" ]]; then
	echo "$(date +'%Y-%m-%d %H:%M:%S') Computer App Mode running - Switching on VPP" >> /Users/Shared/VPP_Tool/VPP_Migrator_tool.log
MacAppsOn
else
	echo "No Mode/Type Detected check to see if configured correctly"
fi
echo ""
fi
fi
fi
