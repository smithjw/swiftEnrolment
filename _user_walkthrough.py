#!/usr/local/bin/managed_python3
# Version: 1.1.3

import argparse
import asyncio
import concurrent.futures
import json
import logging
import os
import platform
import shlex
import subprocess
import time
from textwrap import dedent

import requests
from pkg_resources import parse_version

dialog_icon = "SF=sparkles.rectangle.stack.fill,colour=auto,weight=medium"
dialog_commandfile = "/var/tmp/dialog.log"
dialog_custom_commandfile = "/var/tmp/dialog_user_walkthrough.log"
dialog_title_prefix = "COMPANY Setup"
download_icon = "SF=laptopcomputer.and.arrow.down,colour=auto,weight=medium"
jamf_binary = "/usr/local/bin/jamf"
dialog_binary = "/usr/local/bin/dialog"
mem_registration_policy_id = 19
mem_registration_policy_url = (
    "jamfselfservice://content?entity=policy&id=19&action=view"
)
role_dict = {
    "title": "Select Role",
    "default": "Engineering",
    "values": ["Design", "Engineering", "Other"],
}

app_list = [
    # {"name": "","icon": "","checked": False,"trigger": "",},
    {
        "name": "Adobe Acrobat Reader",
        "icon": "https://PATH.TO.ICON.com",
        "checked": ["Design", "Other"],
        "trigger": "install-Adobe_Acrobat_Reader",
    },
    {
        "name": "Docker Desktop",
        "icon": "https://PATH.TO.ICON.com",
        "checked": ["Engineering"],
        "trigger": "install-Docker",
    },
    {
        "name": "Figma",
        "icon": "https://PATH.TO.ICON.com",
        "checked": ["Design"],
        "trigger": "install-Figma",
    },
    {
        "name": "GitHub Desktop",
        "icon": "https://PATH.TO.ICON.com",
        "checked": ["Engineering"],
        "trigger": "install-GitHub_Desktop",
    },
    {
        "name": "iTerm2",
        "icon": "https://PATH.TO.ICON.com",
        "checked": ["Engineering"],
        "trigger": "install-iTerm2",
    },
    {
        "name": "Microsoft Office",
        "icon": "https://PATH.TO.ICON.com",
        "checked": ["Design", "Engineering", "Other"],
        "trigger": "install-Microsoft_Office_Suite",
    },
    {
        "name": "Postman",
        "icon": "https://PATH.TO.ICON.com",
        "checked": ["Engineering"],
        "trigger": "install-Postman",
    },
    {
        "name": "Visual Studio Code",
        "icon": "https://PATH.TO.ICON.com",
        "checked": ["Engineering"],
        "trigger": "install-Visual_Studio_Code",
    },
    {
        "name": "Xcode",
        "icon": "https://PATH.TO.ICON.com",
        "checked": ["Engineering"],
        "trigger": "install-Xcode-14",
    },
]


logging.basicConfig(
    level=logging.NOTSET,
    format="%(asctime)s,%(msecs)03d %(levelname)-8s [%(filename)s:%(lineno)d] %(message)s",
    datefmt="%Y-%m-%d:%H:%M:%S",
)
logger = logging.getLogger("bootstrap")
logger.setLevel(logging.WARNING)


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "mountpoint",
        nargs="?",
        help="Default argument passed into the script if run from Jamf. $1",
    )
    parser.add_argument(
        "computer_name",
        nargs="?",
        help="Default argument passed into the script if run from Jamf. $2",
    )
    parser.add_argument(
        "user_shortname",
        nargs="?",
        help="Default argument passed into the script if run from Jamf. $3",
    )
    parser.add_argument(
        "unknown",
        nargs="*",
        help="Capture remaining positional arguments",
    )
    parser.add_argument(
        "-log",
        default="info",
        required=False,
        help="Provide logging level. Example -log debug, default=info",
    )

    parser.add_argument(
        "-demo",
        default=False,
        action="store_true",
        required=False,
        help="Won't execute jamf policies if set",
    )

    result = parser.parse_args()

    logger.debug(result)
    return result


