#!/bin/bash

#CA Renew Terra form
#Version 1.1RC
#Renewing the CA has a number of steps and can be cumbersome to do especially the prework of getting devices into static groups and what not. There is still work that needs to be done manually but this takes some of the burden out of the CA renewal. 


#Environment Varibles
username='' #Jamf Pro User Name
password='' #Password for the account
url='' #include https

#Static Dont Change
bearerToken=""
tokenExpirationEpoch="0"
logpath='/tmp/CA-RenewTerraForm.log'
mgc='100'

#Functions (Authentication)
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


#Functions Advance search check and creation
ComputerAdvanceSearchCheckMDMRN() {
echo "[Info - Computers] $(date +'%Y-%m-%d %H:%M:%S') Creating CA Renewal Tracking Advance Searches. This is for devices that need renewal" >> $logpath
getBearerToken
echo "[Info - Authentication] $(date +'%Y-%m-%d %H:%M:%S') Authenticated to Jamf Pro" >> $logpath
iscreatedcmrn=$(curl -s -H "Authorization: Bearer ${bearerToken}" ${url}/JSSResource/advancedcomputersearches | xpath -e '//advanced_computer_searches/advanced_computer_search/name' 2>&1 | awk -F'<name>|</name>' '{print $2}' | awk NF | grep "terraform MDM Renewal Needed")
echo "[Info - Computers] $(date +'%Y-%m-%d %H:%M:%S') checking for Advance Search creation" >> $logpath
if [ "${iscreatedcmrn}" == "terraform MDM Renewal Needed" ]; then
echo "[Warn - Computers] $(date +'%Y-%m-%d %H:%M:%S') terraform MDM Renewal Needed is found in Jamf Pro. Moving On" >> $logpath
else
echo "[Info - Computers] $(date +'%Y-%m-%d %H:%M:%S') Creating the advance search. Not found" >> $logpath
mdmrncreated=$(curl -s -H "Authorization: Bearer ${bearerToken}" ${url}/JSSResource/advancedcomputersearches/id/0 -X POST -H "Content-Type: application/xml" -d '<advanced_computer_search><name>terraform MDM Renewal Needed</name><view_as>Standard Web Page</view_as><criteria><criterion><name>MDM Profile Renewal Needed - CA Renewed</name><priority>0</priority><and_or>and</and_or><search_type>is</search_type><value>Yes</value><opening_paren>false</opening_paren><closing_paren>false</closing_paren></criterion></criteria><display_fields><size>2</size><display_field><name>Serial Number</name></display_field><display_field><name>Computer Name</name></display_field></display_fields><site><id>-1</id><name>None</name></site></advanced_computer_search>')
echo "[Info - Computers] $(date +'%Y-%m-%d %H:%M:%S') Created terraform MDM Renewal Needed Advance search ${mdmrncreated}" >> $logpath
fi
invalidateToken
}


ComputerAdvanceSearchCheckMDMRC() {
echo "[Info - Computers] $(date +'%Y-%m-%d %H:%M:%S') Creating CA Renewal Tracking Advance Searches. This is for devices that have renewed or doesnt require it" >> $logpath
getBearerToken
echo "[Info - Authentication] $(date +'%Y-%m-%d %H:%M:%S') Authenticated to Jamf Pro" >> $logpath
iscreatedcmrd=$(curl -s -H "Authorization: Bearer ${bearerToken}" ${url}/JSSResource/advancedcomputersearches | xpath -e '//advanced_computer_searches/advanced_computer_search/name' 2>&1 | awk -F'<name>|</name>' '{print $2}' | awk NF | grep "terraform MDM Renewal Completed")
echo "[Info - Computers] $(date +'%Y-%m-%d %H:%M:%S') checking for Advance Search creation" >> $logpath
if [ "${iscreatedcmrd}" == "terraform MDM Renewal Completed" ]; then
echo "[Warn - Computers] $(date +'%Y-%m-%d %H:%M:%S') terraform MDM Renewal Completed is found in Jamf Pro. Moving On" >> $logpath	
else
echo "[Info - Computers] $(date +'%Y-%m-%d %H:%M:%S') Creating the advance search. Not found" >> $logpath
mdmcccreated=$(curl -s -H "Authorization: Bearer ${bearerToken}" ${url}/JSSResource/advancedcomputersearches/id/0 -X POST -H "Content-Type: application/xml" -d '<advanced_computer_search><name>terraform MDM Renewal Completed</name><view_as>Standard Web Page</view_as><criteria><criterion><name>MDM Profile Renewal Needed - CA Renewed</name><priority>0</priority><and_or>and</and_or><search_type>is</search_type><value>No</value><opening_paren>false</opening_paren><closing_paren>false</closing_paren></criterion></criteria><display_fields><size>2</size><display_field><name>Serial Number</name></display_field><display_field><name>Computer Name</name></display_field></display_fields><site><id>-1</id><name>None</name></site></advanced_computer_search>')
echo "[Info - Computers] $(date +'%Y-%m-%d %H:%M:%S') Created terraform MDM Renewal Completed Advance search ${mdmcccreated}" >> $logpath
fi
invalidateToken
}


