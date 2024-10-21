#!/bin/bash
#site Counter v1
#counts device split in sites.
username='' #Jamf Pro User Name 
password='' #Jamf Pro Password
url='' #Jamf Pro URL including https://

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

##Script below
computersitecount() {
	getBearerToken
curl -s -H "Authorization: Bearer ${bearerToken}" $url/JSSResource/computers | xmllint --format - > /tmp/computerlist
computeridraw=$(cat /tmp/computerlist | xpath -e '//computer/id' 2>&1 | awk -F'<id>|</id>' '{print $2}')
for computerid in ${computeridraw}; do
computersitename=$(curl -s -H "Authorization: Bearer ${bearerToken}" $url/JSSResource/computers/id/${computerid} -X GET | xmllint --format - | xpath -e '//computer/general/site' | awk -F'<name>|</name>' '{print $2}')
if ! ls /tmp/ | grep "$computersitename.jprocomputer"; then
echo "object not created"
touch /tmp/$computersitename.jpro
echo "$computerid" >> /tmp/$computersitename.jprocomputer
else
echo "$computerid" >> /tmp/$computersitename.jprocomputer
fi
done
}
mobiledevicecount() {
curl -s -H "Authorization: Bearer ${bearerToken}" $url/JSSResource/mobiledevices | xmllint --format - > /tmp/mobiledevicelist
mobiledeviceidraw=$(cat /tmp/mobiledevicelist | xmpath -e '//mobile_device/id' 2>&1 | awk -F'<id>|</id>' '{print $2}')
for mobiledeviceid in ${mobiledeviceidraw}; do
mobiledevicesitename=$(curl -s -H "Authorization: Bearer ${bearerToken}" $url/JSSResource/mobiledevices/id/${mobiledeviceid} | xmllint --format - | xpath -e '//mobile_device/general/site' | awk -F'<name>|</name>' '{print $2}')
if ! ls /tmp/ | grep "$mobiledevicesitename.jpromd"; then
	echo "object not created"
	touch /tmp/$mobiledevicesitename.jpromd
	echo "$mobiledeviceid" > /tmp/$mobiledevicesitename.jpromd
else
echo "$mobiledeviceid" > /tmp/$mobiledevicesitename.jpromd
fi
done
}
reportcreate() {
computersraw=$(ls /tmp/ | grep ".jprocomputer" > /tmp/clistbuild)
touch /tmp/final_device_count_report.txt
while IFS= read clist; do
ccount=$(cat /tmp/$clist | wc -l )
csitename=$(basename "$clist" .jprocomputer)
echo "$csitename computers:${ccount}" >> /tmp/final_device_count_report.txt
done < /tmp/clistbuild
mobiledeviceraw=$(ls /tmp/ | grep ".jpromd" > /tmp/mlistbuild)
while IFS= read mlist; do
mcount=$(cat /tmp/$mlist | wc -l )
msitename=$(basename "$mlist" .jpromd)
echo "$msitename mobiledevices:${mcount}" >> /tmp/final_device_count_report.txt
done < /tmp/mlistbuild
}

computersitecount
mobiledevicecount
reportcreate
cat /tmp/final_device_count_report.txt
