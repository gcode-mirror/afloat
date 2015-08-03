# Introduction #

This article tells how exactly does Afloat work, what its structure is and how it injects (or not) code into foreign
applications.


# Details #

Afloat is composed by three modules that work in unison; these modules are the ''preference pane'', the ''agent'' and
the ''payload''.

The preference pane is Afloat's most visible UI. The two other components are found inside its bundle and therefore
are removed when the bundle is removed (usually by the built-in "Remove Preference Pane" option of System
Preferences). The prefpane's responsibilites include the starting up and closing of the agent, and ensuring the agent
starts up (or not) when the user logs in by modifying the Login Items list for that user (this is done via the AELI...
functions found inside LoginItemsAE at http://developer.apple.com/samplecode/LoginItemsAE/index.html by
Apple).

The agent is an application built around `mach_inject` and specifically `mach_inject_bundle`. To ensure some
degree of
stability, a precompiled Universal (ppc+i386) version of `mach_inject_bundle.framework` is included into the SVN
repository. At runtime, the agent observes NSWorkspace notifications about new applications being launched and
will then retrieve their PID and inject the payload into them. The agent also injects the payload in all running
applications when it first starts up, but uses a slightly more complex procedure to do so:

  * The agent starts up and sends a distributed kAfloatRollCallNotification which can be "heard" by all public
processes.
  * The agent sets a timer for one second into the future, to allow other applications to intercept and respond to its
notification.
  * In this meanwhile, applications in which the payload is loaded will trigger code that will resend a "response"
distributed kAfloatAlreadyLoadedNotification. The userInfo of this notification includes the application's identifiers.
  * The agent will intercept and respond to "already loaded" notifications by adding the identifiers to a "do not load"
list.
  * When the timer finally fires, the agent gets a list of all loaded applications and loads the payload onto each of
them. If an application is in the "do not load" list, it will be skipped.

This prevents the payload from being loaded more than once into the same application. This check is only done at
startup, as the agent assumes that new applications do not have Afloat loaded into them.

The agent also vends a Distributed Objects proxy object with identifier `net.infinite-labs.Afloat.DO`. This object is
used by the preference pane to ask the Agent to shut down and ensure it really has (and send a SIGKILL to it if it
hasn't).

The payload contains the actual implementation of Afloat. It has a "hub", a centerpoint written in Cocoa that
manipulates abstract "window" objects (of type `id`), and can contain one or more implementations (as of [r31](https://code.google.com/p/afloat/source/detail?r=31),
only one Cocoa implementation) that provides the hub with the window objects (which must conform to an informal
protocol) and additional information to the hub. The feature are mostly written in a toolkit-independent form in the
hub, while the implementation translates the commands from the hub into Cocoa or Carbon calls as needed. (Of
course all of this was done to support Carbon in the future.) The implementation also handles roll call notifications
at the moment. This division still requires that some Cocoa machinery be working in order to work even in Carbon
apps (for example, Cocoa UI NSWindows must be displayable and working in the application, or the Adjust Effects
panel will not work).