MobileDeviceAdvanceSearchCheckMDMRN() {
echo "[Info - MobileDevices] $(date +'%Y-%m-%d %H:%M:%S') Creating CA Renewal Tracking Advance Searches. This is for devices that need renewal" >> $logpath
getBearerToken
echo "[Info - Authentication] $(date +'%Y-%m-%d %H:%M:%S') Authenticated to Jamf Pro" >> $logpath
iscreatedmdmrn=$(curl -s -H "Authorization: Bearer ${bearerToken}" ${url}/JSSResource/advancedmobiledevicesearches | xpath -e '//advanced_mobile_device_searches/advanced_mobile_device_search/name' 2>&1 | awk -F'<name>|</name>' '{print $2}' | awk NF | grep "terraform MDM Renewal Needed")
echo "[Info - MobileDevices] $(date +'%Y-%m-%d %H:%M:%S') checking for Advance Search creation" >> $logpath
if [ "${iscreatedmdmrn}" == "terraform MDM Renewal Needed" ]; then
echo "[Warn - MobileDevices] $(date +'%Y-%m-%d %H:%M:%S') terraform MDM Renewal Needed is found in Jamf Pro. Moving On" >> $logpath
else
echo "[Info - MobileDevices] $(date +'%Y-%m-%d %H:%M:%S') Creating the advance search. Not found" >> $logpath
mdmdmrncreated=$(curl -s -H "Authorization: Bearer ${bearerToken}" ${url}/JSSResource/advancedmobiledevicesearches/id/0 -X POST -H "Content-Type: application/xml" -d '<advanced_mobile_device_search><name>terraform MDM Renewal Needed</name><view_as>Standard Web Page</view_as><criteria><criterion><name>MDM Profile Renewal Needed - CA Renewed</name><priority>0</priority><and_or>and</and_or><search_type>is</search_type><value>Yes</value><opening_paren>false</opening_paren><closing_paren>false</closing_paren></criterion></criteria><display_fields><size>2</size><display_field><name>Serial Number</name></display_field><display_field><name>Display Name</name></display_field></display_fields><site><id>-1</id><name>None</name></site></advanced_mobile_device_search>')
echo "[Info - MobileDevices] $(date +'%Y-%m-%d %H:%M:%S') Created terraform MDM Renewal Needed Advance search ${mdmdmrncreated}" >> $logpath
fi
invalidateToken
}


MobileDeviceAdvanceSearchCheckMDMRC() {
echo "[Info - MobileDevices] $(date +'%Y-%m-%d %H:%M:%S') Creating CA Renewal Tracking Advance Searches. This is for devices that have renewed or doesnt require it" >> $logpath
getBearerToken
echo "[Info - Authentication] $(date +'%Y-%m-%d %H:%M:%S') Authenticated to Jamf Pro" >> $logpath
iscreatedmdmrc=$(curl -s -H "Authorization: Bearer ${bearerToken}" ${url}/JSSResource/advancedmobiledevicesearches | xpath -e '//advanced_mobile_device_searches/advanced_mobile_device_search/name' 2>&1 | awk -F'<name>|</name>' '{print $2}' | awk NF | grep "terraform MDM Renewal Completed")
echo "[Info - MobileDevices] $(date +'%Y-%m-%d %H:%M:%S') checking for Advance Search creation" >> $logpath
if [ "${iscreatedmdmrc}" == "terraform MDM Renewal Completed" ]; then
echo "[Warn - MobileDevices] $(date +'%Y-%m-%d %H:%M:%S') terraform MDM Renewal Completed is found in Jamf Pro. Moving On" >> $logpath
else
mdmdmrccreated=$(curl -s -H "Authorization: Bearer ${bearerToken}" ${url}/JSSResource/advancedmobiledevicesearches/id/0 -X POST -H "Content-Type: application/xml" -d '<advanced_mobile_device_search><name>terraform MDM Renewal Completed</name><view_as>Standard Web Page</view_as><criteria><criterion><name>MDM Profile Renewal Needed - CA Renewed</name><priority>0</priority><and_or>and</and_or><search_type>is</search_type><value>No</value><opening_paren>false</opening_paren><closing_paren>false</closing_paren></criterion></criteria><display_fields><size>2</size><display_field><name>Serial Number</name></display_field><display_field><name>Display Name</name></display_field></display_fields><site><id>-1</id><name>None</name></site></advanced_mobile_device_search>')
echo "[Info - MobileDevices] $(date +'%Y-%m-%d %H:%M:%S') Created terraform MDM Renewal Completed Advance search ${mdmdmrccreated}" >> $logpath
fi
invalidateToken
}

