#!/bin/bash
# Enrolment script used at various companies
# Author: James Smith - james@smithjw.me
# Version 3.6.0

/usr/bin/defaults write /Library/Management/management_info.plist enrol_initial_policy_start "$(date +%s)"

working_dir="/private/var/tmp"
identifier_prefix="com.github.smithjw"
enrolment_base_string="${identifier_prefix}.mac.swiftEnrolment"
enrolment_script="${working_dir}/${enrolment_base_string}.sh"
enrolment_launchdaemon="/Library/LaunchDaemons/${enrolment_base_string}.plist"
post_enrolment_launchdaemon="/Library/LaunchDaemons/${enrolment_base_string}_post.plist"
jamf_binary="/usr/local/jamf/bin/jamf"
fde_setup_binary="/usr/bin/fdesetup"
self_service_branding_icon_name="brandingimage.png"
self_service_branding_icon_location="/Library/Management/images"
self_service_branding_icon_url="https://COMPANY.jamfcloud.com/api/v1/branding-images/download/9"
dialog_app="/usr/local/bin/dialog"
dialog_command_file="${working_dir}/dialog.log"
dialog_icon="/Library/Management/images/company_logo.png"
dialog_title="COMPANY Device Enrolment"
dialog_title_complete="You're all done!"
dialog_message="We're just installing up a few apps and configuring a few System Settings before you get started. \n\n This process should take about 10 minutes to complete. \n\n "
dialog_message_testing="This is usually where swiftDialog would quit, and the user logged out. \n\nHowever, testing_mode is enabled and FileVault deferred status is on."
dialog_message_final="We've finished installing up all the default apps required to get you started. \n\nIn a few moments you'll see a new dialog that will walk you through the remaining setup steps."
dialog_status_initial="Initial Configuration Starting..."
dialog_status_complete="Configuration Complete!"

log_folder="/private/var/log"
log_name="management.log"

dialog_cmd=(
    -p
    --title "$dialog_title"
    --iconsize 200
    --width 70%
    --height 70%
    --position centre
    --button1disabled
    --progress 30
    --progresstext "$dialog_status_initial"
    --blurscreen
)

#########################################################################################
# Policy Array to determine what's installed
#########################################################################################

policy_array=('
{
    "steps": [
        {
            "listitem": "Installing management tools...",
            "icon": "SF=terminal,colour=auto,weight=medium",
            "trigger_list": [
                {
                    "trigger": "install-Python",
                    "path": "/usr/local/bin/managed_python3"
                },
                {
                    "trigger": "install-Nudge",
                    "path": "/Applications/Utilities/Nudge.app/Contents/Info.plist"
                },
                {
                    "trigger": "install-Outset",
                    "path": "/usr/local/outset/outset"
                }
            ]
        },
        {
            "listitem": "Configuring Single Sign-On...",
            "icon": "SF=person.crop.square.filled.and.at.rectangle,colour=auto,weight=medium",
            "trigger_list": [
                {
                    "trigger": "install-nomad",
                    "path": "/Applications/NoMAD.app/Contents/Info.plist"
                },
                {
                    "trigger": "install-Microsoft_Company_Portal",
                    "path": "/Applications/Company Portal.app/Contents/Info.plist"
                }
            ]
        },
        {
            "listitem": "Configuring network settings...",
            "icon": "SF=network.badge.shield.half.filled,colour=auto,weight=medium",
            "trigger_list": [
                {
                    "trigger": "configure-networkprefsaccess",
                    "path": ""
                },
                {
                    "trigger": "configure-proxy",
                    "path": ""
                }
            ]
        },
        {
            "listitem": "Installing collaboration tools...",
            "icon": "SF=bubble.left.and.bubble.right,colour=auto,weight=medium",
            "trigger_list": [
                {
                    "trigger": "install-Slack",
                    "path": "/Applications/Slack.app/Contents/Info.plist"
                },
                {
                    "trigger": "install-Microsoft_Teams",
                    "path": "/Applications/Microsoft Teams.app/Contents/Info.plist"
                }
            ]
        },
        {
            "listitem": "Installing browsers...",
            "icon": "SF=safari,colour=auto,weight=medium",
            "trigger_list": [
                {
                    "trigger": "install-Microsoft_Edge",
                    "path": "/Applications/Microsoft Edge.app/Contents/Info.plist"
                }
            ]
        },
        {
            "listitem": "Configuring account access...",
            "icon": "SF=lock.square,colour=auto,weight=medium",
            "trigger_list": [
                {
                    "trigger": "install-Privileges",
                    "path": "/Applications/Privileges.app/Contents/Info.plist"
                },
                {
                    "trigger": "install-macOSLAPS",
                    "path": "/usr/local/laps/macOSLAPS"
                },
                {
                    "trigger": "remove-admin",
                    "path": ""
                }
            ]
        },
        {
            "listitem": "Making things pretty...",
            "icon": "SF=sparkles.tv,colour=auto,weight=medium",
            "trigger_list": [
                {
                    "trigger": "install-desktoppr",
                    "path": "/usr/local/bin/desktoppr"
                },
                {
                    "trigger": "configure-default-appearance",
                    "path": ""
                }
            ]
        },
        {
            "listitem": "Submitting Inital Computer Inventory...",
            "icon": "SF=tray.and.arrow.up.fill,colour=auto,weight=medium",
            "trigger_list": [
                {
                    "trigger": "recon",
                    "path": ""
                }
            ]
        }
    ]
}
')

#########################################################################################
# Bash functions used later on
#########################################################################################

echo_logger() {
    # echo_logger version 1.1
    log_folder="${log_folder:=/private/var/log}"
    /bin/mkdir -p "$log_folder"
    echo -e "$(date +'%Y-%m-%d %T%z') - ${log_prefix:+$log_prefix }${1}" | /usr/bin/tee -a "$log_folder/${log_name:=management.log}"
}

echo_logger_heading() {
    echo_logger "#########################################################################"
    echo_logger "$1"
    echo_logger "#########################################################################"
}

dialog_update() {
    echo_logger "DIALOG: $1"
    # shellcheck disable=2001
    echo "$1" >> "$dialog_command_file"
}

get_json_value() {
    JSON="$1" /usr/bin/osascript -l 'JavaScript' \
        -e 'const env = $.NSProcessInfo.processInfo.environment.objectForKey("JSON").js' \
        -e "JSON.parse(env).$2"
}

run_jamf_trigger() {
    trigger="$1"
    if [ "$testing_mode" = true ]; then
        echo_logger "TESTING: $trigger"
        /bin/sleep 1
    elif [ "$trigger" == "recon" ]; then
        echo_logger "RUNNING: $jamf_binary $trigger"
        "$jamf_binary" "$trigger"
    else
        echo_logger "RUNNING: $jamf_binary policy -event $trigger"
        "$jamf_binary" policy -event "$trigger"
    fi
}

# Run script with -t to enable testing_mode
while getopts "t" o; do
    case "${o}" in
        t)
            echo_logger "TESTING: Testing mode enabled"
            echo_logger "TESTING: Jamf Policies will not be run"
            echo_logger "TESTING: No management files will be written"
            testing_mode=true
            ;;
        *)
            ;;
    esac
