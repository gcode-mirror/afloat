# Introduction #

Recent versions of Mac OS X have introduced restrictions on "unusual" code injection paths, such as mach\_inject. The mach\_inject framework (especially mach\_inject\_bundle) is used by new versions of Afloat.

Only Afloat "beta 4" and later versions are affected. Afloat "beta 3" uses a less-featured code injection path that is not subject to security restrictions.


# Technical Details #

The mach\_inject framework uses Mach APIs to manipulate other running processes. Starting from recent versions of Tiger for Intel-based Macs, only processes belonging to root or to the procmod group (GID 9) can use these APIs.

Afloat adopts a setuid binary (the Agent executable) to work around the restriction. This means that the user must be root or have administrator credentials (as given by the Security Server) so that the setuid bit can be placed on the Agent in the very first place. [This link holds the rationale behind the decision](http://0xced.blogspot.com/2006/06/machinject-procmod-group-and-security.html) (and explains why the other possible method, adding the user to the procmod group, lowers security and should not be used).

The Preference Pane shows a notice, once installed, that prompts the user for authorization. The user is also prompted every time the user tries to enable Afloat but the Agent executable does not have the setuid bit or the correct group set.

You can also manually authorize the Agent by using the following command on a command line:

```
sudo "~/Library/PreferencePanes/Afloat.prefPane/Contents/Resources/Afloat Agent.app/Contents/MacOS/Afloat Agent" --Afloat-Authorize
```

The preference pane only requires authorization on the following platforms:
  * Mac OS X 10.4.4 and later on Intel-based Macs; or
  * Mac OS X 10.5 on both Intel-based and PowerPC-based Macs.

Note that the 10.5 part is speculative, since I can't test it.

# Issues #

The Afloat Agent becomes a setgid binary that is writable by the user.  Currently, the permissions are 02755, but I'm planning to make them 02555 (-r-xr-tr-x); note that, since the user remains the owner, the permissions can be reset easily. The alternative would be to give root ownership of the Agent, but Afloat can still be tricked into executing a binary with root privileges by replacing the Agent.

The rationale behind the lax security is, code must be running on the system for the issue to be exploited. If code is running on an OS X system, all bets are off -- there are easier, less tricky ways to gain elevated access and Afloat won't ask for reauthorization for an already-authorized Agent. Afloat may begin checking the Agent's integrity if this becomes an important issue.