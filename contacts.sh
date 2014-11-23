#!/bin/bash
#
# Matthew Beardmore and Matthew Bowen
# Introduction to Scripting: Project 2
# Google Contacts API script 
# 11/23/2014
#

#
# Constants
#
API_CLIENT_ID="1029985346719-4ecd3h4k1s8l2v3i7hn8okobu5ct0jiq.apps.googleusercontent.com"
API_CLIENT_SECRET="z7s_zY2MjT6AC7IruKO-BVCL"
API_SCOPE="https://www.google.com/m8/feeds"

# Attempts to load a cached access token from the .contacts_access_token file.
#
# Output:
#    ACCESS_TOKEN set to the cached access token if it is valid, an empty 
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

# Extracts the value of a JSON string given the specified key.
#
# Parameters:
#     1: JSON data
#     2: JSON key
#
# Output: JSON value on stdout, or an empty string if the key wasn't found.
extract_json_string()
{
    echo "$1" | grep "$2" | awk "{ match(\$0, /\"$2\"\s*:\s*\"([^\"]*?)/, arr); print arr[1]; }"
}

# Extracts the value of a JSON string given the specified key.
#
# Parameters:
#     1: JSON data
#     2: JSON key
#
# Output: JSON value on stdout, or an empty string if the key wasn't found.
extract_json_number()
{
    echo "$1" | grep "$2" | awk "{ match(\$0, /\"$2\"\s*:\s*([0-9]+)/, arr); print arr[1]; }"
}

# Authenticates the user with Google's servers.
#
# We use OAuth 2.0 to authenticate the user. First, we ask Google for a device
# code and a verification URL. We then show the user both of these and ask them
# to navigate their browser to the verification URL and enter the access code
# given to them. Once that is done, Google gives us an access token that we
# use to interface with the user's contacts.
#
# Output: ACCESS_TOKEN set to an access token used to interface with Google's
# API.
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

	local output=`wget -qO- --post-data "client_id=$API_CLIENT_ID&scope=$API_SCOPE" https://accounts.google.com/o/oauth2/device/code`

	# Get the various bits of info we need
	local device_code=`extract_json_string "$output" "device_code"`
	local user_code=`extract_json_string "$output" "user_code"`
	local veri_url=`extract_json_string "$output" "verification_url"`
    local interval=`extract_json_number "$output" "interval"`

	# Tell the user where to go to be able to verify the script and the code they need
	echo "Please navigate to the following URL in your browser:"
    echo ""
    echo "    $veri_url"
    echo ""
    echo "When prompted, enter the following code:"
    echo ""
    echo "    $user_code"
    echo ""
    echo "You can continue once you authorize this script."

    echo -n "Waiting for user authorization..."
    
	# We now wait for the user to authorize us to access their account
	while true
	do
        # Wait for a certain number of seconds between each authorization check
        sleep $interval
        
		# Ask the server if we have been authorized yet
		output=`wget -qO- --post-data "client_id=$API_CLIENT_ID&client_secret=$API_CLIENT_SECRET&code=$device_code&grant_type=http://oauth.net/grant_type/device/1.0" https://accounts.google.com/o/oauth2/token`

		# See whether there was an error in the response
		local error=`extract_json_string "$output" "error"`

		if [ -z "$error" ]
		then
			# There wasn't an error, so we've been authorized!
            echo " Authorized!"
            
			ACCESS_TOKEN=`extract_json_string "$output" "access_token"`

            # Save the access token for future program runs
            echo -n "$ACCESS_TOKEN" > .contacts_access_token
			break
		fi

		if [ $error == "authorization_pending" ]
		then
			# Haven't been authorized yet
			echo -n "."
		fi
	done
}

# Prints a table of contacts received from a Google API call in a formatted
# table. Also parses that data into an array for further consumption.
#
# Parameters:
#     1: A string containing contacts data from a Google API call.
#
# Output: OUTPUT set to an array containing sets of 4 pieces of information:
#     Index+0: Contact's name
#     Index+1: Contact's phone
#     Index+2: Contact's Email
#     Index+3: The URL used for editing and deleting the contact.
display_contact_info()
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
	done < <(echo "$1" | awk -f parse_contacts_list.awk | sort)
    
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