done

#########################################################################################
# Policy kickoff
#########################################################################################

echo_logger_heading "Start of _enrolment.sh"

# Check if Dialog is running
if ! /usr/bin/pgrep -qx "Dialog"; then
    echo_logger "INFO: Dialog isn't running, launching now"
    "$dialog_app" "${dialog_cmd[@]}" & /bin/sleep 1
else
    echo_logger "INFO: Dialog is running"
    echo_logger "INFO: Dialog Process: $(/usr/bin/pgrep -lx Dialog)"
    dialog_update "title: $dialog_title"
    dialog_update "progresstext: $dialog_status_initial"
fi

dialog_update "progress: complete"

logged_in_user=$( scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }' )
logged_in_user_home=$(dscl . read /Users/"$logged_in_user" NFSHomeDirectory | awk '{print $2}')
logged_in_user_uid=$(id -u "$logged_in_user")
echo_logger "INFO: User details:"
echo_logger "INFO:   logged_in_user: $logged_in_user"
echo_logger "INFO:   logged_in_user_home: $logged_in_user_home"
echo_logger "INFO:   logged_in_user_uid: $logged_in_user_uid"

self_service_custom_icon="$logged_in_user_home/Library/Application Support/com.jamfsoftware.selfservice.mac/Documents/Images/brandingimage.png"
self_service_path=$( /usr/bin/defaults read /Library/Preferences/com.jamfsoftware.jamf.plist self_service_app_path )

if /usr/bin/curl -JLo "$self_service_branding_icon_name" --create-dirs --output-dir "$self_service_branding_icon_location" "$self_service_branding_icon_url"; then
    self_service_branding_icon="$self_service_branding_icon_location/$self_service_branding_icon_name"
    if [[ -f "$self_service_branding_icon" ]]; then
        dialog_overlayicon="$self_service_branding_icon"
    fi
elif [[ -f "$self_service_custom_icon" ]]; then
    dialog_overlayicon="$self_service_custom_icon"
else
    dialog_overlayicon="$self_service_path"
fi

echo_logger "INFO: self_service_branding_icon: $self_service_branding_icon"

#########################################################################################
# Main Script Logic
#########################################################################################

# Iterate through policy_array json to construct the list for swiftDialog
dialog_step_length=$(get_json_value "${policy_array[*]}" "steps.length")
for (( i=0; i<dialog_step_length; i++ )); do
    listitem=$(get_json_value "${policy_array[*]}" "steps[$i].listitem")
    list_item_array+=("$listitem")
