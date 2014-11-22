#!/bin/bash
# Matthew Beardmore and Matthew Bowen
# Introduction to Scripting: Project 2
# Google Contacts API script 
# 11/11/2014

# Constants
API_CLIENT_ID="1029985346719-4ecd3h4k1s8l2v3i7hn8okobu5ct0jiq.apps.googleusercontent.com"
API_CLIENT_SECRET="z7s_zY2MjT6AC7IruKO-BVCL"
API_SCOPE="https://www.google.com/m8/feeds"

# Output:
#    ACCESS_TOKEN set to the cached access token if it is valid; an empty 
#    string otherwise.
get_cached_access_token()
{
    ACCESS_TOKEN=""
    
    # Check to see if there's already a valid access token cached from a previous run
    if [ ! -f .contacts_access_token ]
    then
        return
    fi
    
    # Load the cached token
    local cached_token=`cat .contacts_access_token`
    
    # Ask Google if this is a valid access token
    local output=`wget -qO- https://www.googleapis.com/oauth2/v1/tokeninfo?access_token=$cached_token`

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
    ACCESS_TOKEN=$cached_token
}

# $1: String
# $2: JSON key
#
# Output: JSON value on stdout
extract_json_string()
{
    echo "$1" | grep "$2" | awk "{ match(\$0, /\"$2\"\s*:\s*\"([^\"]*?)/, arr); print arr[1]; }"
}

# $1: String
# $2: JSON key
#
# Output: JSON value on stdout
extract_json_number()
{
    echo "$1" | grep "$2" | awk "{ match(\$0, /\"$2\"\s*:\s*([0-9]+)/, arr); print arr[1]; }"
}

# Logs the user in and gains access to the user's contacts
login_auth()
{
    get_cached_access_token

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
	local output=`wget -qO- --post-data "client_id=$API_CLIENT_ID&scope=$API_SCOPE" https://accounts.google.com/o/oauth2/device/code`

	# Get the various bits of info we need
	local device_code=`extract_json_string "$output" "device_code"`
	local user_code=`extract_json_string "$output" "user_code"`
	local veri_url=`extract_json_string "$output" "verification_url"`
    local interval=`extract_json_number "$output" "interval"`

	# Tell the user where to go to be able to verify the script and the code they need
	echo "Please go to the following URL:"
    echo ""
    echo "    $veri_url"
    echo ""
    echo "When prompted, enter the following code:"
    echo ""
    echo "    $user_code"
    echo ""
    echo "You can continue once you authorize this script."

    echo -n "Waiting for user authorization..."
    
	# The script now has to wait for the user to authorize the script to access their account
	while true
	do
        # Wait for a certain number of seconds between each authorization check
        sleep $interval
        
		#Ask the server if we have been authorized yet...
		output=`wget -qO- --post-data "client_id=$API_CLIENT_ID&client_secret=$API_CLIENT_SECRET&code=$device_code&grant_type=http://oauth.net/grant_type/device/1.0" https://accounts.google.com/o/oauth2/token`

		#See whether there is a line in the JSON that contains with "error" :
		local error=`extract_json_string "$output" "error"`

		if [ -z "$error" ]
		then
			#There wasn't an error, so we've been authorized!
			#Get the access_token that we'll need to send any further requests to the contacts API
            echo " Authorized!"
            
			ACCESS_TOKEN=`extract_json_string "$output" "access_token"`

            # Save the access token for future program runs
            echo -n "$ACCESS_TOKEN" > .contacts_access_token
			break
		fi

		if [ $error == "authorization_pending" ]
		then
			#This is the error we're looking for if the user hasn't authorized us yet, still waiting...
			echo -n "."
		fi
	done
}

# Displays contact info stored in $CONTACT_INFO in a nicely formatted table
display_contact_info()
{
    parse_contact_info
    
    # Print out the table header
	printf "  # | %-25s | %-15s | %-30s\n" "Contact Name" "Phone Number" "Email"
    echo "----+---------------------------+-----------------+-----------------"
    
    # Print out all the contact info we have for them
    for i in `seq 0 $(((${#OUTPUT[@]}-1)/4))`
    do
        local name=${OUTPUT[$i*4]}
        local phone=${OUTPUT[$i*4+1]}
        local email=${OUTPUT[$i*4+2]}
        
        printf " %2d | %-25s | %-15s | %-30s\n" "$(($i+1))" "$name" "$phone" "$email"
    done
}

parse_contact_info()
{
    # Clear any output from previous runs
    unset OUTPUT
    
    local row_num=0
	while read -r LINE; do
        OUTPUT[$(($row_num*4))]=`echo "$LINE" | cut -f 1`
        OUTPUT[$(($row_num*4+1))]=`echo "$LINE" | cut -f 2`
        OUTPUT[$(($row_num*4+2))]=`echo "$LINE" | cut -f 3`
        OUTPUT[$(($row_num*4+3))]=`echo "$LINE" | cut -f 4`

        row_num=$(($row_num+1))
	done < <(echo "$CONTACTS_FULL" | awk -f parse_contacts_list.awk)
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
    local query=""
    read -p "Query: " query
    
	CONTACTS_FULL=`wget -qO- --header="Authorization: Bearer $ACCESS_TOKEN" https://www.google.com/m8/feeds/contacts/default/full?q=$query\&v=3.0`

    echo ""
    
    # Check to see if any results were found
    local num_results=`echo "$CONTACTS_FULL" | grep openSearch:totalResults | awk 'BEGIN { FS="[<>]" } { print $3 }'`
    
    if [ ! -z "$num_results" -a "$num_results" == "0" ]
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