# Displays a list of all contacts on the user's account.
#
# Output: See `display_contact_info`.
display_all_contacts()
{
	#Fetch the contacts file from Google with our access token
	local response=`wget -qO- --header="Authorization: Bearer $ACCESS_TOKEN" https://www.google.com/m8/feeds/contacts/default/full`
    
	#Have this method display the info in a table
	display_contact_info "$response"
}

# Prompts the user for a query to the contact database and displays the
# results for that query.
#
# Output: See `display_contact_info`.
search_for_contacts()
{
    local query=""
    read -p "Query: " query
    
	local response=`wget -qO- --header="Authorization: Bearer $ACCESS_TOKEN" https://www.google.com/m8/feeds/contacts/default/full?q=$query\&v=3.0\&`

    echo ""
    
    # Check to see if any results were found
    local num_results=`echo "$response" | grep openSearch:totalResults | awk 'BEGIN { FS="[<>]" } { print $3 }'`
    
    if [ ! -z "$num_results" -a "$num_results" == "0" ]
    then
        echo "No results found!"
    else
        display_contact_info "$response"
    fi
}

# Prompts the user for information for creating a new contact, and creates it.
#
# Output: See `display_contact_info`.
add_contact()
{
    local new_name=""
    local new_phone=""
    local new_email=""
    
    read -p "Name: " new_name
    read -p "Phone: " new_phone
    read -p "Email: " new_email

    local template=`cat new_contact_template.xml`
    
    if [ -z "$new_name" -a -z "$new_phone" -a -z "$new_email" ]
    then
        echo "Contact not added."
        return
    fi
    
    if [ ! -z "$new_name" ]
    then
        template=`echo "$template" | sed s/{{NAME}}/"$new_name"/`
    else
        template=`echo "$template" | sed /{{NAME}}/d`
    fi
    
    if [ ! -z "$new_phone" ]
    then
        template=`echo "$template" | sed s/{{PHONE}}/"$new_phone"/`
    else
        template=`echo "$template" | sed /{{PHONE}}/d`
    fi
    
    if [ ! -z "$new_email" ]
    then
        template=`echo "$template" | sed s/{{EMAIL}}/"$new_email"/`
    else
        template=`echo "$template" | sed /{{EMAIL}}/d`
    fi
    
    echo "Adding contact..."
    
    # Add the new contact
    local result=`wget -qO- --header="Authorization: Bearer $ACCESS_TOKEN" --header="Content-Type: application/atom+xml" --post-data "$template" https://www.google.com/m8/feeds/contacts/default/full`
    
    if [ $? -ne 0 ]
    then
        # Contact was not added successfully
        echo "An error occurred while adding the new contact!"
    else
        echo "Contact added successfully!"
        echo ""
        
        display_contact_info "$result"
    fi
}

# Prompts the user to delete a contact from a list of all of their contacts.
#
# Output: See `display_contact_info`.
delete_contact()
{
    # Show the user a list of contacts they can delete
    display_all_contacts
    
    echo "Select a contact to delete."
    
    local selection=-1
    while [ $selection -lt 1 -o $selection -gt $((${#OUTPUT[@]}/4)) ]
    do
        read -p "Selection: " selection
        
        # Make sure the selection is an integer
        echo $selection | egrep -q "[0-9]+"
        if [ $? -eq 1 ]
        then
            # Not an integer, set it to an invalid value and try again
            selection=-1
        fi
    done
    
    selection=$(($selection-1)) # OUTPUT array is zero-based
    echo "Deleting contact for \"${OUTPUT[$selection*4]}.\""
    read -p "Are you sure? (y/N) " confirm
    
    if [ $confirm != "y" -a $confirm != "Y" ]
    then
        echo "Contact not deleted."
        return
    fi
    
    echo "Deleting contact..."
    local result=`wget -qO- --header="Authorization: Bearer $ACCESS_TOKEN" --method=DELETE ${OUTPUT[$(($selection*4+3))]}`

    if [ $? -ne 0 ]
    then
        # Server didn't like our request
        echo "Contact was NOT deleted successfully!"
    else
        echo "Contact was deleted successfully!"
    fi
}

# Displays a menu of actions the user can choose from.
#
# Output: SELECTION set to 0-4, indicating the action the user selected.
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

#
# Script start
#

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
