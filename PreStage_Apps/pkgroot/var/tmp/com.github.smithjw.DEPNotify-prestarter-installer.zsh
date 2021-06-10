#!/bin/zsh
# shellcheck shell=bash

# Some Variables
depnotify_app="/Applications/Utilities/DEPNotify.app"
depnotify_log="/var/tmp/depnotify.log"
depnotify_debug="/var/tmp/depnotifyDebug.log"
depnotify_starter_trigger="configure-Mac"

xattr -r -d com.apple.quarantine $depnotify_app

setup_assistant_process=$(pgrep -l "Setup Assistant")
until [ "$setup_assistant_process" = "" ]; do
  echo "$(date "+%a %h %d %H:%M:%S"): Setup Assistant Still Running. PID $setup_assistant_process." >> "$depnotify_debug"
  sleep 1
  setup_assistant_process=$(pgrep -l "Setup Assistant")
done

# Checking to see if the Finder is running now before continuing. This can help
# in scenarios where an end user is not configuring the device.
finder_process=$(pgrep -l "Finder")
until [ "$finder_process" != "" ]; do
  echo "$(date "+%a %h %d %H:%M:%S"): Finder process not found. Assuming device is at login screen." >> "$depnotify_debug"
  sleep 1
  finder_process=$(pgrep -l "Finder")
done

# After the Apple Setup completed. Now safe to grab the current user.
logged_in_user=$( scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }' )
echo "$(date "+%a %h %d %H:%M:%S"): Current user set to $logged_in_user." >> "$depnotify_debug"

sudo -u "$logged_in_user" open -a "$depnotify_app" --args -path "$depnotify_log" -fullScreen

until [ -f /var/log/jamf.log ]
do
	echo "Waiting for jamf log to appear"
	sleep 1
done

until ( /usr/bin/grep -q enrollmentComplete /var/log/jamf.log )
do
	echo "Waiting for jamf enrollment to be complete."
	sleep 1
done

defaults write /Library/Management/management_info.plist enrol_end_prestage "$(date +%s)"
/usr/local/jamf/bin/jamf policy -event ${depnotify_starter_trigger}

exit 0
exit 1
