#!/bin/bash
# exec 1> >(logger -s -t $(basename $0)) 2>&1
# set -x

#########################################################################################
# Policy Variables to Modify
#########################################################################################
counter_start=0
enrolment_starter_trigger="configure-Mac"
log_folder="/private/var/log"
log_name="swiftEnrolment.log"
jamf_binary="/usr/local/bin/jamf"

dialog_app="/usr/local/bin/dialog"
dialog_command_file="/var/tmp/dialog.log"
dialog_icon="/Library/Management/Images/company_logo.png"
dialog_initial_title="Welcome to your new Mac"
dialog_initial_image="/Library/Management/Images/new_mac.jpg"
dialog_error_url_prefix="https://github.com/smithjw/swiftEnrolment/raw/main"
dialog_error_img_1="PreStage/payload/var/tmp/eacs_menu_bar_half.png?raw=true"
dialog_error_img_2="PreStage/payload/var/tmp/eacs_menu_half.png?raw=true"
dialog_error_title="Something went wrong"

dialog_error_text=(
    'The enrolment did not complete successfully, please perform the following: \n\n'
    '1. Launch System Preferences \n'
    '1. Click on the System Preferences menu item in the top-left of your screen \n\n'
    '    !'"[Menu Bar]($dialog_error_url_prefix/$dialog_error_img_1) \n"
    '1. Click Erase all Contents and Settings... \n\n'
    '    !'"[Menu Bar]($dialog_error_url_prefix/$dialog_error_img_2) \n"
    '1. Enter your password and try setting up your Mac again. \n\n'
)
    # Single quotes are used for the ! so that the shell does not try and interpret it. Leaving it followed by the
    # double-quoted string for the images on the same line for readability

dialog_cmd=(
    "-p --title \"$dialog_initial_title\""
    "--icon \"$dialog_icon\""
    "--message \" \""
    "--centericon"
    "--width 70%"
    "--height 70%"
    "--position centre"
    "--button1disabled"
    "--progress 60"
)

    # Because dialog_initial_title and dialog_initial_image are passed into the dialog command as command-line arguments
    # we need to ensure that they are quoted once constructed into the full command. We use double quotes for each argument
    # as parameter expansion does not work within single quotes.

#########################################################################################
# Main Functions
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

dialog_reset_progress() {
    dialog_update "progress: complete"
    dialog_update "progress: reset"
    counter_start=0

    # Adding "progress: complete" before "progress: reset" makes things look nicer within swiftDialog
    # Resetting $counter_start for another period before triggering a failed enrolment
}

dialog_finalise() {
    dialog_update "progresstext: Initial Enrolment Complete"
    sleep 1
    dialog_update "quit:"
    exit 0
}

get_json_value() {
    JSON="$1" osascript -l 'JavaScript' \
        -e 'const env = $.NSProcessInfo.processInfo.environment.objectForKey("JSON").js' \
        -e "JSON.parse(env).$2"
}

jamf_fixer () {

    dialog_eacs

    # TODO: after passing quit, relaunch smaller window top-right
    # TODO: Quit button to launch System Preferences
    # TODO: Change label of button


}

dialog_eacs () {
    dialog_update "title: $dialog_error_title"
    dialog_update "icon: left"
    dialog_update "icon: $dialog_icon"
    dialog_update "message: ${dialog_error_text[*]}"
    dialog_update "button1: enable"
    dialog_update "progresstext: "
    dialog_update "progress: complete"
    sleep "$jamf_fixer_sleep_time"
    dialog_update "quit:"
    exit 0
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
# Testing Mode Configurations
#########################################################################################
# $counter_limit controls how long this script will wait for the initial Jamf enrolment
# and then once reset, how long it will watch the jamf log for "enrollmentComplete" before
# running the jamf_fixer function

if [[ -z "$testing_mode" ]]; then
    # Running in production
    dialog_cmd+=("--blurscreen")
    counter_limit=60
    jamf_fixer_sleep_time=30
    watch_log="/var/log/jamf.log"
else
    # Running in testing_mode
    dialog_cmd+=("--blurscreen")
    counter_limit=5
    jamf_fixer_sleep_time=5
    watch_log="/var/log/jamf.log"
    # watch_log="/var/log/jamf_test.log"
fi

#########################################################################################
# Main Script Logic
#########################################################################################

if [ ! -f "$dialog_app" ]; then
    echo_logger "swiftDialog not installed"
    dialog_latest=$( curl -sL https://api.github.com/repos/bartreardon/swiftDialog/releases/latest )
    dialog_url=$(get_json_value "$dialog_latest" 'assets[0].browser_download_url')
    curl -L --output "dialog.pkg" --create-dirs --output-dir "/var/tmp" "$dialog_url"
    installer -pkg "/var/tmp/dialog.pkg" -target /
fi

# Waiting for Setup Assistant to complete
setup_assistant_process=$(pgrep -l "Setup Assistant")
until [ "$setup_assistant_process" = "" ]; do
  echo_logger "Setup Assistant Still Running. PID $setup_assistant_process."
  sleep 1
  setup_assistant_process=$(pgrep -l "Setup Assistant")
done

# Waiting for the Finder process to initialise
finder_process=$(pgrep -l "Finder")
until [ "$finder_process" != "" ]; do
  echo_logger "Finder process not found. Assuming device is at login screen."
  sleep 1
  finder_process=$(pgrep -l "Finder")
done

# Grabbing user information and launching swiftDialog
logged_in_user=$( scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }' )
echo_logger "Current user set to $logged_in_user."

# Run swiftDialog
eval "$dialog_app" "${dialog_cmd[*]}" & sleep 1

dialog_update "icon: none"
dialog_update "image: $dialog_initial_image"

until [ -f "$watch_log" ]
do
    dialog_update "progress: increment"
    dialog_update "progresstext: Waiting for Jamf installation"
    sleep 1
    ((counter_start++))
    if [[ $counter_start -gt $counter_limit ]]; then
        jamf_fixer
    fi
done

dialog_reset_progress

until ( /usr/bin/grep -q enrollmentComplete "$watch_log" )
do
    dialog_update "progresstext: $(tail -1 $watch_log)"
    dialog_update "progress: increment"
    sleep 1
    ((counter_start++))
    if [[ $counter_start -gt $counter_limit ]]; then
        jamf_fixer
    fi
done

dialog_update "progresstext: Launching first-run scripts now"
dialog_update "progress: indeterminate"

# If we're not in testing_mode, write to the Management plist and call the Jamf Custom Trigger
if [[ -z "$testing_mode" ]]; then
    defaults write /Library/Management/management_info.plist enrol_prestage_end "$(date +%s)"
    $jamf_binary policy -event ${enrolment_starter_trigger}
fi

exit 0
exit 1