async def get_self_service_branding_icon():
    # Check for the icon on disk first and download it if not found
    self_service_branding_icon_name = "brandingimage.png"
    self_service_branding_icon_location = "/Library/Management/images"
    self_service_branding_icon_url = (
        "https://COMPANY.jamfcloud.com/api/v1/branding-images/download/9"
    )
    self_service_branding_icon = (
        f"{self_service_branding_icon_location}/{self_service_branding_icon_name}"
    )

    if not os.path.exists(self_service_branding_icon):
        # Open the url image, set stream to True, this will return the stream content.
        request = requests.get(self_service_branding_icon_url, stream=True)

        # Check if the image was retrieved successfully
        if request.status_code == 200:
            # Open a local file with wb ( write binary ) permission.
            with open(self_service_branding_icon, "wb") as f:
                f.write(request.content)

            logger.debug("Branding icon downloaded")
            result = self_service_branding_icon

        else:
            logger.debug("Branding icon couldn't be downloaded, setting generic icon")
            result = dialog_icon

    else:
        logger.debug("Branding image already on disk")
        result = self_service_branding_icon

    logger.debug(f"Branding icon: {result}")
    return result


def run_jamf_policy(trigger):
    """Runs a jamf policy given the provided trigger"""
    result = None

    cmd = f"{jamf_binary} policy \
        -event {trigger}"
    logger.debug(f"cmd: {cmd}")

    cmd_split = shlex.split(cmd)

    jamf_policy = subprocess.Popen(cmd_split, stdout=subprocess.PIPE, text=True)

    while True:
        # Get the current output of the subprocess
        cmd_output = jamf_policy.stdout

        if jamf_policy.poll() is None:
            # poll() returns None if the process is still running
            if cmd_output:
                # Logs the current output of the command, if any
                logger.debug(f"{cmd_output.readline().strip()}")
        else:
            logger.debug(f"returncode: {jamf_policy.poll()}")
            break

    if jamf_policy.poll() == 0:
        logger.debug(f"Successfully ran JAMF policy via trigger: {trigger}")
        result = True
    else:
        logger.debug(f"Unable to run JAMF policy via trigger: {trigger}")
        result = False

    return result


def dialog_log(dialog_command: str, commandfile=dialog_commandfile):
    logger.debug(f"dialog_log commandfile: {commandfile}")
    logger.debug(f"dialog_log dialog_command: {dialog_command}")

    # adding sleep so Dialog updates
    time.sleep(0.5)
    with open(commandfile, "a") as f:
        f.write(f"\n{dialog_command}")

    return


def process_jamf_app_list(jamf_app_list, demo_mode):
    # Adding initial sleep so that swiftDialog has time to catch up
    logger.debug("########################################################")
    logger.debug("process_jamf_app_list")
    logger.debug("########################################################")

    # jamf_app_list = kwargs.get("jamf_app_list")
    # demo_mode = kwargs.get("demo_mode")

    if jamf_app_list:
        time.sleep(1)
        for app in jamf_app_list:
            index = app.get("index")
            trigger = app.get("trigger")

            dialog_log(
                commandfile=dialog_custom_commandfile,
                dialog_command=f"listitem: index: {index}, status: wait, statustext: Installing",
            )

            if demo_mode:
                logger.info(f"Demo mode is enabled, marking {trigger} successful")
                time.sleep(0.5)
                dialog_log(
                    commandfile=dialog_custom_commandfile,
                    dialog_command=f"listitem: index: {index}, status: success, statustext: Demo",
                )
            else:
                if run_jamf_policy(trigger):
                    logger.info(f"Policy successful: {trigger}")
                    dialog_log(
                        commandfile=dialog_custom_commandfile,
                        dialog_command=f"listitem: index: {index}, status: success, statustext: Installed",
                    )
                else:
                    logger.warning(f"Policy failed: {trigger}")
                    dialog_log(
                        commandfile=dialog_custom_commandfile,
                        dialog_command=f"listitem: index: {index}, status: fail, statustext: Failed",
                    )

        dialog_log(
            commandfile=dialog_custom_commandfile,
            dialog_command="quit:",
        )

    return