#Sorting Devices into bundles of 100 for stability. 
#Computers
ComputersStaticGroupPrep() {
echo "[Info - Computers] $(date +'%Y-%m-%d %H:%M:%S') Organising Computers into Groups of 100" >> $logpath
getBearerToken
echo "[Info - Authentication] $(date +'%Y-%m-%d %H:%M:%S') Authenticated to Jamf Pro" >> $logpath
curl -s -H "Authorization: Bearer ${bearerToken}" ${url}/JSSResource/computers | xpath -e '//computers/computer/id' 2>&1 | awk -F'<id>|</id>' '{print $2}' | awk NF > /tmp/ComputerListRaw.file
echo "[Info - Computers] $(date +'%Y-%m-%d %H:%M:%S') Computers Grabbed, breaking into groups of 100" >> $logpath
computerout='computergroup'
split -l ${mgc} /tmp/ComputerListRaw.file /tmp/${computerout}
i=1
for comfile in /tmp/${computerout}*; do
	mv $comfile /tmp/${computerout}_${i}.file
	((i++))
done
csgc=$(ls /tmp/computergroup_* | wc -l | tr -d ' ')
echo "[Info - Computers] $(date +'%Y-%m-%d %H:%M:%S') Broken into groups of 100. Approx ${csgc} groups will be created" >> $logpath
invalidateToken
}


ComputersStaticGroupCreate() {
csgc=$(ls /tmp/computergroup_* | wc -l | tr -d ' ')
echo "[Info - Computers] $(date +'%Y-%m-%d %H:%M:%S') Creating Computer Static Groups. ${csgc} groups will be created" >> $logpath
for (( i=1; i<=${csgc}; i++ ))
do
getBearerToken
echo "[Info - Authentication] $(date +'%Y-%m-%d %H:%M:%S') Authenticated to Jamf Pro" >> $logpath
echo "[Info - Computers] $(date +'%Y-%m-%d %H:%M:%S') creating computer static group MDMRenew${i}" >> $logpath
curl -s -H "Authorization: Bearer ${bearerToken}" ${url}/JSSResource/computergroups/id/0 -X POST -H "Content-Type: application/xml" -d "<computer_group><name>MDMRenew${i}</name><is_smart>false</is_smart></computer_group>" > /tmp/computerad-dump
while IFS= read -r line 
do
curl -s -k -H "Authorization: Bearer ${bearerToken}" ${url}/JSSResource/computergroups/name/MDMRenew${i} -X PUT -H "Content-Type: application/xml" -d "<computer_group><computer_additions><computer><id>${line}</id></computer></computer_additions></computer_group>" > /tmp/computerad-dump
echo "[Info - Computers] $(date +'%Y-%m-%d %H:%M:%S') Added computerid ${line} to MDMRenew${i} if managed" >> $logpath
done < /tmp/computergroup_${i}.file
invalidateToken
done

echo "[Info - Computers] $(date +'%Y-%m-%d %H:%M:%S') Computer Static Groups created. Please spot check" >> $logpath
rm /tmp/computergroup*
rm /tmp/ComputerList*
rm /tmp/computerad-dump
echo "[Info - Computers] $(date +'%Y-%m-%d %H:%M:%S') cleaning up files created in /tmp" >> $logpath
}


#Sorting Devices into bundles of 100 for stability. 
#MobileDevices
MobileDeviceStaticGroupPrep() {
echo "[Info - MobileDevices] $(date +'%Y-%m-%d %H:%M:%S') Organising MobileDevices into Groups of 100" >> $logpath
getBearerToken
echo "[Info - Authentication] $(date +'%Y-%m-%d %H:%M:%S') Authenticated to Jamf Pro" >> $logpath
curl -s -H "Authorization: Bearer ${bearerToken}" ${url}/JSSResource/mobiledevices | xpath -e '//mobile_devices/mobile_device/id' 2>&1 | awk -F'<id>|</id>' '{print $2}' | awk NF > /tmp/MobileDeviceListRaw.file
echo "[Info - MobileDevices] $(date +'%Y-%m-%d %H:%M:%S') MobileDevices Grabbed, breaking into groups of 100" >> $logpath
mobiledeviceout="mobiledevicegroup"
split -l ${mgc} /tmp/MobileDeviceListRaw.file /tmp/${mobiledeviceout}
c=1
for mdfile in /tmp/${mobiledeviceout}*; do
	mv $mdfile /tmp/${mobiledeviceout}_${c}.file
	((c++))
done
mdsgc=$(ls /tmp/mobiledevicegroup_* | wc -l | tr -d ' ')
echo "[Info - MobileDevices] $(date +'%Y-%m-%d %H:%M:%S') Broken into groups of 100. Approx ${mdsgc} groups will be created" >> $logpath
invalidateToken
}


