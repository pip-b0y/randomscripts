#!/bin/bash
####Okta-Tester
#=_ &#95;
oktaurl='' ##ie tenant + domain okta/oktapreview
oktauser='' #Target User Name
oktapass='' #target Password
factor_id='' #see below
factor_id_2=''
#Note Factor ID you can get by running the following lines in this script and searching for the Factor ID releated to MFA Push with verify. see line 26
#json creation
cat <<EOF > /tmp/okta_data1.json
{
"options": {
"multiOptionalFactorEnroll": false,
"warnBeforePasswordExpired": false
},
"password": "${oktapass}",
"username": "${oktauser}"
}
EOF
###Start of Script
counter='0'
required_count='5' #Greater than 0
######CounterX######
while [ ${counter} -lt ${required_count} ]
do
	
token_raw=$(curl -X POST -H "Accept: application/json" -H "Content-Type: application/json" --data-binary @/tmp/okta_data1.json "https://${oktaurl}/api/v1/authn" )
token=$(echo ${token_raw} | awk -F '[:,{"}]' ' {print $6} ')
echo ${token_raw} > /tmp/okta_raw_token.json
###Comment out all below to review the json file okta_raw_token.json to get the MFA Factor ID to force use MFA Push to verify. use https://jsoneditoronline.org/ to help
encypted_token=$(echo $token | base64)
cat <<EOF > /tmp/okta_token.json
{
"stateToken": "${token}"
}
EOF
mfa_push1=$(curl -X POST -H "Accept: application/json" -H "Content-Type: application/json" --data-binary @/tmp/okta_token.json "https://$oktaurl/api/v1/authn/factors/$factor_id/verify" )
echo "####MFA_PUSH_1 Start####." >> /tmp/okta-call-log
echo "$counter"
echo "$counter first MFA push" >> /tmp/okta-call-log.log
echo "####" >> /tmp/okta-call-log.log
echo "$mfa_push1" >> /tmp/okta-call-log.log
echo "Validated data below" >> /tmp/okta-call-log
sleep 5
validate_data=$(curl -X POST -H "Accept: application/json" -H "Content-Type: application/json" --data-binary @/tmp/okta_token.json "https://$oktaurl/api/v1/authn/factors/$factor_id/verify")
echo "#### $counter Validated Data Below ####" >> /tmp/okta-call-log.log
echo "$validate_data" >> /tmp/okta-call-log.log
echo "#######END OF RUN $counter ###########" >> /tmp/okta-call-log.log
rm /tmp/okta_token.json
rm /tmp/okta_raw_token.json
counter=`expr $counter + 1`
done

rm /tmp/okta_data1.json