async def macos_update_required(demo_mode):
    # Get the current version of macOS
    local_version = platform.mac_ver()[0]

    if demo_mode:
        logger.info("Demo mode is enabled, setting dummy Software Update info")
        update_required = True
        latest_version = "19.1"
    else:
        # Get the JSON data from the URL
        url = "https://jamf-patch.jamfcloud.com/v1/software/"
        request = requests.get(url)
        data = request.json()

        logger.debug(f"Requests status_code: {request.status_code}")

        # Use list comprehension to filter the JSON data and retrieve the item with the name "Apple macOS Ventura"
        item = next((i for i in data if i["name"] == "Apple macOS Ventura"), None)

        if item:
            latest_version = item["currentVersion"].split(" ")[0]

            parsed_local_version = parse_version(local_version)
            parsed_latest_version = parse_version(latest_version)

            logger.info(f"Current version: {local_version}")
            logger.info(f"Latest version: {latest_version}")

            if parsed_local_version < parsed_latest_version:
                update_required = True
            elif parsed_local_version == parsed_latest_version:
                update_required = False
            else:
                update_required = False
        else:
            logger.warning(
                "The item 'Apple macOS Ventura' could not be found in the JSON data."
            )
            update_required = False
            latest_version = None

    result = update_required, local_version, latest_version

    return result


async def dialog_prompt(commandfile=dialog_commandfile, **kwargs):
    # Function to display a generic swiftDialog prompt
    result = None

    logger.debug(f"dialog_prompt kwargs: {kwargs}")

    blocking = kwargs.get("blocking", True)
    dialog_icon = await get_self_service_branding_icon()

    dialog_dict = {
        "button1text": kwargs.get("button1text"),
        "checkbox": kwargs.get("checkbox"),
        "commandfile": commandfile,
        "icon": kwargs.get("icon", dialog_icon),
        "ignorednd": kwargs.get("ignorednd"),
        "json": True,
        "listitem": kwargs.get("listitem"),
        "message": dedent(kwargs.get("message", None)),
        "position": kwargs.get("position"),
        "ontop": kwargs.get("ontop", True),
        "moveable": True,
        "selectitems": kwargs.get("selectitems"),
        "small": kwargs.get("small"),
        "mini": kwargs.get("mini"),
        "title": kwargs.get("title"),
        "button1action": kwargs.get("button1action"),
    }

    if kwargs.get("width"):
        dialog_dict |= {
            "width": kwargs.get("width"),
        }

    if kwargs.get("height"):
        dialog_dict |= {
            "height": kwargs.get("height"),
        }

    if kwargs.get("timer"):
        dialog_dict |= {
            "timer": kwargs.get("timer"),
            "hidetimerbar": True,
        }

    json_string = shlex.quote(json.dumps(dialog_dict))
    logger.debug(f"json_string: {json_string}")

    cmd = f"{dialog_binary} \
        --jsonstring {json_string}"
    logger.debug(f"cmd: {cmd}")
    cmd_split = shlex.split(cmd)
    # cmd_quote = shlex.quote(cmd)

    # TODO: Need to figure out a better way to implement this
    if blocking:
        # Default action for .run() is to block before moving on
        # TODO: Should this use asyncio.create_subprocess_shell - https://docs.python.org/3/library/asyncio-subprocess.html
        blocking_prompt = subprocess.run(cmd_split, capture_output=True)
        logger.debug(f"blocking_prompt: {blocking_prompt}")

        if blocking_prompt.returncode == 0:
            result = json.loads(blocking_prompt.stdout)
        elif blocking_prompt.returncode == 4:
            logger.debug(f"Return code was {blocking_prompt.returncode}, timer ran out")
            result = True
        else:
            logger.warning(f"blocking_prompt: {blocking_prompt}")
            result = False
    elif not blocking:
        # Default action for .Popen() is to spawn the dialog window, then move on
        # TODO: Should this use asyncio.create_subprocess_shell - https://docs.python.org/3/library/asyncio-subprocess.html
        result = subprocess.Popen(
            cmd_split, stdin=None, stdout=None, stderr=None, close_fds=True
        )
        # result = asyncio.create_subprocess_shell(
        #     cmd_quote, stdin=None, stdout=None, stderr=None, close_fds=True
        # )

    logger.debug(f"result: {result}")
    return result


async def return_selected_role(**kwargs):
    """Displays a message to the user via Dialog to select their role"""
    result = None

    selected_role = await dialog_prompt(
        title=kwargs.get("title"),
        message=kwargs.get("message"),
        button1text="Next",
        height="220",
        width="600",
        blocking=True,
        selectitems=[kwargs.get("roles")],
    )

    if type(selected_role) is dict:
        result = selected_role.get("SelectedOption")
        logger.debug(f"selected_role: {result}")

    return result


