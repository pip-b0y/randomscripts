#!/bin/bash

#Renamed - CA-Renewal-Jamf-Pro-Primer
#Version 1.2.1
#Renewing the CA has a number of steps and can be cumbersome to do especially the prework of getting devices into static groups and what not. There is still work that needs to be done manually but this takes some of the burden out of the CA renewal. 
#By Hayden Charters

#1.2.1 Change log.
# - Create the static groups first. Allows for the static groups to be present and avoid issues where the static group is created but caches dont see it. The first couple of devices seem to fail to add to the static group, when in Jamf Cloud. Not an issue for on prem.
# - ComputerStaticGroupCreate and MobileDeviceStaticGroupCreate will do just that. These functions now just create the static groups only
# - MobileDeviceStaticGroupAdd and ComputerStaticGroupAdd functions will put the devices into the static groups.
# - Purge function created - Purge = 1 when set, the rest of the script is ignored. Advance searches are deleted. Static groups created by the functions in this script are deleted as well
# - echo the api reply into the log when adding devices to the static group. For tracking and debugging. Might change this in the future to include a full debug mode.
# - More meaningful logging. rather that just Info!!


#Environment Varibles
username='' #Jamf Pro User Name
password='' #Password for the account
url='' #include https

#purge previous runs
purge='0' #0 = off and runs normally. If set to 1 it will purge all previous work. 

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
	echo "[Info - ComputerAdvanceSearch] $(date +'%Y-%m-%d %H:%M:%S') Creating CA Renewal Tracking Advance Searches. This is for devices that need renewal" >> $logpath
	getBearerToken
	echo "[Info - Authentication] $(date +'%Y-%m-%d %H:%M:%S') Authenticated to Jamf Pro" >> $logpath
	iscreatedcmrn=$(curl -s -H "Authorization: Bearer ${bearerToken}" ${url}/JSSResource/advancedcomputersearches | xpath -e '//advanced_computer_searches/advanced_computer_search/name' 2>&1 | awk -F'<name>|</name>' '{print $2}' | awk NF | grep "terraform MDM Renewal Needed")
	echo "[Info - ComputerAdvanceSearch] $(date +'%Y-%m-%d %H:%M:%S') checking for Advance Search creation" >> $logpath
	if [ "${iscreatedcmrn}" == "terraform MDM Renewal Needed" ]; then
		echo "[Warn - ComputerAdvanceSearch] $(date +'%Y-%m-%d %H:%M:%S') terraform MDM Renewal Needed is found in Jamf Pro. Moving On" >> $logpath
	else
		echo "[Info - ComputerAdvanceSearch] $(date +'%Y-%m-%d %H:%M:%S') Creating the advance search. Not found" >> $logpath
		mdmrncreated=$(curl -s -H "Authorization: Bearer ${bearerToken}" ${url}/JSSResource/advancedcomputersearches/id/0 -X POST -H "Content-Type: application/xml" -d '<advanced_computer_search><name>terraform MDM Renewal Needed</name><view_as>Standard Web Page</view_as><criteria><criterion><name>MDM Profile Renewal Needed - CA Renewed</name><priority>0</priority><and_or>and</and_or><search_type>is</search_type><value>Yes</value><opening_paren>false</opening_paren><closing_paren>false</closing_paren></criterion></criteria><display_fields><size>2</size><display_field><name>Serial Number</name></display_field><display_field><name>Computer Name</name></display_field></display_fields><site><id>-1</id><name>None</name></site></advanced_computer_search>')
		echo "[Info - ComputerAdvanceSearch] $(date +'%Y-%m-%d %H:%M:%S') Created terraform MDM Renewal Needed Advance search ${mdmrncreated}" >> $logpath
	fi
	invalidateToken
}


