#!/bin/bash
#Matthew Beardmore and Matthew Bowen
#Introduction to Scripting: Project 2
#Google Contacts API script 
#11/11/2014

# Constants
API_CLIENT_ID="1029985346719-4ecd3h4k1s8l2v3i7hn8okobu5ct0jiq.apps.googleusercontent.com"
API_CLIENT_SECRET="z7s_zY2MjT6AC7IruKO-BVCL"
API_SCOPE="https://www.google.com/m8/feeds"

# Output:
#    ACCESS_TOKEN set to the cached access token if it is valid; an empty 
#    string otherwise.
verify_cached_access_token()
{
    ACCESS_TOKEN=""
    
    # Check to see if there's already a valid access token cached from a previous run
    if [ ! -f .contacts_access_token ]
    then
        return
    fi
    
    # Load the cached token
    CACHED_TOKEN=`cat .contacts_access_token`
    
    # Ask Google if this is a valid access token
    output=`wget -qO- https://www.googleapis.com/oauth2/v1/tokeninfo?access_token=$CACHED_TOKEN`

    if [ $? -ne 0 ]
    then
        # Token is not valid
        return
    fi
    
    # Verify that the access token is valid for our program
    echo "$output" | grep -q "$API_CLIENT_ID"
    
    if [ $? -ne 0 ]
    then
        # Access token not issued to our client ID
        return
    fi
    
    # Verify that the scope is correct
    echo "$output" | grep -q "$API_SCOPE"
    
    if [ $? -ne 0 ]
    then
        # The scope we need isn't assigned to the token
        return
    fi
    
    # Token works, use it
    ACCESS_TOKEN=$CACHED_TOKEN
}

