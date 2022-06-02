# swiftEnrolment

## Jamf Enrolment Script

You will need a policy setup in Jamf that uses a custom trigger called `configure-Mac`. If you wish to change this, you can edit the `enrolment_starter_trigger` variable in the `com.github.smithjw.mac.swiftEnrolment.sh` file.

## PreStage Package

- Drop any assets/logos into the `PreStage/payload/Library/Management/Images` folder

### build-pkg

Run this script to pull down the latest version of `swiftDialog` and create a PreStage Enrolment package

Either update the variables within the script or run this pkg with the following options:

- Signing Certificate Name: `-c Developer ID Installer: Pretend Co (ABCD1234)`
- Apple Developer Account Email: `-E DEV_ACCOUNT@EMAIL.COM`
- Apple Developer Account Password Item: `-K DEV_ACCOUNT_PASSWORD`
- Apple Developer ASC Provider: `-A DEVELOPER_ASC_PROVIDER`
- Package Identifier: `-i com.github.smithjw.mac.swiftEnrolment`
- Package Name: `-n swiftEnrolment`
- Package Version: `-v 1.0`
- Enable Debug Mode `-d`

You will also need to store the password for your developer account in the keychain using the following method:

`security add-generic-password -s 'distbuild-DEV_ACCOUNT@EMAIL.COM' -a 'YOUR_USERNAME' -w 'DEV_ACCOUNT_PASSWORD'`


## This project was influenced by the following:
#   - https://github.com/jamfprofessionalservices/DEP-Notify
#   - https://gist.github.com/arekdreyer/a7af6eab0646a77b9684b2e620b59e1b