ComputerAdvanceSearchCheckMDMRC() {
	echo "[Info - ComputerAdvanceSearchCheck] $(date +'%Y-%m-%d %H:%M:%S') Creating CA Renewal Tracking Advance Searches. This is for devices that have renewed or doesnt require it" >> $logpath
	getBearerToken
	echo "[Info - Authentication] $(date +'%Y-%m-%d %H:%M:%S') Authenticated to Jamf Pro" >> $logpath
	iscreatedcmrd=$(curl -s -H "Authorization: Bearer ${bearerToken}" ${url}/JSSResource/advancedcomputersearches | xpath -e '//advanced_computer_searches/advanced_computer_search/name' 2>&1 | awk -F'<name>|</name>' '{print $2}' | awk NF | grep "terraform MDM Renewal Completed")
	echo "[Info - ComputerAdvanceSearchCheck] $(date +'%Y-%m-%d %H:%M:%S') checking for Advance Search creation" >> $logpath
	if [ "${iscreatedcmrd}" == "terraform MDM Renewal Completed" ]; then
		echo "[Warn - ComputerAdvanceSearch] $(date +'%Y-%m-%d %H:%M:%S') terraform MDM Renewal Completed is found in Jamf Pro. Moving On" >> $logpath	
	else
		echo "[Info - ComputerAdvanceSearch] $(date +'%Y-%m-%d %H:%M:%S') Creating the advance search. Not found" >> $logpath
		mdmcccreated=$(curl -s -H "Authorization: Bearer ${bearerToken}" ${url}/JSSResource/advancedcomputersearches/id/0 -X POST -H "Content-Type: application/xml" -d '<advanced_computer_search><name>terraform MDM Renewal Completed</name><view_as>Standard Web Page</view_as><criteria><criterion><name>MDM Profile Renewal Needed - CA Renewed</name><priority>0</priority><and_or>and</and_or><search_type>is</search_type><value>No</value><opening_paren>false</opening_paren><closing_paren>false</closing_paren></criterion></criteria><display_fields><size>2</size><display_field><name>Serial Number</name></display_field><display_field><name>Computer Name</name></display_field></display_fields><site><id>-1</id><name>None</name></site></advanced_computer_search>')
		echo "[Info - ComputerAdvanceSearch] $(date +'%Y-%m-%d %H:%M:%S') Created terraform MDM Renewal Completed Advance search ${mdmcccreated}" >> $logpath
	fi
	invalidateToken
}


MobileDeviceAdvanceSearchCheckMDMRN() {
	echo "[Info - MobileDevicesAdvanceSearch] $(date +'%Y-%m-%d %H:%M:%S') Creating CA Renewal Tracking Advance Searches. This is for devices that need renewal" >> $logpath
	getBearerToken
	echo "[Info - Authentication] $(date +'%Y-%m-%d %H:%M:%S') Authenticated to Jamf Pro" >> $logpath
	iscreatedmdmrn=$(curl -s -H "Authorization: Bearer ${bearerToken}" ${url}/JSSResource/advancedmobiledevicesearches | xpath -e '//advanced_mobile_device_searches/advanced_mobile_device_search/name' 2>&1 | awk -F'<name>|</name>' '{print $2}' | awk NF | grep "terraform MDM Renewal Needed")
	echo "[Info - MobileDevicesAdvanceSearch] $(date +'%Y-%m-%d %H:%M:%S') checking for Advance Search creation" >> $logpath
	if [ "${iscreatedmdmrn}" == "terraform MDM Renewal Needed" ]; then
		echo "[Warn - MobileDevicesAdvanceSearch] $(date +'%Y-%m-%d %H:%M:%S') terraform MDM Renewal Needed is found in Jamf Pro. Moving On" >> $logpath
	else
		echo "[Info - MobileDevicesAdvanceSearch] $(date +'%Y-%m-%d %H:%M:%S') Creating the advance search. Not found" >> $logpath
		mdmdmrncreated=$(curl -s -H "Authorization: Bearer ${bearerToken}" ${url}/JSSResource/advancedmobiledevicesearches/id/0 -X POST -H "Content-Type: application/xml" -d '<advanced_mobile_device_search><name>terraform MDM Renewal Needed</name><view_as>Standard Web Page</view_as><criteria><criterion><name>MDM Profile Renewal Needed - CA Renewed</name><priority>0</priority><and_or>and</and_or><search_type>is</search_type><value>Yes</value><opening_paren>false</opening_paren><closing_paren>false</closing_paren></criterion></criteria><display_fields><size>2</size><display_field><name>Serial Number</name></display_field><display_field><name>Display Name</name></display_field></display_fields><site><id>-1</id><name>None</name></site></advanced_mobile_device_search>')
		echo "[Created - MobileDevicesAdvanceSearch] $(date +'%Y-%m-%d %H:%M:%S') Created terraform MDM Renewal Needed Advance search ${mdmdmrncreated}" >> $logpath
	fi
	invalidateToken
}