async def return_selected_apps(**kwargs):
    # Allow users to select applications
    result = None

    title = kwargs.get("title")
    message = kwargs.get("message")
    role = kwargs.get("role")
    desired_keys = ["name", "checked"]

    app_checkboxes = [
        {
            **{
                "label"
                if key == "name"  # Changes key name to "label" if it was "name" prior
                else key: value
                if key != "checked"
                else role in value
                for key, value in item.items()
                if key in desired_keys  # filter key-value pairs based on desired_keys
            },
            # Add new boolean key-value pair to each item based on the name of the item
            "disabled": item["name"] == "Microsoft Office",
        }
        for item in app_list  # Iterate over each item in the app_list
    ]

    logger.debug(app_checkboxes)

    selected_apps = await dialog_prompt(
        title=title,
        message=message,
        button1text="Install",
        height="450",
        width="600",
        blocking=True,
        checkbox=app_checkboxes,
    )

    if type(selected_apps) is dict:
        # Filter dict to selected applications only
        result = list(dict(filter(lambda e: e[1], selected_apps.items())).keys())
        logger.debug(f"selected_apps: {result}")

    return result


async def create_selected_app_lists(**kwargs):
    # Makes new lists from the selected apps

    apps = kwargs.get("apps")

    if type(apps) is not list:
        raise TypeError("apps must be a list")
    else:
        selected_apps = sorted(apps)

    # Create listitem for for use in swiftDialog
    dialog_listitem = [
        {
            "title": app,
            "icon": next(a["icon"] for a in app_list if a["name"] == app),
            "status": "pending",
            "statustext": "Pending",
        }
        for app in selected_apps
    ]
    logger.debug(f"dialog_listitem: {dialog_listitem}")

    # Create list for executing jamf policies
    jamf_app_list = [
        {
            "index": index,
            "name": app,
            "trigger": next(a["trigger"] for a in app_list if a["name"] == app),
        }
        for index, app in enumerate(selected_apps)
    ]
    logger.debug(f"jamf_app_list: {jamf_app_list}")

    result = dialog_listitem, jamf_app_list

    return result


async def walkthrough_welcome(demo_mode):
    logger.debug("########################################################")
    logger.debug("walkthrough_welcome")
    logger.debug("########################################################")
    await asyncio.sleep(0)

    # 💻 Computer = U+1F4BB
    # 🔄 Sync/Counterclockwise = U+1F504
    # 🔑 Key = U+1F511

    await dialog_prompt(
        title=dialog_title_prefix,
        message="""\
            Let's get a few more things setup on your new Mac.  \n\n
                \U0001F4BB Install Additional Apps \n
                \U0001F504 macOS Update Check \n
                \U0001F511 Device Compliance Registration \n
            """,
        button1text="Next",
        blocking=True,
        height="300",
        timer="10",
    )


async def walkthrough_role_app_selection():
    logger.debug("########################################################")
    logger.debug("role_app_selection")
    logger.debug("########################################################")
    await asyncio.sleep(0)

    # Promt user which role they're in and return
    selected_role = await return_selected_role(
        title=f"{dialog_title_prefix}: Select Role",
        message="""\
            Please select the role that most closely aligns to your function.
            """,
        roles=role_dict,
    )

    # Ask the user what additional applications they would like to install
    selected_apps = await return_selected_apps(
        title=f"{dialog_title_prefix}: Select Applications",
        message="Please select any additional applications you'd like us to install now:",
        role=selected_role,
    )

    # Install the selected applications
    if selected_apps:
        dialog_listitem, jamf_app_list = await create_selected_app_lists(
            apps=selected_apps
        )

        await dialog_prompt(
            title=f"{dialog_title_prefix}: Installing Applications",
            message="""\
                These applications are now being installed. \n\n
                This will continue in the background.
            """,
            icon=download_icon,
            button1text="Ok",
            small=False,
            blocking=False,
            ontop=False,
            listitem=dialog_listitem,
            position="bottomright",
            commandfile=dialog_custom_commandfile,
        )

        return jamf_app_list

    else:
        logger.debug("app_selection was empty, moving on")
        return None


