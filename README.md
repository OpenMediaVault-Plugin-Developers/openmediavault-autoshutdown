debian-autoshutdown plugin
==================================

This is a fork from the awesome openmediavault-auotshutdown-plugin
-------------------------------------------------------------------
I do not take any credit for the work, I just try and make it usable on a standard Debian/Ubuntu System.
Pleas go check them out [here](https://github.com/OpenMediaVault-Plugin-Developers/openmediavault-autoshutdown)


Installation
------------
There are 3 ways how you can install this on your machine:
1. curl one-line command
2. download install script
3. clone git-repo

### One-Line-Command
just copy and paste this to your terminal everything is done for you. 

`curl -sSL https://raw.githubusercontent.com/mnul/debian-autoshutdown/master/install.sh | sudo bash`

### Download and install script

tbd.

### clone git repo

tbd.



Original README.md
-------------------

__Bugs reports:__  Please provide a _full_ verbose or FAKE-Mode log with the
git issue.


How it works:
-------------
The Autoshutdown script checks the status of the network and the server. A set
of check in the script are known as a "cycle". Between the cycles the script
goes into sleep for x seconds. The checks run on the system have a different
priority from 0 = highest to 6 = lowest:

0. Stay up-range: UPHOURS (Server in the time range, where it should be online)
1. Check for active IPs over network interfaces
2. Ports (Network sockets) over network interfaces  
   Ports (Docker host ports)  
   Check for logged in user  
   Samba status check  
3. UL/DL-Rate in kB/s over active network interfaces
4. HDD IO rate check in kB/s  
   Check if S.M.A.R.T tests are running  
5. Check for active processes
6. Check for user plugins

If a check with a higher priority gives back a positive result, then no check
with a lower priority is executed. The script reduces the cycles by one and
goes to sleep for x seconds until the next cycle. If all cycles are 0 (zero)
the server is shutdown.

Let's have a look at a simple example:

    --- autoshutdown.conf ---
    ENABLE=true
    CYCLES=4
    SLEEP=180
    RANGE="5..100"
    CHECKCLOCKACTIVE="true"
    UPHOURS="06:00..20:00"
    NSOCKETNUMBERS="21,22,80,3689,6991,9091,49152"
    ULDLCHECK="true"
    ULDLRATE=50
    LOADAVERAGECHECK="true"
    LOADAVERAGE=40
    SYSLOG="true"
    VERBOSE="false"
    FAKE="false"
    TEMPPROCNAMES="-"

It is 10:00 am. Autoshutdown does the first check:

__Prio 0:__ UPHOURS  
They are set to "06:00..20:00" which means 06:00 - 20:00 (6am to 8pm). No
further checks needed, the script sleeps until 8pm.

It is 20:01 (8:01pm) now and Autoshutdown does further checks:

__Prio 1:__ IPs  
Let's assume, that only IP 137 is online, so the check is negative, next check.

__Prio 2:__ Ports  
Let's assume, that there is no connection on any port to watch. The check is
negative, next check.

__Prio 3:__ UL/DL-Rate  
Maybe a DL is running with 238 kB/s over the last minute. The check is
positive, no more checks needed.
Autoshutdown goes to sleep for x seconds.

__Prio 4 and 6:__  
Not needed, because a check with a higher priority is positive.


Configuration options details:
------------------------------
For details of what value should be set in the autoshutdown.conf, and there
meaning, see [autoshutdown.default](https://github.com/OpenMediaVault-Plugin-Developers/openmediavault-autoshutdown/blob/master/etc/autoshutdown.default)


Exit code details:
-------------------
0 - Script completed successfully.  
142 - Shutdown mechanism failed to run correctly.  
141 - Initialisation failed for a component.  
140 - Invalid configuration value where no default is available.  
139 - A required configuration file was not found.  
138 - No valid network interface found on system.