MobileDeviceStaticGroupCreate() {
mdsgc=$(ls /tmp/mobiledevicegroup_* | wc -l | tr -d ' ')
echo "[Info - MobileDevices] $(date +'%Y-%m-%d %H:%M:%S') Creating Computer Static Groups. ${mdsgc} groups will be created" >> $logpath
for (( i=1; i<=${mdsgc}; i++ ))
do
getBearerToken
echo "[Info - Authentication] $(date +'%Y-%m-%d %H:%M:%S') Authenticated to Jamf Pro" >> $logpath
echo "[Info - MobileDevice] $(date +'%Y-%m-%d %H:%M:%S') creating Mobile Device static group MDMRenew${i}" >> $logpath
curl -s -H "Authorization: Bearer ${bearerToken}" ${url}/JSSResource/mobiledevicegroups/id/0 -X POST -H "Content-Type: application/xml" -d "<mobile_device_group><name>MDMRenew${i}</name><is_smart>false</is_smart></mobile_device_group>" > /tmp/mobiledevice-dump
while IFS= read -r line
do
curl -s -k -H "Authorization: Bearer ${bearerToken}" ${url}/JSSResource/mobiledevicegroups/name/MDMRenew${i} -X PUT -H "Content-Type: application/xml" -d "<mobile_device_group><mobile_device_additions><mobile_device><id>${line}</id></mobile_device></mobile_device_additions></mobile_device_group>" > /tmp/mobiledevice-dump
echo "[Info - MobileDevice] $(date +'%Y-%m-%d %H:%M:%S') Added MobileDevice ID ${line} to MDMRenew${i} if managed" >> $logpath
done < /tmp/mobiledevicegroup_${i}.file
invalidateToken
done
rm /tmp/mobiledevicegroup*
rm /tmp/MobileDevice*
rm /tmp/mobiledevice*
echo "[Info - MobileDevice] $(date +'%Y-%m-%d %H:%M:%S') cleaning up files created in /tmp" >> $logpath
}


#Terra From Script
echo "[Info - TerraFormCA] Script starting run for CA Renewal Prep" >> $logpath
echo "[Info - TerraFormCA] $(date +'%Y-%m-%d %H:%M:%S') Starting to check Computer Advance Searches Now" >> $logpath
ComputerAdvanceSearchCheckMDMRN
ComputerAdvanceSearchCheckMDMRC
echo "[Info - TerraFormCA] $(date +'%Y-%m-%d %H:%M:%S') Computer Advance Search has been completed" >> $logpath
echo "[Info - TerraFormCA] $(date +'%Y-%m-%d %H:%M:%S') Starting to check Mobile Device Advance Searches Now" >> $logpath
MobileDeviceAdvanceSearchCheckMDMRN
MobileDeviceAdvanceSearchCheckMDMRC
echo "[Info - TerraFormCA] $(date +'%Y-%m-%d %H:%M:%S') Mobile Device Advance Search has been completed" >> $logpath
echo "[Info - TerraFormCA] $(date +'%Y-%m-%d %H:%M:%S') Advance Searches Completed Exporting devices" >> $logpath
echo "[Info - TerraFormCA] $(date +'%Y-%m-%d %H:%M:%S') Breaking Down Computer devices and creating static groups" >> $logpath
ComputersStaticGroupPrep
ComputersStaticGroupCreate
echo "[Info - TerraFormCA] $(date +'%Y-%m-%d %H:%M:%S') Static Groups created for computers. Please spot check" >> $logpath
echo "[Info - TerraFormCA] $(date +'%Y-%m-%d %H:%M:%S') Breaking Down Mobile Devices and creating static groups" >> $logpath
MobileDeviceStaticGroupPrep
MobileDeviceStaticGroupCreate
echo "[Info - TerraFormCA] $(date +'%Y-%m-%d %H:%M:%S') Static Groups created for Mobile Devices. Please spot check" >> $logpath
echo "The hard work is done now. You need to go into Jamf Pro and do the following"
echo "1 - Go to Settings > MDM Profile Settings"
echo "2 - Uncheck all of the options and save this"
echo "3 - select a mobile device and Computer device and send a mdm renew command from the device record"
echo "4 - Engage with support for the next steps of CA Renewal. The Pre Work is done."
