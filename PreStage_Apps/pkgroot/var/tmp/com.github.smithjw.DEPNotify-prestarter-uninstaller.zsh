#!/bin/zsh
# shellcheck shell=bash
# Initially sourced from https://gist.github.com/arekdreyer/a7af6eab0646a77b9684b2e620b59e1b

# This is meant to be called by a Jamf Pro policy via trigger
# Near the end of your POLICY_ARRAY in your DEPNotify.sh script

rm /var/tmp/com.github.smithjw.DEPNotify-prestarter-installer.zsh

# Note that if you unload the LaunchDaemon this will immediately kill the depNotify.sh script
# Just remove the underlying plist file, and the LaunchDaemon will not run after next reboot/login.
rm /Library/LaunchDaemons/com.github.smithjw.DEPNotify-prestarter.plist
rm /var/tmp/com.github.smithjw.DEPNotify-prestarter-uninstaller.zsh

# Write time to management plist that enrollment completed
defaults write /Library/Management/management_info.plist enrol_end_uninstaller "$(date +%s)"

exit 0
exit 1