MobileDeviceAdvanceSearchCheckMDMRC() {
	echo "[Info - MobileDevicesAdvanceSearch] $(date +'%Y-%m-%d %H:%M:%S') Creating CA Renewal Tracking Advance Searches. This is for devices that have renewed or doesnt require it" >> $logpath
	getBearerToken
	echo "[Info - Authentication] $(date +'%Y-%m-%d %H:%M:%S') Authenticated to Jamf Pro" >> $logpath
	iscreatedmdmrc=$(curl -s -H "Authorization: Bearer ${bearerToken}" ${url}/JSSResource/advancedmobiledevicesearches | xpath -e '//advanced_mobile_device_searches/advanced_mobile_device_search/name' 2>&1 | awk -F'<name>|</name>' '{print $2}' | awk NF | grep "terraform MDM Renewal Completed")
	echo "[Info - MobileDevices] $(date +'%Y-%m-%d %H:%M:%S') checking for Advance Search creation" >> $logpath
	if [ "${iscreatedmdmrc}" == "terraform MDM Renewal Completed" ]; then
		echo "[Warn - MobileDevices] $(date +'%Y-%m-%d %H:%M:%S') terraform MDM Renewal Completed is found in Jamf Pro. Moving On" >> $logpath
	else
		mdmdmrccreated=$(curl -s -H "Authorization: Bearer ${bearerToken}" ${url}/JSSResource/advancedmobiledevicesearches/id/0 -X POST -H "Content-Type: application/xml" -d '<advanced_mobile_device_search><name>terraform MDM Renewal Completed</name><view_as>Standard Web Page</view_as><criteria><criterion><name>MDM Profile Renewal Needed - CA Renewed</name><priority>0</priority><and_or>and</and_or><search_type>is</search_type><value>No</value><opening_paren>false</opening_paren><closing_paren>false</closing_paren></criterion></criteria><display_fields><size>2</size><display_field><name>Serial Number</name></display_field><display_field><name>Display Name</name></display_field></display_fields><site><id>-1</id><name>None</name></site></advanced_mobile_device_search>')
		echo "[Created - MobileDevicesAdvanceSearch] $(date +'%Y-%m-%d %H:%M:%S') Created terraform MDM Renewal Completed Advance search ${mdmdmrccreated}" >> $logpath
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
	echo "[Info - ComputersStaticGroup] $(date +'%Y-%m-%d %H:%M:%S') Broken into groups of 100. Approx ${csgc} groups will be created" >> $logpath
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
		csgcr=$(curl -s -H "Authorization: Bearer ${bearerToken}" ${url}/JSSResource/computergroups/id/0 -X POST -H "Content-Type: application/xml" -d "<computer_group><name>MDMRenew${i}</name><is_smart>false</is_smart></computer_group>")
		echo "[Created - ComputerStaticGroupCreate] $(date +'%Y-%m-%d %H:%M:%S') Created Computer Static Group. MDMRenew${i} ${csgcr}" >> $logpath
		invalidateToken
	done
	
}


ComputersStaticGroupAdd() {
	csgc=$(ls /tmp/computergroup_* | wc -l | tr -d ' ')
	echo "[Info - ComputerStaticGroupAdd] $(date +'%Y-%m-%d %H:%M:%S') Creating Computer Static Groups. ${csgc} groups will be created" >> $logpath
	for (( i=1; i<=${csgc}; i++ ))
	do
		getBearerToken
		echo "[Info - Authentication] $(date +'%Y-%m-%d %H:%M:%S') Authenticated to Jamf Pro" >> $logpath
		echo "[Info - ComputerStaticGroupAdd] $(date +'%Y-%m-%d %H:%M:%S') Adding Computers to computer static group MDMRenew${i}" >> $logpath
		while IFS= read -r line 
		do
			csgar=$(curl -s -k -H "Authorization: Bearer ${bearerToken}" ${url}/JSSResource/computergroups/name/MDMRenew${i} -X PUT -H "Content-Type: application/xml" -d "<computer_group><computer_additions><computer><id>${line}</id></computer></computer_additions></computer_group>")
			echo "[Added - ComputerStaticGroupAdd] $(date +'%Y-%m-%d %H:%M:%S') Added computerid ${line} to MDMRenew${i} if managed" >> $logpath
			echo "[Results - ComputerStaticGroupAdd] $(date +'%Y-%m-%d %H:%M:%S') API Results for ${line} Results = $csgar" >> $logpath
		done < /tmp/computergroup_${i}.file
		invalidateToken
	done	
	rm /tmp/computergroup*
	rm /tmp/ComputerList*
	echo "[Delete - ComputerStaticGroupAdd] $(date +'%Y-%m-%d %H:%M:%S') cleaning up files created in /tmp" >> $logpath
}


