#!/bin/bash
#Per app usage report
username="" #Jamf Pro user name 
password="" #Jamf Pro user password 
url="" #Jamf Pro URL
asraw='' #Advance search
startdate='' #in yyyy-mm-dd format
enddate='' #in yyyy-mm-dd format
appnameraw='' ## App Name as it appears in Application Usage in a device record. eg Google Chrome
#transformer
ascon=$(printf "%s\n" "${asraw}" | sed 's/ /%20/g')
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
########
#Script Below
touch /tmp/Applicaiton_report_${startdate}_${enddate}.txt
getBearerToken
curl -s -H "Authorization: Bearer ${bearerToken}" $url/JSSResource/advancedcomputersearches/name/${ascon} -X GET > /tmp/ascon_raw.xml

idraw=$(cat /tmp/ascon_raw.xml | xpath -e '//advanced_computer_search/computers/computer/id' 2>&1 | awk -F'<id>|</id>' '{print $2}')
for id in ${idraw};do
    curl -s -H "Authorization: Bearer ${bearerToken}" $url/JSSResource/computers/id/${id} -X GET > /tmp/${id}_name.xml
    computername=$(cat /tmp/${id}_name.xml | xpath -e '//computer/general/name' 2>&1 | awk -F'<name>|</name>' '{print $2}' | tr -d '\n')
    echo "${computername}"
    curl -s -H "Authorization: Bearer ${bearerToken}" $url/JSSResource/computerapplicationusage/id/${id}/${startdate}_${enddate} | xmllint --format - > /tmp/${id}_report.xml
    echo $id
testvalue=$(xpath -e "//app[name='${appname}']/foreground/text()" /tmp/${id}_report.xml)
echo $testvalue
    total_sum=0
    while IFS= read -r value; do
        total_sum=$((total_sum + value))
        echo "current $total_sum"
    done < <(xpath -e "//app[name='${appnameraw}']/foreground/text()" /tmp/${id}_report.xml)
    echo "${computername} ran ${appnameraw} for a total of ${total_sum} minutes" >> /tmp/Applicaiton_report_${startdate}_${enddate}.txt
rm /tmp/${id}_report.xml
rm /tmp/${id}_name.xml
done 

echo "report can be found in /tmp as Applicaiton_report_${startdate}_${enddate}.txt"
