#!/bin/bash
#User Creater V1
#Creates users, doesnt assign devices just creates a bunch of users for noise.
url='' #with https or http depending on your test server
username=''
password=''
userscreate='' #number only
#functions
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
getBearerToken
for ((currentcount=1; currentcount<=userscreate; currentcount++))
do 
	echo "$currentcount"
getBearerToken 
curl -s -H "Authorization: Bearer ${bearerToken}" ${url}/JSSResource/users/id/0 -X POST --header "Content-Type: text/xml" --data "<user><name>SmokeTestUser${currentcount}</name><full_name>SmokeTestUser ${currentcount}</full_name><email>SmokeTestUser${currentcount}@UserCreateScript.local</email><email_address>SmokeTestUser${currentcount}@UserCreateScript.local</email_address></user>"
if (( currentcount % 1000 == 0 )); then
	invalidateToken
	getBearerToken
fi
if (( currentcount % 100 == 0 )); then
	sleep 3
	echo "sleeping for 3"
fi
done
