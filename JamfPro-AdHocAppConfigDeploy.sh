#!/bin/bash
#Name: AppConfigDeploy-V1.1
#© 2017, JAMF Software, LLC.
#THE SOFTWARE IS PROVIDED "AS-IS," WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NON-INFRINGEMENT. IN NO EVENT SHALL JAMF SOFTWARE, LLC OR ANY OF ITS AFFILIATES BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT, OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OF OR OTHER DEALINGS IN THE SOFTWARE, INCLUDING BUT NOT LIMITED TO DIRECT, INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL OR PUNITIVE DAMAGES AND OTHER DAMAGES SUCH AS LOSS OF USE, PROFITS, SAVINGS, TIME OR DATA, BUSINESS INTERRUPTION, OR PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES.
#Created by Hayden Charter
#Notes:
#App config needs to be in xml format and in a single line. 
#PerAppVPN UUID can be gathered by either database or looking at the UUID of the profile deployed.
#Target devices should be placed in a specific group. Dont worry about spaces in the name, it will be made API friendly.
#Version 1.1 changes:
#clean up funtion added to remove old files
#changed vpnUuid to vpnUUID
#
#
#
###Set Varibles
username='' #Jamf Pro User Name
password='' #Password for the account
url='' #include https
groupname_raw='' #Raw group name
groupname=$(printf "%s\n" "${groupname_raw}" | sed 's/ /%20/g' ) #dont modify
managedappconfig='' #In the following format <plist><dict><key>SOMEKEY</key><string>KeyValue</string></dict></plist>
appidentifer='' #the app identifier eg com.google.chrome
vpnuuid='' #the UUID of the VPN Payload. Reach out to support to get this value.
#Variable declarations# Don't Change Below
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
buildlist() {
#Builds a list of management ids
getBearerToken
curl -s -H "Authorization: Bearer ${bearerToken}" $url/JSSResource/mobiledevicegroups/name/${groupname}  | xmllint --format - > /tmp/build-list-raw.xml
mobiledeviceraw=$(cat /tmp/build-list-raw.xml | xpath -e '//mobile_device_group/mobile_devices/mobile_device/id'  2>&1 | awk -F'<id>|</id>' '{print $2}')
for mdid in $mobiledeviceraw; do
curl -s -H "Authorization: Bearer ${bearerToken}" $url/api/v2/mobile-devices/$mdid --header 'accept: application/json' | plutil -extract managementId raw - >> /tmp/managedids.log		
done
invalidateToken 
}
sendcommand() {
#sends the management command to the device
getBearerToken
while IFS= read -r line
do
echo "sending attributes to ${line}"
postattributes=$(curl -s -H "Authorization: Bearer ${bearerToken}" $url/api/v2/mdm/commands -H "content-type: application/json" --data "{\"commandData\": {\"commandType\": \"SETTINGS\",\"applicationAttributes\": {\"identifier\": \"$appidentifer\",\"attributes\": {\"removable\": false,\"vpnUUID\":\"$vpnuuid\"}},\"applicationConfiguration\": {\"configuration\": \"$managedappconfig\",\"identifier\": \"$appidentifer\"}},\"clientData\": [{\"managementId\": \"$line\"}]}")
echo $postattributes
done < /tmp/managedids.log
invalidateToken
}
clean() {
#clean function
	rm /tmp/managedids.log
	rm /tmp/build-list-raw.xml
}

buildlist
sendcommand
clean
