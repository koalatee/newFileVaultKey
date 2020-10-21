# Reissuing FileVault keys 

_This is taken from the work of Elliot Jordan [homebysix/jss-filevault-reissue](https://github.com/homebysix/jss-filevault-reissue)_

---

I rewrote this as part of re-writing most all of my scripts from bash to zsh. 
This scripts works on macOS 10.15 and macOS 11 (confirmed with jamf + jamf built-in escrow profile) but should work with other MDM or custom profile that uses the com.apple.security.FDERecoveryKeyEscrow payload

This can be run from your Self Service application of choice, or from terminal. 

The only "requirements" are:
1. 10.13+ with an escrow profile in place 
2. A PPPC profile to allow Terminal to have access to "System Events" (for prompts/notifications)

---

There are many ways to determine necessity in jamf alone, so I leave that to you. 
For ideas, check out the original [homebysix/jss-filevault-reissue](https://github.com/homebysix/jss-filevault-reissue) or ask in macadmins slack

I have a script that checks [filevault and writes to a jamf EA](https://github.com/koalatee/scripts/blob/master/jamf/EAs/EA-AccurateFilevaultReporting.zsh) for more accurate reporting