#Sorting Devices into bundles of 100 for stability. 
#MobileDevices
MobileDeviceStaticGroupPrep() {
	echo "[Info - MobileDevicesStaticGroupPrep] $(date +'%Y-%m-%d %H:%M:%S') Organising MobileDevices into Groups of 100" >> $logpath
	getBearerToken
	echo "[Info - Authentication] $(date +'%Y-%m-%d %H:%M:%S') Authenticated to Jamf Pro" >> $logpath
	curl -s -H "Authorization: Bearer ${bearerToken}" ${url}/JSSResource/mobiledevices | xpath -e '//mobile_devices/mobile_device/id' 2>&1 | awk -F'<id>|</id>' '{print $2}' | awk NF > /tmp/MobileDeviceListRaw.file
	echo "[Info - MobileDevicesStaticGroupPrep] $(date +'%Y-%m-%d %H:%M:%S') MobileDevices Grabbed, breaking into groups of 100" >> $logpath
	mobiledeviceout="mobiledevicegroup"
	split -l ${mgc} /tmp/MobileDeviceListRaw.file /tmp/${mobiledeviceout}
	c=1
	for mdfile in /tmp/${mobiledeviceout}*; do
		mv $mdfile /tmp/${mobiledeviceout}_${c}.file
		((c++))
	done
	mdsgc=$(ls /tmp/mobiledevicegroup_* | wc -l | tr -d ' ')
	echo "[Info - MobileDevicesStaticGroupPrep] $(date +'%Y-%m-%d %H:%M:%S') Broken into groups of 100. Approx ${mdsgc} groups will be created" >> $logpath
	invalidateToken
}


MobileDeviceStaticGroupCreate() {
	mdsgc=$(ls /tmp/mobiledevicegroup_* | wc -l | tr -d ' ')
	echo "[Info - MobileDeviceStaticGroupCreate] $(date +'%Y-%m-%d %H:%M:%S') Creating MobileDevice Static Groups. ${mdsgc} groups will be created" >> $logpath
	for (( i=1; i<=${mdsgc}; i++ ))
	do
		getBearerToken
		echo "[Info - Authentication] $(date +'%Y-%m-%d %H:%M:%S') Authenticated to Jamf Pro" >> $logpath
		echo "[Info - MobileDeviceStaticGroupCreate] $(date +'%Y-%m-%d %H:%M:%S') creating Mobile Device static group MDMRenew${i}" >> $logpath
		mdsgcr=$(curl -s -H "Authorization: Bearer ${bearerToken}" ${url}/JSSResource/mobiledevicegroups/id/0 -X POST -H "Content-Type: application/xml" -d "<mobile_device_group><name>MDMRenew${i}</name><is_smart>false</is_smart></mobile_device_group>")
		echo "[Created - MobileDevice] $(date +'%Y-%m-%d %H:%M:%S') Created Mobile Device static group MDMRenew${i} ${mdsgcr}" >> $logpath
		invalidateToken
	done
}


MobileDeviceStaticGroupAdd() {
	mdsgc=$(ls /tmp/mobiledevicegroup_* | wc -l | tr -d ' ')
	echo "[Info - MobileDeviceStaticGroupAdd] $(date +'%Y-%m-%d %H:%M:%S') Creating MobileDevice Static Groups. ${mdsgc} groups will be created" >> $logpath
	for (( i=1; i<=${mdsgc}; i++ ))
	do
		getBearerToken
		echo "[Info - Authentication] $(date +'%Y-%m-%d %H:%M:%S') Authenticated to Jamf Pro" >> $logpath
		echo "[Info - MobileDeviceStaticGroupAdd] $(date +'%Y-%m-%d %H:%M:%S') Adding Mobile Devices to static group MDMRenew${i}" >> $logpath
		while IFS= read -r line
		do
			mdmsgar=$(curl -s -k -H "Authorization: Bearer ${bearerToken}" ${url}/JSSResource/mobiledevicegroups/name/MDMRenew${i} -X PUT -H "Content-Type: application/xml" -d "<mobile_device_group><mobile_device_additions><mobile_device><id>${line}</id></mobile_device></mobile_device_additions></mobile_device_group>")
			echo "[Added - MobileDeviceStaticGroupAdd] $(date +'%Y-%m-%d %H:%M:%S') Added MobileDevice ID ${line} to MDMRenew${i} if managed" >> $logpath
			echo "[Results - MobileDevice] API results for ${line} Results = $mdmsgar" >> $logpath
		done < /tmp/mobiledevicegroup_${i}.file
		invalidateToken
	done
	rm /tmp/mobiledevicegroup*
	rm /tmp/MobileDevice*
	rm /tmp/mobiledevice*
	echo "[Delete - MobileDeviceStaticGroupAdd] $(date +'%Y-%m-%d %H:%M:%S') cleaning up files created in /tmp" >> $logpath
}


