Prism Venues — Windows
======================

Venue audio control. Requires 64-bit Windows 10 or 11. Nothing else needs
installing: the Flutter runtime and the sound engine are both inside this
folder.


Install
-------

1. Extract this whole folder somewhere (Downloads is fine).
2. Double-click  Install.cmd
3. Launch "Prism Venues" from the Start Menu or the desktop.

It installs for your user account only, into

    %LOCALAPPDATA%\Programs\PrismVenues

so it needs no administrator rights and shows no UAC prompt. Running
Install.cmd again upgrades in place.

Prefer not to install? Double-click "Run without installing.cmd" instead. It
runs straight out of this folder and writes nothing outside the app's own data
directory.


"Windows protected your PC"
---------------------------

Expected. The build is not code-signed, so SmartScreen warns about it the first
time. Click "More info", then "Run anyway".

The only way to remove that warning is an Authenticode certificate from a
certificate authority (roughly $200-400/year), applied with signtool.exe to
prism_venues.exe and to the installer.


Signing in
----------

The app talks to the hosted backend; the URL is compiled in. All you need is an
account — an email and a password. There is no server to run and nothing to
configure on this machine.

If sign-in fails, check the machine has internet access. There is no offline
mode.


Uninstall
---------

Settings > Apps > Installed apps > Prism Venues > Uninstall.
Or double-click Uninstall.cmd in this folder.

Your saved sign-in and preferences are left behind on purpose, so a reinstall
does not sign you out. To clear them too, delete:

    %APPDATA%\com.example\prism_venues


If something looks wrong
------------------------

App opens but there is no sound
    Check prism_core.dll sits next to prism_venues.exe in the app folder. That
    file is the sound engine; the dashboard works without it, silently.

App opens but there is no data
    A network or sign-in problem, not an install problem. The app needs to
    reach the backend over HTTPS.

Install.cmd flashes and closes
    Right-click it and choose Run as administrator once — some machines have a
    policy that blocks scripts for standard users.
