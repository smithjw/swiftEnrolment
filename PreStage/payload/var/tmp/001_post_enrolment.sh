#!/bin/bash
# Post-Enrolment script used at ANZ
# Author: James Smith - james@smithjw.me
# Version 3.0

jamf_binary="/usr/local/jamf/bin/jamf"
jamf_process=$(pgrep -x "jamf")
finder_process=$(pgrep -l "Finder")
log_folder="/private/var/log"
log_name="enrolment.log"

echo_logger() {
    log_folder="${log_folder:=/private/var/log}"
    log_name="${log_name:=log.log}"

    mkdir -p $log_folder

    echo -e "$(date) - $1" | tee -a $log_folder/$log_name
}

jamf_check() {
    trigger="$1"
    echo_logger "SCRIPT: Waiting until jamf is no longer running"
    until [ ! "$jamf_process" ]; do
        sleep 1
        jamf_process=$(pgrep -x "jamf")
    done

    echo_logger "SCRIPT: Running \"jamf $trigger\""
    $jamf_binary "$trigger"
    sleep 2
}

echo_logger "SCRIPT: Waiting until Finder is running"
until [ "$finder_process" != "" ]; do
    sleep 1
    finder_process=$(pgrep -l "Finder")
done

defaults write /Library/Management/ANZ/management_info.plist enrol_login_policy_start "$(date +%s)"

jamf_check "manage"
jamf_check "recon"
jamf_check "policy"

defaults write /Library/Management/ANZ/management_info.plist enrol_login_policy_end "$(date +%s)"

echo_logger "SCRIPT: Cleaning up post-enrolment script"
rm /usr/local/outset/login-privileged-once/001_post_enrolment.sh

exit 0