#Remove Advance Searches
PurgeAdvanceSearch(){
	getBearerToken
	echo "[Info - Authentication] $(date +'%Y-%m-%d %H:%M:%S') Authenticated to Jamf Pro" >> $logpath
	echo "[Info - Purge] $(date +'%Y-%m-%d %H:%M:%S') Seaching for Advance Search gathering IDs " >> $logpath
	delcmrc=$(curl -s -k -H "Authorization: Bearer ${bearerToken}" ${url}/JSSResource/advancedcomputersearches/name/terraform%20MDM%20Renewal%20Completed | xpath -e '//advanced_computer_search/id/' 2>&1 | awk -F'<id>|</id>' '{print $2}' | awk NF)
	delcmrn=$(curl -s -k -H "Authorization: Bearer ${bearerToken}" ${url}/JSSResource/advancedcomputersearches/name/terraform%20MDM%20Renewal%20Needed | xpath -e '//advanced_computer_search/id/' 2>&1 | awk -F'<id>|</id>' '{print $2}' | awk NF)
	delmdmrc=$(curl -s -k -H "Authorization: Bearer ${bearerToken}" ${url}/JSSResource/advancedmobiledevicesearches/name/terraform%20MDM%20Renewal%20Completed | xpath -e '//advanced_mobile_device_search/id/' 2>&1 | awk -F'<id>|</id>' '{print $2}' | awk NF)
	delmdmrn=$(curl -s -k -H "Authorization: Bearer ${bearerToken}" ${url}/JSSResource/advancedmobiledevicesearches/name/terraform%20MDM%20Renewal%20Needed | xpath -e '//advanced_mobile_device_search/id/' 2>&1 | awk -F'<id>|</id>' '{print $2}' | awk NF)
	
	#delete the advance searches terraform MDM Renewal Completed
	if [[ ${delcmrc} =~ ^[0-9]+$ ]]; then
		echo "[Info - Purge] $(date +'%Y-%m-%d %H:%M:%S') Advance search found deleting terraform MDM Renewal Completed for Comptuers" >> $logpath
		delcmrcdel=$(curl -s -k -H "Authorization: Bearer ${bearerToken}" ${url}/JSSResource/advancedcomputersearches/id/${delcmrc} -X DELETE)
		echo "[Delete - Purge] $(date +'%Y-%m-%d %H:%M:%S') Advance Search deleted ${delcmrcdel}" >> $logpath
	else
		echo "[Warn - Purge] $(date +'%Y-%m-%d %H:%M:%S') Advance search Not found" >> $logpath
	fi
	
	#delete the advance searches terraform MDM Renewal Needed
	if [[ ${delcmrn} =~ ^[0-9]+$ ]]; then
		echo "[Info - Purge] $(date +'%Y-%m-%d %H:%M:%S') Advance search found deleting terraform MDM Renewal Needed for Comptuers" >> $logpath
		delcmrndel=$(curl -s -k -H "Authorization: Bearer ${bearerToken}" ${url}/JSSResource/advancedcomputersearches/id/${delcmrn} -X DELETE)
		echo "[Delete - Purge] $(date +'%Y-%m-%d %H:%M:%S') Advance Search deleted $delcmrndel" >> $logpath
	else
		echo "[Warn - Purge] $(date +'%Y-%m-%d %H:%M:%S') Advance search Not found" >> $logpath
	fi
	
	#delete the advance searches terraform MDM Renewal Completed
	if [[ ${delmdmrc} =~ ^[0-9]+$ ]]; then
		echo "[Info - Purge] $(date +'%Y-%m-%d %H:%M:%S') Advance search found deleting terraform MDM Renewal Completed for MobileDevices" >> $logpath
		delmdmrcdel=$(curl -s -k -H "Authorization: Bearer ${bearerToken}" ${url}/JSSResource/advancedmobiledevicesearches/id/${delmdmrc} -X DELETE)
		echo "[Delete - Purge] $(date +'%Y-%m-%d %H:%M:%S') Advance Search deleted ${delmdmrcdel}" >> $logpath
	else
		echo "[Warn - Purge] $(date +'%Y-%m-%d %H:%M:%S') Advance search Not found" >> $logpath
	fi
	
	
	#delete the advance searches terraform MDM Renewal Needed
	if [[ ${delmdmrn} =~ ^[0-9]+$ ]]; then
		echo "[Info - Purge] $(date +'%Y-%m-%d %H:%M:%S') Advance search found deleting terraform MDM Renewal Needed for MobileDevices" >> $logpath
		delmdmrndel=$(curl -s -k -H "Authorization: Bearer ${bearerToken}" ${url}/JSSResource/advancedmobiledevicesearches/id/${delmdmrn} -X DELETE)
		echo "[Delete - Purge] $(date +'%Y-%m-%d %H:%M:%S') Advance Search deleted $delmdmrndel" >> $logpath
	else
		echo "[Warn - Purge] $(date +'%Y-%m-%d %H:%M:%S') Advance search Not found" >> $logpath
	fi
	invalidateToken 
}


