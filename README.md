## PreStage Apps

You will need a policy setup in Jamf that uses a custom trigger called `configure-Mac`. If you wish to change this, you can edit the `depnotify_starter_trigger` variable in the `anz.service.smithjw.DEPNotify-prestarter-installer.zsh` file.

Drop the latest version of the DEPNotify app into `PreStage_Apps/pkgroot/Applications/Utilities`

## PreStage Assets

- Drop any assets/logos into the `PreStage_Assets` folder


## distbuild

Update the following variables:

- `certificate_name`
- `provider`
- `dev_email`
- `keychain_account`