done

# Updating swiftDialog with the list of items
dialog_update "overlayicon: $dialog_overlayicon"
dialog_update "icon: default"
dialog_update "icon: $dialog_icon"
dialog_update "message: $dialog_message"
dialog_update "progresstext: "

list_item_string=${list_item_array[*]/%/,}
dialog_update "list: ${list_item_string%?}"
for (( i=0; i<dialog_step_length; i++ )); do
    dialog_update "listitem: index: $i, status: pending, statustext: Pending..."
done
# The ${array_name[*]/%/,} expansion will combine all items within the array adding a "," character at the end
# To add a character to the start, use "/#/" instead of the "/%/"

if [ "$testing_mode" = true ]; then /bin/sleep 2; fi

# This for loop will iterate over each distinct step in the policy_array array
for (( i=0; i<dialog_step_length; i++ )); do
    # Creating initial variables
    listitem=$(get_json_value "${policy_array[*]}" "steps[$i].listitem")
    icon=$(get_json_value "${policy_array[*]}" "steps[$i].icon")
    progresstext=$(get_json_value "${policy_array[*]}" "steps[$i].progresstext")
    trigger_list_length=$(get_json_value "${policy_array[*]}" "steps[$i].trigger_list.length")

    # If there's a value in the variable, update running swiftDialog
    # if [[ -n "$listitem" ]]; then dialog_update "listitem: $listitem: wait"; fi
    if [[ -n "$listitem" ]]; then dialog_update "listitem: index: $i, status: wait, statustext: Downloading..."; fi
    if [[ -n "$icon" ]]; then dialog_update "icon: $icon"; fi
    if [[ -n "$progresstext" ]]; then dialog_update "progresstext: $progresstext"; fi
    if [[ -n "$trigger_list_length" ]]; then
        for (( j=0; j<trigger_list_length; j++ )); do
            # Setting variables within the trigger_list
            trigger=$(get_json_value "${policy_array[*]}" "steps[$i].trigger_list[$j].trigger")
            path=$(get_json_value "${policy_array[*]}" "steps[$i].trigger_list[$j].path")

            # If the path variable has a value, check if that path exists on disk
            if [[ -f "$path" ]]; then
                echo_logger "INFO: $path exists, moving on"
            else
                run_jamf_trigger "$trigger"
            fi
        done
    fi
    if [[ -n "$listitem" ]]; then dialog_update "listitem: index: $i, status: success, statustext: Installed"; fi
done

dialog_update "title: $dialog_title_complete"
dialog_update "list: clear"
dialog_update "overlayicon: clear"
dialog_update "height: 400"
dialog_update "width: 600"
dialog_update "icon: $dialog_icon"
dialog_update "progresstext: $dialog_status_complete"
dialog_update "button1: enable"
dialog_update "button1text: Continue"

#########################################################################################
# Post Enrolment Setup
#########################################################################################

echo_logger "INFO: Configuring post_enrolment_script"

/bin/mv "${working_dir}/${enrolment_base_string}_post.plist" "${post_enrolment_launchdaemon}"
/bin/chmod 644 "${post_enrolment_launchdaemon}"
/usr/sbin/chown root:wheel "${post_enrolment_launchdaemon}"

#########################################################################################
# Script Cleanup
#########################################################################################

if [ "$testing_mode" = true ]; then
    echo_logger "TESTING: Displaying message and exiting out now"
    dialog_update "message: $dialog_message_testing"
    /bin/sleep 5
    dialog_update "quit:"
else
    echo_logger "Writing enrol_initial_policy_end into management_info.plist"
    /usr/bin/defaults write /Library/Management/management_info.plist enrol_initial_policy_end "$(date +%s)"

    filevault_status=$($fde_setup_binary status | grep "Deferred" | cut -d ' ' -f6)

    if [ "$filevault_status" = "active" ]; then
        echo_logger "INFO: FileVault is deferred, logging out now"
        dialog_update "quit:"
        /bin/launchctl bootout user/"$logged_in_user_uid"
    else
        echo_logger "INFO: FileVault is already enabled, moving on"
        dialog_update "message: $dialog_message_final"
    fi
fi

if /bin/launchctl bootstrap system "${post_enrolment_launchdaemon}"; then
    echo_logger "INFO: post_enrolment_launchdaemon launched, exiting script"
    echo_logger "INFO: swiftEnrolment dialog will remain until user_walkthrough has begun"
else
    echo_logger "WARNING: post_enrolment_launchdaemon didn't launch correctly"
    echo_logger "WARNING: Quitting swiftEnrolment dialog"
    /bin/sleep 2
    dialog_update "quit:"
fi

exit 0