#PurgeStaticGroups - Computers
PurgeStaticComputerGroup() {
	getBearerToken
	echo "[Info - Authentication] $(date +'%Y-%m-%d %H:%M:%S') Authenticated to Jamf Pro" >> $logpath	
	echo "[Info - PurgeStaticComputerGroup] $(date +'%Y-%m-%d %H:%M:%S') Gathering Static Groups for Computers" >> $logpath
	curl -s -k -H "Authorization: Bearer ${bearerToken}" ${url}/JSSResource/computergroups | xpath -e '//computer_groups/computer_group/name' 2>&1 | awk -F'<name>|</name>' '{print $2}' | awk NF | grep 'MDMRenew' >> /tmp/csraw.file
	while IFS= read -r linepsc 
	do 
		echo "[Info - PurgeStaticComputerGroup] $(date +'%Y-%m-%d %H:%M:%S') Purging ${linepsc}" >> $logpath
		csid=$(curl -s -k -H "Authorization: Bearer ${bearerToken}" ${url}/JSSResource/computergroups/name/${linepsc} | xpath -e '//computer_group/id' 2>&1 | awk -F'<id>|</id>' '{print $2}' | awk NF)
		delcsid=$(curl -s -k -H "Authorization: Bearer ${bearerToken}" ${url}/JSSResource/computergroups/id/${csid} -X DELETE)
		echo "[Delete - PurgeStaticComputerGroup] $(date +'%Y-%m-%d %H:%M:%S') Purged ${linepsc} Results ${delcsid}" >> $logpath
	done < /tmp/csraw.file
	echo "[Info - PurgeStaticComputerGroup] $(date +'%Y-%m-%d %H:%M:%S') Computer Static Groups completed" >> $logpath
	rm /tmp/csraw.file
	invalidateToken 
}

#PurgeStaticGroups - MobileDevices
PurgeStaticMobileDeviceGroup() {
	getBearerToken
	echo "[Info - Authentication] $(date +'%Y-%m-%d %H:%M:%S') Authenticated to Jamf Pro" >> $logpath	
	echo "[Info - PurgeStaticMobileDeviceGroup] $(date +'%Y-%m-%d %H:%M:%S') Gathering Static Groups for Mobile Device" >> $logpath
	curl -s -k -H "Authorization: Bearer ${bearerToken}" ${url}/JSSResource/mobiledevicegroups | xpath -e '//mobile_device_groups/mobile_device_group/name' 2>&1 | awk -F'<name>|</name>' '{print $2}' | awk NF | grep 'MDMRenew' >> /tmp/mdsraw.file
	while IFS= read -r linepsmd 
	do 
		echo "[Info - PurgeStaticMobileDeviceGroup] $(date +'%Y-%m-%d %H:%M:%S') Purging ${linepsmd}" >> $logpath
		mdsid=$(curl -s -k -H "Authorization: Bearer ${bearerToken}" ${url}/JSSResource/mobiledevicegroups/name/${linepsmd} | xpath -e '//mobile_device_group/id' 2>&1 | awk -F'<id>|</id>' '{print $2}' | awk NF)
		delmdsid=$(curl -s -k -H "Authorization: Bearer ${bearerToken}" ${url}/JSSResource/mobiledevicegroups/id/${mdsid} -X DELETE)
		echo "[Delete - PurgeStaticMobileDeviceGroup] $(date +'%Y-%m-%d %H:%M:%S') Purged ${linepsmd} Results ${delmdsid}" >> $logpath
	done < /tmp/mdsraw.file
	echo "[Info - PurgeStaticMobileDeviceGroup] $(date +'%Y-%m-%d %H:%M:%S') MobileDevice Static Groups completed" >> $logpath
	rm /tmp/mdsraw.file
	invalidateToken
	rm /tmp/mobile*
	rm /tmp/computer*
	rm /tmp/Mobile*
	rm /tmp/Computer*
}


