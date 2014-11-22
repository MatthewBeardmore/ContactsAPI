#!/usr/bin/awk -f

/^\s*<entry/ {
    inside_entry = 1
}
        
inside_entry && /^\s*<title/ {
    match($0, /<title.*>(.*)<\/title>/, arr);
    contact_name = arr[1];
}

inside_entry && /^\s*<gd:email/ {
    match($0, /<gd:email.*address=\"([^"]*)/, arr);
    contact_email = arr[1];
}

inside_entry && /^\s*<gd:phoneNumber/ {
    match($0, /<gd:phoneNumber.*>(.*)<\/gd:phoneNumber>/, arr);
    contact_phone = arr[1];
}

inside_entry && /^\s*<link/ {
    match($0, /<link.*rel=\"edit\".*href=\"([^"]*)/, arr);
    contact_edit_link = arr[1];
}

/^\s*<\/entry/ {
    if (inside_entry == 1) {
        if (contact_name != "") {
            printf "%s\t%s\t%s\t%s\n", contact_name, contact_phone,
                contact_email, contact_edit_link;
        }
        
        inside_entry = 0;
        contact_name = contact_email = contact_phone = contact_edit_link = "";
    }
}
