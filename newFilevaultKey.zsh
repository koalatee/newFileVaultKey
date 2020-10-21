#!/bin/zsh


###
#
#            Name:  jamf-newFilevaultKey
#            From:  
#     Description:  This script is intended to run on Macs which no longer have
#                   a valid recovery key in jamf Pro. It prompts users to enter
#                   their Mac password, and uses this password to generate a
#                   new FileVault key and escrow with your mdm. The "Escrow
#                   FileVault key" configuration profile must already
#                   be deployed in order for this script to work correctly.
#                   - In Elliot's original script (linked below), the profile identifier can 
#                     be given to search for the correct profile being installed
#                   - This script searches for Escrow (profiles show |grep Escrow) to
#                     see if the profile is installed. 
#                   - This shouldn't be jamf specific, as it should find a payload for 
#                     com.apple.security.FDERecoveryKeyEscrow, but it's all I have to test. 
#
#                   Based off of https://github.com/homebysix/jss-filevault-reissue
#                   Modified to move to zsh and osascript (not jamfHelper), which
#                   should ensure compatibility outside of jamf.
#                   - There is a mention of jamf near end: if jamf binary exists then run recon & continue
#                   - To assist with the double recon requirement of key uploading and validation
#
#                   This has been tested with macOS 10.15 and macOS 11, requires macOS 10.13+ (for Escrow key)
#                   - Has not been tested on macOS 10.13 or macOS 10.14, but should work on both
#
#    Requirements:  the applescript functions do require PPPC for terminal > system events
#          Author:  James Journey
#         Created:  2020-10-21
#   Last Modified:  2020-10-21
#         Version:  1.0
#
###


################################## VARIABLES ##################################

IT_CONTACT_SHORT=""
IT_CONTACT_FULL=""

# The title of the message that will be displayed to the user.
# Not too long, or it'll get clipped.
PROMPT_TITLE="Encryption Key Escrow"

# The body of the message that will be displayed before prompting the user for
# their password. All message strings below can be multiple lines.
PROMPT_MESSAGE="Your Mac's FileVault encryption key needs to be changed for $IT_CONTACT_SHORT to be able to decrypt your hard drive in the event of a failure.

Click the Next button below, then enter your Mac's password when prompted. 

If you have any questions, please contact $IT_CONTACT_FULL."

# The body of the message that will be displayed after 5 incorrect passwords.
FORGOT_PW_MESSAGE="You made five incorrect password attempts.
Please contact $IT_CONTACT_FULL for assistance."

# The body of the message that will be displayed after successful completion.
SUCCESS_MESSAGE="Thank you! Your FileVault key has been changed."

# The body of the message that will be displayed if a failure occurs.
FAIL_MESSAGE="Sorry, an error occurred while changing your FileVault key. Please contact $IT_CONTACT_FULL for assistance."


###############################################################################
######################### DO NOT EDIT BELOW THIS LINE #########################
###############################################################################

# applescript
#
# template:
########### Title - "$2" ############
#                                   #
#     Text to display - "$1"        #
#                                   #
#      [Default response - "$5"]    #
#                                   #
#               (B1 "$3") (B2 "$4") # <- Button 2 default
#####################################

function simpleInput() {
osascript <<EOT
tell app "System Events" 
with timeout of 2700 seconds
text returned of (display dialog "$1" default answer "$5" buttons {"$3", "$4"} default button 2 with title "$2")
end timeout
end tell
EOT
}

function simpleInputNoCancel() {
osascript <<EOT
tell app "System Events"
with timeout of 2700 seconds
text returned of (display dialog "$1" default answer "$4" buttons {"$3"} default button 1 with title "$2")
end timeout
end tell
EOT
}

function hiddenInput() {
osascript <<EOT
tell app "System Events" 
with timeout of 2700 seconds
text returned of (display dialog "$1" with hidden answer default answer "" buttons {"$3", "$4"} default button 2 with title "$2")
end timeout
end tell
EOT
}

function hiddenInputNoCancel() {
osascript <<EOT
tell app "System Events" 
with timeout of 2700 seconds
text returned of (display dialog "$1" with hidden answer default answer "" buttons {"$3"} default button 1 with title "$2")
end timeout
end tell
EOT
}

function OneButtonInfoBox() {
osascript <<EOT
tell app "System Events"
with timeout of 2700 seconds
button returned of (display dialog "$1" buttons {"$3"} default button 1 with title "$2")
end timeout
end tell
EOT
}

function TwoButtonInfoBox() {
osascript <<EOT
tell app "System Events"
with timeout of 2700 seconds
button returned of (display dialog "$1" buttons {"$3", "$4"} default button 2 with title "$2")
end timeout
end tell
EOT
}