#Logs the user in and gains access to the user's contacts
login_auth()
{
    verify_cached_access_token

    if [ ! -z "$ACCESS_TOKEN" ]
    then
        # Use the cached access token
        return
    fi

    # Remove any cached access token, since it's not valid
    rm .contacts_access_token 2> /dev/null

	#Get information for OAuth from the Google OAuth 2.0 server
	#Contains device_code, user_code, verification_url, and interval
	#verfication_url and user_code must be given to the user so that they can authorize our script
	#We use device_code and interval to get an access_token once the user gives our script access on Google's websitee
	output=`wget -qO- --post-data "client_id=$API_CLIENT_ID&scope=$API_SCOPE" https://accounts.google.com/o/oauth2/device/code`

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
		output=`wget -qO- --post-data "client_id=$API_CLIENT_ID&client_secret=$API_CLIENT_SECRET&code=$DEVICE_CODE&grant_type=http://oauth.net/grant_type/device/1.0" https://accounts.google.com/o/oauth2/token`

		#See whether there is a line in the JSON that contains with "error" :
		ERROR=`echo "$output" | grep '"error" : '`

		if [ -z "$ERROR" ]
		then
			#There wasn't an error, so we've been authorized!
			#Get the access_token that we'll need to send any further requests to the contacts API
			echo "User has authorized this project!"
			ACCESS_TOKEN=`echo "$output" | grep '"access_token" : '`
			ACCESS_TOKEN=`echo $ACCESS_TOKEN | awk 'BEGIN{FS="\""};{print $4}'`

            # Save the access token for future program runs
            echo -n "$ACCESS_TOKEN" > .contacts_access_token
            
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

# Displays contact info stored in $CONTACT_INFO in a nicely formatted table
display_contact_info()
{
    parse_contact_info
    
    #Print out the top information about the table
	printf "  # | %-25s | %-15s | %-30s\n" "Contact Name" "Phone Number" "Email"
    echo "--------------------------------+-----------------+-----------------"
    
    #Print out all the contact info we have for them
    for i in `seq 0 $(((${#OUTPUT[@]}-1)/4))`
    do
        CONTACT_NAME=${OUTPUT[$i*4]}
        CONTACT_PHONE_NUM=${OUTPUT[$i*4+1]}
        CONTACT_EMAIL=${OUTPUT[$i*4+2]}
        
        printf " %2d | %-25s | %-15s | %-30s\n" "$(($i+1))" "$CONTACT_NAME" "$CONTACT_PHONE_NUM" "$CONTACT_EMAIL"
    done
}

parse_contact_info()
{
    # Filter the response only to items we care about
    CONTACTS_INFO=`echo "$CONTACTS_FULL" | awk '/<entry/ { show=1 } show && (/<title/ || /<gd:phoneNumber/ || /<gd:email/ || /<link.*rel=\"edit\"/) { print }; /<\/entry>/ { show=0; print }'`
    
    unset OUTPUT
    
    ROW_NUMBER=0
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
        elif [ "${LINE:0:5}" == "<link" ]
        then
            CONTACT_EDIT_LINK=`echo $LINE | awk '{ match($0, /href=\"(.*)\"/, arr); print arr[1]; }'`
		elif [ "$LINE" == "</entry>" ]
		then
			#If we have a name for this contact, print it out with any info we have for it
			if [ ! -z "$CONTACT_NAME" ]
			then
                OUTPUT[$(($ROW_NUMBER*4))]="$CONTACT_NAME"
                OUTPUT[$(($ROW_NUMBER*4+1))]="$CONTACT_PHONE_NUM"
                OUTPUT[$(($ROW_NUMBER*4+2))]="$CONTACT_EMAIL"
                OUTPUT[$(($ROW_NUMBER*4+3))]="$CONTACT_EDIT_LINK"
                
                ROW_NUMBER=$(($ROW_NUMBER+1))
			fi
            
			#Clear out the info for this entry
			CONTACT_NAME=""
			CONTACT_PHONE_NUM=""
			CONTACT_EMAIL=""
            CONTACT_EDIT_LINK=""
		fi
	done <<< "$CONTACTS_INFO" 
}

#Displays all contacts that are available for the Google account we have access to
#Assumes we have logged in and have a correct ACCESS_TOKEN
display_all_contacts()
{
	#Fetch the contacts file from Google with our access token
	CONTACTS_FULL=`wget -qO- --header="Authorization: Bearer $ACCESS_TOKEN" https://www.google.com/m8/feeds/contacts/default/full`
    
	#Have this method display the info in a table
	display_contact_info
}

search_for_contacts()
{
    read -p "Query: " QUERY
    
	CONTACTS_FULL=`wget -qO- --header="Authorization: Bearer $ACCESS_TOKEN" https://www.google.com/m8/feeds/contacts/default/full?q=$1\&v=3.0`

    echo ""
    
    # Check to see if any results were found
    NUM_RESULTS=`echo "$CONTACTS_FULL" | grep openSearch:totalResults | awk 'BEGIN { FS="[<>]" } { print $3 }'`
    
    if [ ! -z "$NUM_RESULTS" -a "$NUM_RESULTS" == "0" ]
    then
        echo "No results found!"
    else
        display_contact_info
    fi
}

add_contact()
{
    read -p "Name: " NEW_CONTACT_NAME
    read -p "Phone: " NEW_CONTACT_PHONE
    read -p "Email: " NEW_CONTACT_EMAIL

    TEMPLATE=`cat new_contact_template.xml`
    
    if [ -z "$NEW_CONTACT_NAME" -a -z "$NEW_CONTACT_EMAIL" -a -z "$NEW_CONTACT_PHONE" ]
    then
        echo "Contact not added."
        return
    fi
    
    if [ ! -z "$NEW_CONTACT_NAME" ]
    then
        TEMPLATE=`echo "$TEMPLATE" | sed s/{{NAME}}/"$NEW_CONTACT_NAME"/`
    else
        TEMPLATE=`echo "$TEMPLATE" | sed /{{NAME}}/d`
    fi
    
    if [ ! -z "$NEW_CONTACT_EMAIL" ]
    then
        TEMPLATE=`echo "$TEMPLATE" | sed s/{{EMAIL}}/"$NEW_CONTACT_EMAIL"/`
    else
        TEMPLATE=`echo "$TEMPLATE" | sed /{{EMAIL}}/d`
    fi
    
    if [ ! -z "$NEW_CONTACT_PHONE" ]
    then
        TEMPLATE=`echo "$TEMPLATE" | sed s/{{PHONE}}/"$NEW_CONTACT_PHONE"/`
    else
        TEMPLATE=`echo "$TEMPLATE" | sed /{{PHONE}}/d`
    fi
    
    echo ""
    echo "Adding contact..."
    
    # Add the new contact
    RESULT=`wget -qO- --header="Authorization: Bearer $ACCESS_TOKEN" --header="Content-Type: application/atom+xml" --post-data "$TEMPLATE" https://www.google.com/m8/feeds/contacts/default/full`
    
    if [ $? -ne 0 ]
    then
        # Contact was not added successfully
        echo "An error occurred while adding the new contact!"
    else
        echo "Contact added successfully!"
        echo ""
        
        CONTACTS_FULL=$RESULT
        display_contact_info
    fi
}

delete_contact()
{
    display_all_contacts
    
    echo "Select a contact to delete."
    
    SELECTION=-1
    while [ $SELECTION -lt 0 -o $SELECTION -gt ${#OUTPUT[@]} ]
    do
        read -p "Selection: " SELECTION
        
        # Make sure the selection is an integer
        echo $SELECTION | egrep -q "[0-9]+"
        if [ $? -eq 1 ]
        then
            # Not an integer, set it to an invalid value and try again
            SELECTION=-1
        fi
    done
    
    SELECTION=$(($SELECTION-1)) # OUTPUT array is zero-based
    echo "Deleting contact for ${OUTPUT[$SELECTION*4]}."
    read -p "Are you sure? (y/N) " SELECTION
    
    if [ $SELECTION != "y" -a $SELECTION != "Y" ]
    then
        echo "Contact not deleted."
        return
    fi
    
    echo "Deleting contact..."
    
    local result=`wget -qO- --header="Authorization: Bearer $ACCESS_TOKEN" --method=DELETE ${OUTPUT[$((SELECTION*4+3))]}`

    if [ $? -ne 0 ]
    then
        # Token is not valid
        echo "Contact was NOT deleted successfully!"
    else
        echo "Contact was deleted successfully!"
    fi
}

# Return value in $SELECTION
display_menu()
{
    echo "Please select a menu option:"
    echo ""
    echo "1: List contacts"
    echo "2: Search contacts"
    echo "3: Add contact"
    echo "4: Delete contact"
    echo "0: Quit"
    echo ""
    
    SELECTION=-1
    while [ $SELECTION -lt 0 -o $SELECTION -gt 4 ]
    do
        read -p "Option: " SELECTION
        
        # Make sure the selection is an integer
        echo $SELECTION | egrep -q "[0-9]+"
        if [ $? -eq 1 ]
        then
            # Not an integer, set it to an invalid value and try again
            SELECTION=-1
        fi
    done
}

# Login
login_auth

while [ 1 -eq 1 ]
do
    display_menu

    case $SELECTION in
        1)
            display_all_contacts
            ;;
        2)
            search_for_contacts
            ;;
        3)
            add_contact
            ;;
        4)
            delete_contact
            ;;
        0)
            echo "Quitting..."
            exit 0
            ;;
    esac
    
    echo ""
done
