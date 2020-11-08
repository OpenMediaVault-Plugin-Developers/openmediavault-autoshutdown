Autoshutdown-Script for OMV, Debian and Ubuntu:
-----------------------------------------------

__Bugs and feature-requests:__  
Please provide a _full_ DEBUG- or FAKE-Mode-log with the git issue.


How it works:
-------------
Autoshutdown, later called "ASD" does some checks on the network or on the server itself.

A "cycle" is a set of checks. Between the cycles ASD goes into sleep for x seconds.

The checks have a different priority from 0 = high to 5 = low:
0: Stayup-range: UPHOURS (is the server in the timerange, where it should stay online)

1. IPs
2. Ports (Network sockets)
3. UL/DL-Rate in kB/s (only over the last minute)
4. processes, daemons
5. ASD-plugins

If a check with a higher priority gives back a positive result, then no check
with a lower priority is executed. The script reduces the cycles by one and goes
to sleep for x seconds until the next cycle. If all cycles are 0 (zero) the
server is shutting down.

Let's have a look at a example:

    --- autoshutdown.conf ---
    ENABLE=true
    CYCLES=4
    SLEEP=180
    RANGE="5..100"
    CHECKCLOCKACTIVE="true"
    UPHOURS="6..20"
    NSOCKETNUMBERS="21,22,80,139,445,3689,6991,9091,49152"
    ULDLCHECK="true"
    ULDLRATE=50
    LOADAVERAGECHECK="true"
    LOADAVERAGE=30
    SYSLOG="true"
    VERBOSE="false"
    FAKE="false"
    TEMPPROCNAMES="-"

It is 10:00 am. ASD does the first check:

Prio 0: UPHOURS  
They are set to "6..20" which means 06:00 - 08:00 (6am to 8pm). No further checks needed, the script sleeps until 8pm.

It is 20:01 (8:01pm) now and ASD does further checks:

Prio 0: UPHOURS  
The server is not in the (forced) stayup-range (6..20) => negative, next check

Prio 1: IPs  
Let's assume, that only IP 137 is online, so the check is negative, next check

Prio 2: Ports  
Let's assume, that there is no connection on any port to watch. The check is negative, next check

Prio 3: UL/DL-Rate  
Maybe a DL is running with 238 kB/s over the last minute. The check is positive, no more checks needed.
ASD goes to sleep for x seconds.

Prio 4 and 5:  
not needed, because a check with a higher priority is positive


Expert Settings in autoshutdown.conf: (set it in "Expert settings" in the OMV-GUI)
-------------------------------------
__LOADPROCNAMES__  
Command names of processes with load dependent children to check if they have something to do
checked by default="proftpd,smbd,nfsd,transmission-daemon,mt-daapd,forked-daapd")

__TEMPPROCNAMES__  
Command names of processes only started when active
checked with "top" AND "ps", so all processes are found, even such, which doesn't show up in top
like "lftp" - Beware: If the process shows up in "ps" when there is no connection, your PC won't shutdown!
maybe you have to call the process like this: "lftp -do -something -here && exit"
checked by default="in.tftpd")

if you want other processes than the default ones, please uncomment the above lines and add your process at the end of the line
to disable the process-check, set LOADPROCNAMES="-" or TEMPPROCNAMES="-"

The following scheme is mandatory for both LOADPROCNAMES and TEMPPROCNAMES:  
process1,process2 
All processes separated by comma ','

__HDDIOCHECK__  
Set this to "true" and the script checks, if a HDD-IO (read/write) is over a defined value in kB/s (default: HDDIO_RATE=400)
and then don't shutdown the Server. This value is calculated with the SLEEP-time between every cycle of the script-checks.
E.g.: You have defined HDDIO_RATE=2000 and SLEEP=100, then the HDD-IO (read or write) has to be over 200000kB (2000*100) within the
last 100 sec to not shutdown the server.

__PINGLIST__  
With this, you can define a path to a file, which contains list of IPs that should be scanned
only one IP per line is allowed - Format: mmm.nnn.ooo.ppp e.g.: 192.168.1.45
If this expert-setting is used, the IPs specified in "RANGE" or in GUI doesn't work

__PLUGINCHECK__  
Set this to true, if autoshutdown.sh checks for PlugIns in /etc/autoshutdown.d
set it to "false" (or commented) to skip the check

E.g.: When ClamAV does a check, the Server shouldn't shut down. How to do that?
Let's look at a example: in the clamav-plugin for autoshutdown (etc/autoshutdown.d/clamav) the following is set:

    # In which folder is the file to look for
    folder="/var/run/clamav"
    # filename (can be expanded with regexes)
    file="clamdscan-[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}"

Then, if a file i.e.: clamdscan-aaaa3556-adfe-5678-abcdef012345 (or whatever UUID) in /var/run/clamav exists, the Server isn't shutdown

also possible:
    folder="/home/user"
    file="backup.status"
    content="processing job"

If a file /home/user/backup.status exists with the content 'processing job', the Server isn't shutdow
This is useful for backupscripts. It is not nice if the PC is shutting down while the backup-script is running.
In my backup-script i use a simple

    echo "processing job" > /home/user/backup.status

at the beginning and a

    rm /home/user/backup.status

at the end of the script. In the boot-Phase also a

    rm /home/user/*.status

to delete all *.status files, which are not deleted before (loss of power for example)

Please have a look at the two example files in /etc/autoshutdown.d

__FORCE_NIC__  
e.g. FORCE_NIC="eth1" forces autoshutdown to look for a IP first in the given device, after that all others are checked.
