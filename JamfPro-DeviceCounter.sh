#!/bin/bash
#Device Counter V1
# Jamf Pro credentials and URL
readonly username=''
readonly password=''
readonly url=''

# Temporary directory
readonly tmp_dir="/tmp"

# Function to handle errors
handle_error() {
	echo "Error occurred at line $1"
	exit 1
}
trap 'handle_error $LINENO' ERR

# Function to get bearer token
get_bearer_token() {
	local response=$(curl -s -u "$username":"$password" "$url"/api/v1/auth/token -X POST)
	bearerToken=$(echo "$response" | plutil -extract token raw -)
	local tokenExpiration=$(echo "$response" | plutil -extract expires raw - | awk -F . '{print $1}')
	tokenExpirationEpoch=$(date -j -f "%Y-%m-%dT%T" "$tokenExpiration" +"%s")
}

# Function to check token expiration
check_token_expiration() {
	local nowEpochUTC=$(date -j -f "%Y-%m-%dT%T" "$(date -u +"%Y-%m-%dT%T")" +"%s")
	if (( tokenExpirationEpoch > nowEpochUTC )); then
		echo "Token valid until the following epoch time: $tokenExpirationEpoch"
	else
		echo "No valid token available, getting new token"
		get_bearer_token
	fi
}

# Function to fetch data and generate report
fetch_data_and_generate_report() {
	local resource_type="$1"
	local resource_list="$tmp_dir/${resource_type}list.xml"
	local report_file="$tmp_dir/final_${resource_type}_count_report.txt"
	
	check_token_expiration
	curl -s -H "Authorization: Bearer ${bearerToken}" "$url/JSSResource/$resource_type" | xmllint --format - > "$resource_list"
	local resource_id_raw=$(xpath -e "//${resource_type%?}/id" "$resource_list" 2>&1 | awk -F'<id>|</id>' '{print $2}')
	
	for resource_id in $resource_id_raw; do
		local resource_site_name=$(curl -s -H "Authorization: Bearer ${bearerToken}" "$url/JSSResource/${resource_type%?}/id/${resource_id}" | xmllint --format - | xpath -e "//${resource_type%?}/general/site" | awk -F'<name>|</name>' '{print $2}')
		local site_file="$tmp_dir/${resource_site_name}.${resource_type%?}d"
		
		if [[ ! -e $site_file ]]; then
			echo "Object not created for $resource_site_name"
			touch "$site_file"
		fi
		echo "$resource_id" >> "$site_file"
	done
	
	# Generate report
	echo "${resource_type%?}s:" > "$report_file"
	for file in "$tmp_dir"/*."${resource_type%?}d"; do
		local resource_name=$(basename "$file" ".${resource_type%?}d")
		local resource_count=$(wc -l < "$file")
		echo "$resource_name: $resource_count" >> "$report_file"
	done
}

# Main script
fetch_data_and_generate_report "computer"
fetch_data_and_generate_report "mobiledevice"
cat "$tmp_dir/final_device_count_report.txt"
