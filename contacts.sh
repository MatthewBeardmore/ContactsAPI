#!/bin/bash
#Matthew Beardmore and Matthew Bowen
#Introduction to Scripting: Project 2
#Google Contacts API script 
#11/11/2014

#Logs the user in and gains access to the user's contacts
login_auth()
{
	#Get information for OAuth from the Google OAuth 2.0 server
	#Contains device_code, user_code, verification_url, and interval
	#verfication_url and user_code must be given to the user so that they can authorize our script
	#We use device_code and interval to get an access_token once the user gives our script access on Google's websitee
	output=`wget -qO- --post-data 'client_id=1029985346719-4ecd3h4k1s8l2v3i7hn8okobu5ct0jiq.apps.googleusercontent.com&scope=https://www.google.com/m8/feeds' https://accounts.google.com/o/oauth2/device/code`

	#Get the inforation from the JSON by greping for the line with the information we want and
	# using awk to get the information we need
	DEVICE_CODE=`echo "$output" | grep '"device_code" : '`
	DEVICE_CODE=`echo $DEVICE_CODE | awk 'BEGIN{FS="\""};{print $4}'`

	USER_CODE=`echo "$output" | grep '"user_code" : '`
	USER_CODE=`echo $USER_CODE | awk 'BEGIN{FS="\""};{print $4}'`

	VERI_URL=`echo "$output" | grep '"verification_url" : '`
	VERI_URL=`echo $VERI_URL | awk 'BEGIN{FS="\""};{print $4}'`

	INTERVAL=`echo "$output" | grep 'interval'`
	INTERVAL=`echo $INTERVAL | awk 'BEGIN{FS=" "};{print $3}'`

	#Tell the user where to go to be able to verify the script and the code they need
	echo "Go to the URL '$VERI_URL' in your browser and enter the code to continue: $USER_CODE"


	#The script now has to wait for the user to authorize the script to access their account
	while true
	do
		#Ask the server if we have been authorized yet...
		output=`wget -qO- --post-data "client_id=1029985346719-4ecd3h4k1s8l2v3i7hn8okobu5ct0jiq.apps.googleusercontent.com&client_secret=z7s_zY2MjT6AC7IruKO-BVCL&code=$DEVICE_CODE&grant_type=http://oauth.net/grant_type/device/1.0" https://accounts.google.com/o/oauth2/token`

		#See whether there is a line in the JSON that contains with "error" :
		ERROR=`echo "$output" | grep '"error" : '`

		if [ -z "$ERROR" ]
		then
			#There wasn't an error, so we've been authorized!
			#Get the access_token that we'll need to send any further requests to the contacts API
			echo "User has authorized this project!"
			ACCESS_TOKEN=`echo "$output" | grep '"access_token" : '`
			ACCESS_TOKEN=`echo $ACCESS_TOKEN | awk 'BEGIN{FS="\""};{print $4}'`

			break
		fi
		#There was an error... keep waiting with the specified time sent by Google
		ERROR=`echo $ERROR | awk 'BEGIN{FS="\""};{print $4}'`

		if [ $ERROR == "authorization_pending" ]
		then
			#This is the error we're looking for if the user hasn't authorized us yet, still waiting...
			echo "Waiting for user authorization..."
		fi
		#Wait for the specified time before asking Google if we have been authorizedd
		#If we don't do this, the servers will respond that we are sending too many requests
		sleep $INTERVAL
	done
}

#Displays contact info stored in $CONTACT_INFO in a nicely formatted table
display_contact_info()
{
	#Print out the top information about the table
	printf "%-25s %-15s %-30s\n\n" "Contact Name" "Phone Number" "Email"
	while read -r LINE; do
		if [ "${LINE:0:6}" == "<title" ]
		then
			#Get the contact name from the value portion of the XML
			CONTACT_NAME=`echo $LINE | awk 'BEGIN { FS="[<>]" } { print $3 }'`
		elif [ "${LINE:0:15}" == "<gd:phoneNumber" ]
		then
			#Get the phone number from the value portion of the XML
			CONTACT_PHONE_NUM=`echo $LINE | awk 'BEGIN { FS="[<>]" } { print $3 }'`
			#Clean up the phone number a bit by getting rid of -, +, (), and spaces
			CONTACT_PHONE_NUM=`echo "$CONTACT_PHONE_NUM" | tr -d '-' | tr -d ' ' | sed 's/[\+\(\)]//g'`
			#Now let's normalize the number so that it looks pretty by adding a 1 to the beginning if it's not there
			if [ "${#CONTACT_PHONE_NUM}" == "10" ]
			then
				CONTACT_PHONE_NUM="1$CONTACT_PHONE_NUM"
			fi

			#Clean up further by adding - at the correct positions
			CONTACT_PHONE_NUM="${CONTACT_PHONE_NUM:0:1}-${CONTACT_PHONE_NUM:1:3}-${CONTACT_PHONE_NUM:4:3}-${CONTACT_PHONE_NUM:7:11}"
		elif [ "${LINE:0:9}" == "<gd:email" ]
		then
			#Get the field that starts with "address="
			CONTACT_EMAIL=`echo $LINE | awk '{ for(i=1;i<=NF;i++) { if ($i ~ /address=/) {print $i; } } }'`
			#remove the address="email@test.com" and get only the email address itself
			CONTACT_EMAIL=`echo $CONTACT_EMAIL | cut -d '"' -f2 | tr -d '"'`
		elif [ "$LINE" == "</entry>" ]
		then
			#If we have a name for this contact, print it out with any info we have for it
			if [ ! -z "$CONTACT_NAME" ]
			then
				#Print out all the contact info we have for them
				printf "%-25s %-15s %-30s\n" "$CONTACT_NAME" "$CONTACT_PHONE_NUM" "$CONTACT_EMAIL"
			fi
			
			#Clear out the info for this entry
			CONTACT_NAME=""
			CONTACT_PHONE_NUM=""
			CONTACT_EMAIL=""
		fi
	done <<< "$CONTACTS_INFO" 
}

#Displays all contacts that are available for the Google account we have access to
#Assumes we have logged in and have a correct ACCESS_TOKEN
display_all_contacts()
{
	#Fetch the contacts file from Google with our access token
	CONTACTS_FULL=`wget -qO- --header="Authorization: Bearer $ACCESS_TOKEN" https://www.google.com/m8/feeds/contacts/default/full`

	#Get rid of anything that is not the contact name, the phone number, the email, and the end of entry tag
	CONTACTS_INFO=`echo "$CONTACTS_FULL" | awk '/<entry>/ { show=1 } show && (/<title/ || /<gd:phoneNumber/ || /gd:email/) { print }; /<\/entry>/ { show=0; print }'`

	#Have this method display the info in a table
	display_contact_info
}


#First, log in if possible
login_auth

#Now display all contacts available
display_all_contacts