function listChoice() {
osascript <<EOT
tell app "System Events"
with timeout of 2700 seconds
choose from list every paragraph of "$5" with title "$2" with prompt "$1" OK button name "$4" cancel button name "$3"
end timeout
end tell
EOT
}

######################## VALIDATION AND ERROR CHECKING ########################

# Suppress errors for the duration of this script. (This prevents JAMF Pro from
# marking a policy as "failed" if the words "fail" or "error" inadvertently
# appear in the script output.)
exec 2>/dev/null

BAILOUT=false

# Make sure we have root privileges (for fdesetup).
if [[ $EUID -ne 0 ]]; then
    REASON="This script must run as root."
    BAILOUT=true
fi

# Check for remote users.
REMOTE_USERS=$(/usr/bin/who | grep -Eo '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | wc -l)
if [[ $REMOTE_USERS -gt 0 ]]; then
    REASON="Remote users are logged in."
    BAILOUT=true
fi

# Most of the code below is based on the JAMF reissueKey.sh script:
# https://github.com/JAMFSupport/FileVault2_Scripts/blob/master/reissueKey.sh

# Check the OS version.
OS_MAJOR=$(/usr/bin/sw_vers -productVersion | awk -F . '{print $1}')
OS_MINOR=$(/usr/bin/sw_vers -productVersion | awk -F . '{print $2}')
if [[ "$OS_MAJOR" -eq 10 && "$OS_MINOR" -lt 13 ]]; then
    REASON="This script requires macOS 10.13 or higher. This Mac has $(sw_vers -productVersion)."
    BAILOUT=true
elif [[ "$OS_MAJOR" -eq 10 && "$OS_MINOR" -eq 13 ]]; then
    echo "[WARNING] This script has not been tested with macOS 10.13, but should work."
fi

# Check to see if the encryption process is complete
FV_STATUS="$(/usr/bin/fdesetup status)"
if grep -q "Encryption in progress" <<< "$FV_STATUS"; then
    REASON="FileVault encryption is in progress. Please run the script again when it finishes."
    BAILOUT=true
elif grep -q "FileVault is Off" <<< "$FV_STATUS"; then
    REASON="Encryption is not active."
    BAILOUT=true
elif ! grep -q "FileVault is On" <<< "$FV_STATUS"; then
    REASON="Unable to determine encryption status."
    BAILOUT=true
fi

# Get the logged in user's name
CURRENT_USER=$( scutil <<< "show State:/Users/ConsoleUser" | awk -F': ' '/[[:space:]]+Name[[:space:]]:/ { if ( $2 != "loginwindow" ) { print $2 }}' )

# Make sure there's an actual user logged in
if [[ -z $CURRENT_USER || "$CURRENT_USER" == "root" ]]; then
    REASON="No user is currently logged in."
    BAILOUT=true
else
    # Make sure logged in account is already authorized with FileVault 2
    FV_USERS="$(/usr/bin/fdesetup list)"
    if ! egrep -q "^${CURRENT_USER}," <<< "$FV_USERS"; then
        REASON="$CURRENT_USER is not on the list of FileVault enabled users: $FV_USERS"
        BAILOUT=true
    fi
fi

# If specified, the FileVault key redirection profile needs to be installed.
escrowProfileInstalled=$(profiles show |grep Escrow)
if [[ -z $escrowProfileInstalled ]]; then
    REASON="Filevault Escrow Profile is not yet installed."
    BAILOUT=true
fi

################################ MAIN PROCESS #################################

# If any error occurred in the validation section, bail out.
if [[ "$BAILOUT" == "true" ]]; then
    echo "[ERROR]: $REASON"
    OneButtonInfoBox \
        "$FAIL_MESSAGE: $REASON" \
        "$PROMPT_TITLE" \
        "OK" &
    exit 1
fi

# Display a branded prompt explaining the password prompt.
echo "Alerting user $CURRENT_USER about incoming password prompt..."
OneButtonInfoBox \
    "$PROMPT_MESSAGE" \
    "$PROMPT_TITLE" \
    "Next"

# Get the logged in user's password via a prompt.
echo "Prompting $CURRENT_USER for their Mac password..."
USER_PASS="$(hiddenInput \
    "Please enter the password you use to log into your mac:" \
    "$PROMPT_TITLE" \
    "Cancel" \
    "OK" )"
if [[ "$USER_PASS" =~ "false" ]]; then
    echo "User chose to cancel, exiting"
    exit 0
fi

# Thanks to James Barclay (@futureimperfect) for this password validation loop.
TRY=1
until /usr/bin/dscl /Search -authonly "$CURRENT_USER" "$USER_PASS" &>/dev/null; do
    (( TRY++ ))
    echo "Prompting $CURRENT_USER for their Mac password (attempt $TRY)..."
    USER_PASS="$(hiddenInput \
        "Sorry, that password was incorrect. Please try again:" \
        "$PROMPT_TITLE" \
        "Cancel" \
        "OK" )"
        if [[ "$USER_PASS" =~ "false" ]] || [[ -z "$USER_PASS" ]]; then
            echo "User chose to cancel, exiting"
            exit 0
        fi
    if (( TRY >= 5 )); then
        echo "[ERROR] Password prompt unsuccessful after 5 attempts. Displaying \"forgot password\" message..."
        OneButtonInfoBox \
            "$FORGOT_PW_MESSAGE" \
            "$PROMPT_TITLE" \
            "OK" &
        exit 1
    fi
done
echo "Successfully prompted for Mac password."

# If needed, unload and kill FDERecoveryAgent.
if /bin/launchctl list | grep -q "com.apple.security.FDERecoveryAgent"; then
    echo "Unloading FDERecoveryAgent LaunchDaemon..."
    /bin/launchctl unload /System/Library/LaunchDaemons/com.apple.security.FDERecoveryAgent.plist
fi
if pgrep -q "FDERecoveryAgent"; then
    echo "Stopping FDERecoveryAgent process..."
    killall "FDERecoveryAgent"
fi

# Translate XML reserved characters to XML friendly representations.
USER_PASS=${USER_PASS//&/&amp;}
USER_PASS=${USER_PASS//</&lt;}
USER_PASS=${USER_PASS//>/&gt;}
USER_PASS=${USER_PASS//\"/&quot;}
USER_PASS=${USER_PASS//\'/&apos;}

# For 10.13's escrow process, store the last modification time of /var/db/FileVaultPRK.dat
if [[ "$OS_MINOR" -ge 13 ]] || [[ "$OS_MAJOR" -eq 11 ]]; then
    echo "Checking for /var/db/FileVaultPRK.dat on macOS 10.13+..."
    PRK_MOD=0
    if [ -e "/var/db/FileVaultPRK.dat" ]; then
        echo "Found existing personal recovery key."
        PRK_MOD=$(/usr/bin/stat -f "%Sm" -t "%s" "/var/db/FileVaultPRK.dat")
    fi
fi

echo "Issuing new recovery key..."
FDESETUP_OUTPUT="$(/usr/bin/fdesetup changerecovery -norecoverykey -verbose -personal -inputplist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Username</key>
    <string>$CURRENT_USER</string>
    <key>Password</key>
    <string>$USER_PASS</string>
</dict>
</plist>
EOF
)"

# Test success conditions.
FDESETUP_RESULT=$?

# Clear password variable.
unset USER_PASS

# Check new modification time of of FileVaultPRK.dat
ESCROW_STATUS=1
if [ -e "/var/db/FileVaultPRK.dat" ]; then
    NEW_PRK_MOD=$(/usr/bin/stat -f "%Sm" -t "%s" "/var/db/FileVaultPRK.dat")
    if [[ $NEW_PRK_MOD -gt $PRK_MOD ]]; then
        ESCROW_STATUS=0
        echo "Recovery key updated locally and available for collection via MDM. (This usually requires two 'jamf recon' runs to show as valid.)"
        if [[ -e /usr/loca/bin/jamf ]]; then
            jamf recon &
        fi
    else
        echo "[WARNING] The recovery key does not appear to have been updated locally."
    fi
fi

if [[ $FDESETUP_RESULT -ne 0 ]]; then
    [[ -n "$FDESETUP_OUTPUT" ]] && echo "$FDESETUP_OUTPUT"
    echo "[WARNING] fdesetup exited with return code: $FDESETUP_RESULT."
    echo "See this page for a list of fdesetup exit codes and their meaning:"
    echo "https://developer.apple.com/legacy/library/documentation/Darwin/Reference/ManPages/man8/fdesetup.8.html"
    echo "Displaying \"failure\" message..."
    OneButtonInfoBox \
        "$FAIL_MESSAGE: fdesetup exited with code $FDESETUP_RESULT. Output: $FDESETUP_OUTPUT" \
        "$PROMPT_TITLE" \
        "OK"
elif [[ $ESCROW_STATUS -ne 0 ]]; then
    [[ -n "$FDESETUP_OUTPUT" ]] && echo "$FDESETUP_OUTPUT"
    echo "[WARNING] FileVault key was generated, but escrow cannot be confirmed. Please verify that the redirection profile is installed and the Mac is connected to the internet."
    echo "Displaying \"failure\" message..."
    OneButtonInfoBox \
        "$FAIL_MESSAGE: New key generated, but escrow did not occur." \
        "$PROMPT_TITLE" \
        "OK"
else
    [[ -n "$FDESETUP_OUTPUT" ]] && echo "$FDESETUP_OUTPUT"
    echo "Displaying \"success\" message..."
    OneButtonInfoBox \
        "$SUCCESS_MESSAGE" \
        "$PROMPT_TITLE" \
        "OK"
fi

exit $FDESETUP_RESULT