if [[ ${purge} == '1' ]];then
	echo "[Info - CARenewal-JamfProPrimer] Purge is active. Purging work done previously." >> $logpath
	PurgeAdvanceSearch
	PurgeStaticComputerGroup
	PurgeStaticMobileDeviceGroup
	echo "[Info - CARenewal-JamfProPrimer] Purge is complete closing script" >> $logpath
	exit 0
else
	echo "[Info - CARenewal-JamfProPrimer] Purge is disabled. Running normal script" >> $logpath	
	#Terra From Script
	echo "[Info - CARenewal-JamfProPrimer] Script starting run for CA Renewal Prep" >> $logpath
	echo "[Info - CARenewal-JamfProPrimer] $(date +'%Y-%m-%d %H:%M:%S') Starting to check Computer Advance Searches Now" >> $logpath
	ComputerAdvanceSearchCheckMDMRN
	ComputerAdvanceSearchCheckMDMRC
	echo "[Info - CARenewal-JamfProPrimer] $(date +'%Y-%m-%d %H:%M:%S') Computer Advance Search has been completed" >> $logpath
	echo "[Info - CARenewal-JamfProPrimer] $(date +'%Y-%m-%d %H:%M:%S') Starting to check Mobile Device Advance Searches Now" >> $logpath
	MobileDeviceAdvanceSearchCheckMDMRN
	MobileDeviceAdvanceSearchCheckMDMRC
	echo "[Info - CARenewal-JamfProPrimer] $(date +'%Y-%m-%d %H:%M:%S') Mobile Device Advance Search has been completed" >> $logpath
	echo "[Info - CARenewal-JamfProPrimer] $(date +'%Y-%m-%d %H:%M:%S') Advance Searches Completed Exporting devices" >> $logpath
	echo "[Info - CARenewal-JamfProPrimer] $(date +'%Y-%m-%d %H:%M:%S') Breaking Down Computer devices and creating static groups" >> $logpath
	ComputersStaticGroupPrep
	ComputersStaticGroupCreate
	echo "[Info - CARenewal-JamfProPrimer] $(date +'%Y-%m-%d %H:%M:%S') Adding Computers to Static Groups" >> $logpath
	ComputersStaticGroupAdd
	echo "[Info - CARenewal-JamfProPrimer] $(date +'%Y-%m-%d %H:%M:%S') Static Groups created for computers. Please spot check" >> $logpath
	echo "[Info - CARenewal-JamfProPrimer] $(date +'%Y-%m-%d %H:%M:%S') Breaking Down Mobile Devices and creating static groups" >> $logpath
	MobileDeviceStaticGroupPrep
	MobileDeviceStaticGroupCreate
	echo "[Info - CARenewal-JamfProPrimer] $(date +'%Y-%m-%d %H:%M:%S') Adding Mobile Devices to Static Groups" >> $logpath
	MobileDeviceStaticGroupAdd
	echo "[Info - CARenewal-JamfProPrimer] $(date +'%Y-%m-%d %H:%M:%S') Static Groups created for Mobile Devices. Please spot check" >> $logpath
	echo "The hard work is done now. You need to go into Jamf Pro and do the following"
	echo "1 - Go to Settings > MDM Profile Settings"
	echo "2 - Uncheck all of the options and save this"
	echo "3 - select a mobile device and Computer device and send a mdm renew command from the device record"
	echo "4 - Engage with support for the next steps of CA Renewal. The Pre Work is done."
fi