async def walkthrough_device_update(demo_mode):
    logger.debug("########################################################")
    logger.debug("walkthrough_device_update")
    logger.debug("########################################################")
    logger.debug(f"walkthrough_device_update demo_mode: {demo_mode}")
    await asyncio.sleep(0)

    update_required, local_version, latest_version = await macos_update_required(
        demo_mode
    )

    logger.debug(f"update_required: {update_required}")
    if update_required:
        major_version = int(local_version.split(".")[0])

        if major_version >= 13:
            cmd = "open 'x-apple.systempreferences:com.apple.Software-Update-Settings.extension'"
        else:
            cmd = (
                "open 'x-apple.systempreferences:com.apple.preferences.softwareupdate'"
            )

        await asyncio.sleep(1.5)

        await dialog_prompt(
            title=f"{dialog_title_prefix}: Update Required",
            message=f"""\
                Let's get the latest version of macOS installed now \n
                Current: {local_version}
                Latest: {latest_version}\
            """,
            # In order to ensure the best experience and to maintain compliance, please click Update.
            button1text="Update Now",
            # height="325",
            # width="650",
            mini=True,
            blocking=True,
            ontop=False,
            position="topright",
        )

        if demo_mode:
            logger.info("demo_mode enabled, bypassing Software Update launch")
        else:
            # Launch Software Update - Can't use a button action for the deep linking to Software Update
            result = await asyncio.create_subprocess_shell(cmd)
            logger.debug(f"result: {result}")
    else:
        await asyncio.sleep(1.5)

        await dialog_prompt(
            title=f"{dialog_title_prefix}: macOS Update",
            message="""\
                Your Mac is already on the latest version of macOS. \n
                Let's move onto Device Compliance Registration.
            """,
            button1text="Next",
            # height="225",
            # width="650",
            mini=True,
            blocking=True,
            position="topright",
            timer="10",
        )

    return


async def walkthrough_device_registration(demo_mode):
    logger.debug("########################################################")
    logger.debug("walkthrough_device_registration")
    logger.debug("########################################################")
    await asyncio.sleep(0)

    await asyncio.sleep(1.5)

    # if demo_mode:
    #     logger.info("demo_mode enabled, disabling button action")
    #     button1action = None
    # else:
    #     button1action = mem_registration_policy_url

    await dialog_prompt(
        title=f"{dialog_title_prefix}: Device Compliance Registration",
        message="""\
            While your selected apps install, we need to register this device with Microsoft. \n
            We'll launch Self Service and continue there.\
            """,
        button1text="Register",
        # height="250",
        # width="650",
        mini=True,
        blocking=True,
        # button1action=button1action,
        position="topright",
        ontop=False,
    )

    if demo_mode:
        logger.info("demo_mode enabled, bypassing Self Service launch")
    else:
        cmd = f"open '{mem_registration_policy_url}'"
        result = await asyncio.create_subprocess_shell(cmd)
        logger.debug(f"result: {result}")


async def main():
    """Manage arguments and run workflow"""

    # Ensure there aren't any old dialog log files lying around...
    if os.path.exists(dialog_commandfile):
        logger.info(f"Removing prior dialog_commandfile: {dialog_commandfile}")
        result = os.remove(dialog_commandfile)
        logger.info(f"Result: {result}")
    if os.path.exists(dialog_custom_commandfile):
        logger.info(f"Removing prior dialog_custom_commandfile: {dialog_commandfile}")
        result = os.remove(dialog_custom_commandfile)
        logger.info(f"Result: {result}")

    args = parse_args()
    log_level = args.log
    demo_mode = args.demo

    if log_level:
        logger.setLevel(getattr(logging, log_level.upper()))
    else:
        logger.setLevel(logging.INFO)

    logger.info(f"argparse: {args}")

    loop = asyncio.get_running_loop()

    asyncio.create_task(walkthrough_welcome(demo_mode))
    jamf_app_list = asyncio.create_task(walkthrough_role_app_selection())
    asyncio.create_task(walkthrough_device_update(demo_mode))
    asyncio.create_task(walkthrough_device_registration(demo_mode))

    # https://docs.python.org/3/library/asyncio-eventloop.html#asyncio.loop.run_in_executor
    with concurrent.futures.ProcessPoolExecutor() as pool:
        await loop.run_in_executor(
            pool,
            process_jamf_app_list,
            await jamf_app_list,
            args.demo,
        )


if __name__ == "__main__":
    start_time = time.time()
    asyncio.run(main())
    end_time = time.time()

    print(f"Total time elapsed: {end_time - start_time} seconds")
