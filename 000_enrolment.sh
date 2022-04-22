#!/bin/bash
# Enrolment script used at ANZ
# Author: James Smith - james@smithjw.me
# Version 3.0

defaults write /Library/Management/management_info.plist enrol_initial_policy_start "$(date +%s)"

# Projects that this script steals from:
#   - https://github.com/jamfprofessionalservices/DEP-Notify
#   -

dialog_app="/usr/local/bin/dialog"
dialog_command_file="/var/tmp/dialog.log"
dialog_icon="/Library/Management/Images/company_logo.png"

dialog_title="We're getting a few things ready on your new Mac"
dialog_title_complete="You're all done"
dialog_message="Thanks for choosing a Mac! \n\n We want you to have a few applications and settings configured before you get started. \n\n This process should take about 5 to 10 minutes to complete."
dialog_message_testing="This is usually where swiftDialog would quit, and the user logged out. \n\nHowever, testing_mode is enabled and FileVault deferred status is on."
dialog_status_initial="Initial Configuration Starting..."
dialog_status_complete="Configuration Complete!"

dialog_cmd=(
    "-p --title \"$dialog_title\""
    "--iconsize 200"
    "--width 70%"
    "--height 70%"
    "--position centre"
    "--button1disabled"
    "--progress 30"
    "--progresstext \"$dialog_status_initial\""
    "--blurscreen"
)

jamf_binary="/usr/local/bin/jamf"
fde_setup_binary="/usr/bin/fdesetup"

log_folder="/private/var/log"
log_name="enrolment.log"

#########################################################################################
# Policy Array to determine what's installed
#########################################################################################

# colour1=#007DBA colour2=#0064A1

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
    log_folder="${log_folder:=/private/var/log}"
    log_name="${log_name:=log.log}"

    mkdir -p $log_folder

    echo -e "$(date) - $1" | tee -a $log_folder/$log_name
}

dialog_update() {
    echo_logger "DIALOG: $1"
    # shellcheck disable=2001
    echo "$1" >> "$dialog_command_file"
}

get_json_value() {
    JSON="$1" osascript -l 'JavaScript' \
        -e 'const env = $.NSProcessInfo.processInfo.environment.objectForKey("JSON").js' \
        -e "JSON.parse(env).$2"
}

run_jamf_trigger() {
    trigger="$1"
    if [ "$testing_mode" = true ]; then
        echo_logger "TESTING: $trigger"
        sleep 1
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

# Check if Dialog is running
if [ ! "$(pgrep -x "dialog")" ]; then
    echo_logger "INFO: Dialog isn't running, launching now"
    eval "$dialog_app" "${dialog_cmd[*]}" & sleep 1
else
    echo_logger "INFO: Dialog is running"
    dialog_update "title: $dialog_title"
    dialog_update "progresstext: $dialog_status_initial"
fi

dialog_update "progress: complete"

logged_in_user=$( scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }' )
logged_in_user_uid=$(id -u "$logged_in_user")
echo_logger "Current user set to $logged_in_user."

# echo_logger "INFO: Caffeinating swiftDialog process. Process ID: $dialog_process"
# caffeinate -disu -w "$dialog_process"&

# Rename the Mac to match SN if that wasn't completed prior
if [ "$testing_mode" != true ]; then
    serial_number=$(ioreg -c IOPlatformExpertDevice -d 2 | awk -F\" '/IOPlatformSerialNumber/{print $(NF-1)}')
    hostname=$(hostname)
    if [ "$hostname" != "$serial_number" ]; then
        echo_logger "Renaming the Mac to $serial_number"
        "$jamf_binary" setComputerName -name "$serial_number"
    fi
fi

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
dialog_update "icon: default"
dialog_update "icon: $dialog_icon"
dialog_update "message: $dialog_message"
dialog_update "progresstext: "

list_item_string=${list_item_array[*]/%/,}
dialog_update "list: ${list_item_string%?}"
for (( i=0; i<dialog_step_length; i++ )); do
    dialog_update "listitem: index: $i, status: pending"
done
# The ${array_name[*]/%/,} expansion will combine all items within the array adding a "," character at the end
# To add a character to the start, use "/#/" instead of the "/%/"

if [ "$testing_mode" = true ]; then sleep 2; fi

# This for loop will iterate over each distinct step in the policy_array array
for (( i=0; i<dialog_step_length; i++ )); do
    # Creating initial variables
    listitem=$(get_json_value "${policy_array[*]}" "steps[$i].listitem")
    icon=$(get_json_value "${policy_array[*]}" "steps[$i].icon")
    trigger_list_length=$(get_json_value "${policy_array[*]}" "steps[$i].trigger_list.length")

    # If there's a value in the variable, update running swiftDialog
    # if [[ -n "$listitem" ]]; then dialog_update "listitem: $listitem: wait"; fi
    if [[ -n "$listitem" ]]; then dialog_update "listitem: index: $i, status: wait"; fi
    if [[ -n "$icon" ]]; then dialog_update "icon: $icon"; fi
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
    if [[ -n "$listitem" ]]; then dialog_update "listitem: index: $i, status: success"; fi
done

dialog_update "title: $dialog_title_complete"
dialog_update "progresstext: $dialog_status_complete"

#########################################################################################
# Script Cleanup
#########################################################################################

echo_logger "INFO: Configuring post_enrolment_script"
post_enrolment_script="001_post_enrolment.sh"
mv "/var/tmp/$post_enrolment_script" "/usr/local/outset/login-privileged-once/$post_enrolment_script"
chown root:wheel "/usr/local/outset/login-privileged-once/$post_enrolment_script"
chmod 755 "/usr/local/outset/login-privileged-once/$post_enrolment_script"

# Remove files from the prestage package
prestarter_files=(
    "/Library/LaunchDaemons/com.github.smithjw.prestarter.plist"
    "/var/tmp/com.github.smithjw.prestarter-installer.sh"
    "/var/tmp/com.github.smithjw.prestarter-installer.sh"
)

for file in "${prestarter_files[@]}"; do
    if [[ -f $file ]]; then
        rm "$file"
    fi
done

if [ "$testing_mode" = true ]; then
    echo_logger "TESTING: Displaying message and exiting out now"
    dialog_update "list: clear"
    dialog_update "message: $dialog_message_testing"
    dialog_update "icon: center"
    dialog_update "icon: $dialog_icon"
    sleep 5
    dialog_update "quit:"
else
    echo_logger "INFO: Writing the end time of the enrolment script into the management plist"
    defaults write /Library/Management/management_info.plist enrol_initial_policy_end "$(date +%s)"
    touch /var/tmp/com.depnotify.provisioning.done # Just in case you're replacing an old DEPnotify workflow

    filevault_status=$($fde_setup_binary status | grep "Deferred" | cut -d ' ' -f6)

    if [ "$filevault_status" = "active" ]; then
        echo_logger "INFO: FileVault is deferred, logging out now"
        dialog_update "quit:"
        launchctl bootout user/"$logged_in_user_uid"
    else
        echo_logger "INFO: FileVault is already enabled, quitting swiftDialog"
        dialog_update "quit:"
    fi
fi

exit 0
exit 1
