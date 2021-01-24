openmediavault-autoshutdown plugin
==================================

__Bugs and feature-requests:__  
Please provide a _full_ DEBUG- or FAKE-Mode-log with the git issue.


How it works:
-------------
Autoshutdown, does some checks on the network or on the server itself. A
"cycle" is a set of checks. Between the cycles goes into sleep for x
seconds. The checks have a different priority from 0 = high to 6 = low:

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
the server is shutting down.

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

Prio 0: UPHOURS  
They are set to "06:00..20:00" which means 06:00 - 20:00 (6am to 8pm). No
further checks needed, the script sleeps until 8pm.

It is 20:01 (8:01pm) now and Autoshutdown does further checks:

Prio 0: UPHOURS  
The server is not in the (forced) stay-up-range (06::00..20:00) => negative, next check

Prio 1: IPs  
Let's assume, that only IP 137 is online, so the check is negative, next check

Prio 2: Ports  
Let's assume, that there is no connection on any port to watch. The check is negative, next check

Prio 3: UL/DL-Rate  
Maybe a DL is running with 238 kB/s over the last minute. The check is positive, no more checks needed.
Autoshutdown goes to sleep for x seconds.

Prio 4 and 6:  
Not needed, because a check with a higher priority is positive


Meaning of configuration setting:
---------------------------------
For details of what value should be set in the autoshutdown.conf, and there
meaning, see [autoshutdown.default](https://github.com/OpenMediaVault-Plugin-Developers/openmediavault-autoshutdown/blob/master/etc/autoshutdown.default)


Exit codes and meanings:
------------------------
0 - Script completed successfully.  
142 - Shutdown mechanism failed to run correctly.  
141 - Initialisation failed for a component.  
140 - Invalid configuration value where no default is available.  
139 - A required configuration file was not found.  
138 - No valid network interface found on system.
