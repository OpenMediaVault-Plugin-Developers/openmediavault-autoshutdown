#!/bin/bash

#=======================================================================
#
#          FILE:	autoshutdown.sh
#
#         USAGE:	copy this script to /usr/sbin and the config-file to /etc
#
#   DESCRIPTION:	shuts down a PC/Server - variable options
#
#  REQUIREMENTS:  	Debian / Ubuntu-based system
#
#          BUGS:  	if you find any: https://github.com/OpenMediaVault-Plugin-Developers/openmediavault-autoshutdown
#
#        AUTHOR:	Solo0815 - R. Lindlein (Ubuntu-Port, OMV-Changes), it should work on any Debain-based System, too
#					based on autoshutdown.sh v0.7.008 by chrikai, see:
#					https://sourceforge.net/apps/phpbb/freenas/viewtopic.php?f=12&t=2158&start=60
#=======================================================================

# Changelog:	see extra file!

######## VARIABLE DEFINITION ########
RESULT=0               # declare reusable RESULT variable to check function return values

# Variables that normal users should normaly not define - PowerUsers can do it here or add it to the config
LPREPEAT=5         	# number of test cycles for finding and active LOADPROCNAMES-Process (default=5)
TPREPEAT=5         	# number of test cycles for finding and active TEMPPROCNAMES-Process (default=5)

LOGGER="/usr/bin/logger"  	# path and name of logger (default="/usr/bin/logger")
FACILITY="local6"         	# facility to log to -> see rsyslog.conf

							# for a separate Log:
							# Put the file "autoshutdownlog.conf" in /etc/rsyslog.d/

######## CONSTANT DEFINITION ########
VERSION="0.9.9.10"        	 # script version information
#CTOPPARAM="-d 1 -n 1"         # define common parameters for the top command line "-d 1 -n 1" (Debian/Ubuntu)
CTOPPARAM="-b -d 1 -n 1"         # define common parameters for the top command line "-b -d 1 -n 1" (Debian/Ubuntu)
STOPPARAM="-i $CTOPPARAM"   # add specific parameters for the top command line  "-i $CTOPPARAM" (Debian/Ubuntu)

# tmp-directory
TMPDIR="/tmp/autoshutdown"

######## FUNCTION DECLARATION ########

################################################################
#
#   name      : _log
#   parameter   : $LOGMESSAGE : logmessage in format "PRIORITY: MESSAGE"
#   return      : none
#
_log()
{
	[[ "$*" =~ ^([A-Za-z]*):(.*) ]] &&
		{
			PRIORITY=${BASH_REMATCH[1]}
			LOGMESSAGE=${BASH_REMATCH[2]}
			[[ "$(basename "$0")" =~ ^(.*)\. ]] &&
			if $FAKE; then
				LOGMESSAGE="${BASH_REMATCH[1]}[$$]: $PRIORITY: 'FAKE-Mode: $LOGMESSAGE'";
			else
				LOGMESSAGE="${BASH_REMATCH[1]}[$$]: $PRIORITY: '$LOGMESSAGE'";
			fi;
		}

	if $VERBOSE||$FAKE; then echo "$(date '+%b %e %H:%M:%S'): $USER: $FACILITY $LOGMESSAGE"; fi

	[ $SYSLOG ] && $LOGGER -p $FACILITY.$PRIORITY "$LOGMESSAGE"
}

################################################################
#
#   name 		: _ping_range
#   parameter  	: none
#   return		: CNT   : number of active IP hosts within given IP range
#
_ping_range()
{
	NICNR_PINGRANGE="$1"
	PINGRANGECNT=0
	CREATEPINGLIST="false"

	# Create only one pinglist at script-start and not every function-call
	# If pinglist exists, don't create it
	if [ -z $USEOWNPINGLIST ]; then
		PINGLIST="$TMPDIR/pinglist"
		if [ ! -f "$PINGLIST" ]; then
			CREATEPINGLIST="true"
		fi
	fi

	if $DEBUG; then
		_log "DEBUG: _ping_range(): NICNR_PINGRANGE: $NICNR_PINGRANGE"
		_log "DEBUG: _ping_range(): PINGLIST: $PINGLIST"
		_log "DEBUG: _ping_range(): RANGE: '$RANGE'"
		_log "DEBUG: _ping_range(): CLASS: '${CLASS[${NICNR_PINGRANGE}]}'"
	fi
	# separate the IP end number from the loop counter, to give the user a chance to configure the search "algorithm"
	# COUNTUP = 1 means starting at the lowest IP address; COUNTUP=0 will start at the upper end of the given range
	for RG in ${RANGE//,/ } ; do

		if [[ ! "$RG" =~ \.{2} ]]; then

			FINIT="J=$RG"
			FORCHECK="J<=$RG"
			STEP="J++"

		elif [[ "$RG" =~ ^([0-9]{1,3})\.{2}([0-9]{1,3}$) ]]; then

			if [ ${BASH_REMATCH[2]} -gt ${BASH_REMATCH[1]} ]; then
				FINIT="J=${BASH_REMATCH[1]}"
				FORCHECK="J<=${BASH_REMATCH[2]}"
				STEP="J++"
			else
				FINIT="J=${BASH_REMATCH[1]}"
				FORCHECK="J>=${BASH_REMATCH[2]}"
				STEP="J--";
			fi   # > if [ ${BASH_REMATCH[2]} -gt ${BASH_REMATCH[1]} ]; then

		fi   # > if [[ "$RG" =~ [0-9]{1,3} ]]; then

		for (( $FINIT;$FORCHECK;$STEP )); do

			# If the pinglist is not created, create it with all IPs
			# don't add the ServerIP (OMV-IP) to the pinglist (grep -v)
			if $CREATEPINGLIST; then echo "${CLASS[$NICNR_PINGRANGE]}.$J" | grep -vw ${CLASS[$NICNR_PINGRANGE]}.${SERVERIP[$NICNR_PINGRANGE]} >> $PINGLIST; fi

		done   # > for (( J=$iSTART;$FORCHECK;$STEP )); do

	done   # > for RG in ${RANGE//,/ } ; do

	_log "INFO: retrieve list of active IPs for '${NIC[$NICNR_PINGRANGE]}' ..."

	# fping output 2> /dev/null suppresses the " ICMP Host Unreachable from 192.168.178.xy for ICMP Echo sent to 192.168.178.yz"
	if [ -f $PINGLIST ]; then
		FPINGRESULT="$(fping -a -r1 < "$PINGLIST" 2>/dev/null)"
	else
		_log "INFO: PINGLIST: $PINGLIST does not exist. Skip fpinging hosts"
	fi
	for ACTIVEPC in $FPINGRESULT; do
		_log "INFO: Found IP $ACTIVEPC as active host."
		let PINGRANGECNT++;
	done

	if [ -z "$FPINGRESULT" ]; then
		_log "INFO: No active IPs in the specified IP-Range found"
	fi

	return ${PINGRANGECNT};
}

################################################################
#
#   name      : _shutdown
#   parameter   : none
#   return      : none, script exit point
#
_shutdown()
{
   # Goodbye and thanks for all the fish!!
   # We've had no responses for the required number of consecutive scans
   # defined in CYCLES shutdown & power off.

	if [ -z "$SHUTDOWNCOMMAND" ]; then
		_log "INFO: No shutdown command set: setting it to 'shutdown -h now'"
		SHUTDOWNCOMMAND="shutdown -h now"
	fi

	# When FAKE-Mode is on:
	[[ "$FAKE" = "true" ]] && {
		logger -s -t "$USER - : autoshutdown [$$]" "INFO: Fake-Shutdown issued: '$SHUTDOWNCOMMAND' - Command is not executed because of Fake-Mode"
		# normal log-entry
		_log "INFO: Fake-Shutdown issued: '$SHUTDOWNCOMMAND'"
		_log "INFO: The autoshutdown-script will end here."
		_log "INFO:   "
		exit 0
		}

	# Without Fake-Mode:
	# This logs to normal syslog - "autoshutdown [" (the space) is necessary, because then all other logs can be filterd in rsyslog.conf with
	# :msg, contains, "autoshutdown[" /var/log/autoshutdown.log
	# & ~
	logger -s -t "$USER - : autoshutdown [$$]" "INFO: Shutdown issued: '$SHUTDOWNCOMMAND'"
	# normal log-entry
	_log "INFO: Shutdown issued: '$SHUTDOWNCOMMAND'"
	_log "INFO:   "
	_log "INFO:   "

	# write everything to disk/stick and shutdown, hibernate, $whatever is configured
	if sync; then eval "$SHUTDOWNCOMMAND" && exit 0; fi
	# sleep 5 minutes to allow the /etc/init.d/autoshutdown to kill the script and give the right log-message
	# if we exit here immediately, there are errors in the log
	sleep 5m
	# we need this just for debugging - the system should be shutdown here
	logger -s -t "$USER - : autoshutdown [$$]" "INFO: 5 minutes are over"
	sleep 5m
	logger -s -t "$USER - : autoshutdown [$$]" "INFO: another 5 minutes are over"
	exit 0
	}

################################################################
#
#   name      : _ident_num_proc
#   parameter : $1...$(n-1)    : parameter for command 'top'
#             : $n         : search pattern for command 'grep'
#   return    : $NUMOFPROCESSES
#
_ident_num_proc()
{
	# retrieve all function parameters for the top command; as we know the last command line parameter
	# is the pattern for the grep command, we can stop one parameter before the end
	[[ "$*" =~ (.*)\ (.*)\ (.*)$ ]] &&
		{
			TPPARAM=${BASH_REMATCH[1]}
			GRPPATTERN=${BASH_REMATCH[2]}
			CHECKPROCESS=${BASH_REMATCH[3]};
		}
	if $DEBUG ; then _log "DEBUG: _ident_num_proc(): top cmd line: $TPPARAM, grep cmd line: $GRPPATTERN, CHECKPROCESS: $CHECKPROCESS"; fi

	NUMOFPROCESSES=0
	NUMOFPROCESSES_PS=0
	NUMOFPROCESSES_TOP=0

	case $CHECKPROCESS in
		loadproc)
				if $DEBUG ; then _log "DEBUG: _ident_num_proc() loadproc: commandline: 'top ${TPPARAM} | grep -c ${GRPPATTERN}'"; fi
				# call top once, pipe the result to grep and count the number of patterns found
				# the number of found processes is returned to the callee
				NUMOFPROCESSES_TOP=$(top ${TPPARAM} | grep -c ${GRPPATTERN})
				;;

		tempproc)
				if $DEBUG ; then _log "DEBUG: _ident_num_proc() tempproc: commandline: 'top ${TPPARAM} | grep -c ${GRPPATTERN}'"; fi
				NUMOFPROCESSES_TOP=$(top ${TPPARAM} | grep -c ${GRPPATTERN})

				# If there is no process with top, maybe we find some with "ps", but not in in.tftpd
				if [ "$NUMOFPROCESSES_TOP" = 0 ]; then
					if [ "${GRPPATTERN}" != "in.tftpd" ]; then
						if $DEBUG ; then _log "DEBUG: _ident_num_proc() tempproc-ps: commandline: 'ps -ef | grep -c ${GRPPATTERN}'"; fi
						NUMOFPROCESSES_PS=$(ps -ef | grep -v grep | grep -c $GRPPATTERN)
					else
						if $DEBUG; then _log "INFO: Process = 'in.tftpd' - skipping 'ps'-check"; fi
					fi
				fi
				;;

		*)
				_log "ERROR: _ident_num_proc() This should not happen. Exit 42"
				;;
	esac

	let NUMOFPROCESSES=$NUMOFPROCESSES_PS+$NUMOFPROCESSES_TOP
	if $DEBUG; then
		_log "DEBUG: _ident_num_proc(): NUMOFPROCESSES_PS: $NUMOFPROCESSES_PS"
		_log "DEBUG: _ident_num_proc(): NUMOFPROCESSES_TOP: $NUMOFPROCESSES_TOP"
	fi

	return $NUMOFPROCESSES
}

################################################################
#
#   name         : _check_processes
#   parameter      : none
#   global return   : none
#   return    		: 0      : if no active process has been found
#               	: 1 or more      : if at least one active process has been found
#
_check_processes()
{
	# ## disabled for testing
	# _log "DEBUG: _check_processes() disabled for testing"
	# return 0

	NUMPROC=0
	CHECK=0

	# check for each given command name in LOADPROCNAMES if it is currently stated active in "top"
	# i found, that for smbd, proftpd, nsfd, ... there are processes always present in "ps" or "top" output
	# this could be due to the "daemon" mechanism... Only chance to identify there is something happening with these
	# processes, is to check if "top" states them active -> "-i" parameter on the command line
	for LPROCESS in ${LOADPROCNAMES//,/ } ; do
		LP=0
		IPROC=0
		for ((N=0;N < ${LPREPEAT};N++ )) ; do
			_ident_num_proc ${STOPPARAM} ${LPROCESS} loadproc
			RESULT=$?
			LP=$(($LP|$RESULT))
			[ $RESULT -gt 0 ] && let IPROC++
		done
		let NUMPROC=$NUMPROC+$LP

		if $DEBUG ; then
			{ [ $LP -gt 0 ] && _log "DEBUG: _check_processes(): Found active process $LPROCESS"; }
			_log "DEBUG: _check_processes(): > $LPROCESS: found $IPROC of $LPREPEAT cycles active"
		fi

	done   # > LPROCESS in ${LOADPROCNAMES//,/ } ; do

	if ! $DEBUG ; then { [ $NUMPROC -gt 0 ] && _log "INFO: Found $NUMPROC active processes in $LOADPROCNAMES" ; }; fi

	# check for each given command name in TEMPPROCNAMES if it is currently stated present in "top"
	# i found, that for sshd, ... there are processes only present in "ps" or "top" output when is is used.
	# it can not be guaranteed, that top states these services active, as they usually wait for user input
	# no "-I" parameter on the command line, but shear presence is enough
	for TPROCESS in ${TEMPPROCNAMES//,/ } ; do
		TP=0
		IPROC=0
		for ((N=0;N < ${TPREPEAT};N++ )) ; do
			_ident_num_proc ${CTOPPARAM} ${TPROCESS} tempproc
			RESULT=$?
			TP=$(($TP|$RESULT))
			[ $RESULT -gt 0 ] && let IPROC++
		done

		let CHECK=$CHECK+$TP

		if ! $DEBUG ; then { [ $TP -gt 0 ] && _log "INFO: _check_processes(): Found active process $TPROCESS"; }; fi

		if $DEBUG ; then _log "DEBUG: _check_processes(): > $TPROCESS: found $IPROC of $TPREPEAT cycles active"; fi

	done   # > for TPROCESS in ${TEMPPROCNAMES//,/ } ; do

	if ! $DEBUG ; then { [ $CHECK -gt 0 ] &&_log "INFO: Found $CHECK active processes in $TEMPPROCNAMES" ; }; fi

	let NUMPROC=$NUMPROC+$CHECK

	if $DEBUG ; then _log "DEBUG: _check_processes(): $NUMPROC process(es) active."; fi

	# only return we found a process
	return $NUMPROC

}


################################################################
#
#   name 			: _check_plugin
#   parameter		: none
#   global return   : none
#   return			: 0      : if file has not been found
#   				: 1      : if file has been found
#
# With this plugin-system everyone can check if a specific file exists.
# If it exists, the machine won't shutdown
# You find sample plugins in /etc/autoshutdown.d
#
_check_plugin()
{
	FOUNDVALUE_checkplugin=0
	RVALUE=0

	ASD_pluginNR=0
	for ASD_plugin in /etc/autoshutdown.d/*; do
		let ASD_pluginNR++

		PLUGIN_name[$ASD_pluginNR]="${ASD_plugin##*/}"
		PLUGIN_folder[$ASD_pluginNR]="$(egrep 'folder=' $ASD_plugin | sed 's/folder=//g; s/"//g')"
		PLUGIN_file[$ASD_pluginNR]="$(egrep 'file=' $ASD_plugin | sed 's/file=//g; s/"//g')"
		PLUGIN_content[$ASD_pluginNR]="$(egrep 'content=' $ASD_plugin | sed 's/content=//g; s/"//g')"

		if $DEBUG; then
			_log "DEBUG: -------------------------------------------"
			_log "DEBUG: _check_plugin(): PlugIn: ${PLUGIN_name[$ASD_pluginNR]}: ASD_PLUGIN-file: $ASD_plugin"
			_log "DEBUG: _check_plugin(): PlugIn: ${PLUGIN_name[$ASD_pluginNR]}: PLUGIN_name[$ASD_pluginNR]: ${PLUGIN_name[$ASD_pluginNR]}"
			_log "DEBUG: _check_plugin(): PlugIn: ${PLUGIN_name[$ASD_pluginNR]}: PLUGIN_folder[$ASD_pluginNR]: ${PLUGIN_folder[$ASD_pluginNR]}"
			_log "DEBUG: _check_plugin(): PlugIn: ${PLUGIN_name[$ASD_pluginNR]}: PLUGIN_file[$ASD_pluginNR]: ${PLUGIN_file[$ASD_pluginNR]}"
			if [ ! -z "${PLUGIN_content[$ASD_pluginNR]}" ]; then
				_log "DEBUG: _check_plugin(): PlugIn: ${PLUGIN_name[$ASD_pluginNR]}: PLUGIN_content[$ASD_pluginNR]: ${PLUGIN_content[$ASD_pluginNR]}"
			fi
		fi

		# When file exists (matches regex), no shutdown
		if [ "$(find ${PLUGIN_folder[$ASD_pluginNR]} -regextype posix-egrep -regex '.*'${PLUGIN_file[$ASD_pluginNR]} 2> /dev/null | wc -l)" -gt 0 ]; then

			# Check, if PLUGIN_content for the plugin is defined
			if [ ! -z "${PLUGIN_content[$ASD_pluginNR]}" ]; then

				# content found
				if [ $(egrep -c "${PLUGIN_content[$ASD_pluginNR]}" "${PLUGIN_folder[$ASD_pluginNR]}/${PLUGIN_file[$ASD_pluginNR]}") -gt 0 ]; then
					_log "INFO: _check_plugin(): PlugIn: ${PLUGIN_name[$ASD_pluginNR]} -> content found (${PLUGIN_content[$ASD_pluginNR]}) - no shutdown."
					let FOUNDVALUE_checkplugin++
				else
					# content not found
					_log "INFO: _check_plugin(): PlugIn: ${PLUGIN_name[$ASD_pluginNR]} -> content not found (${PLUGIN_content[$ASD_pluginNR]})"
				fi

			# content not defined and file found
			else
				_log "INFO: _check_plugin(): PlugIn: ${PLUGIN_name[$ASD_pluginNR]} -> File found - no shutdown."
				let FOUNDVALUE_checkplugin++
			fi
		else
			# If file doesn't exist -> shutdown
			_log "INFO: _check_plugin(): ${PLUGIN_name[$ASD_pluginNR]} - File not found"
		fi

		if $DEBUG ; then _log "DEBUG: _check_plugin(): ${PLUGIN_name[$ASD_pluginNR]} FOUNDVALUE_checkplugin: $FOUNDVALUE_checkplugin" ; fi

	done

	if $DEBUG ; then _log "DEBUG: _check_plugin(): All PlugIns processed - FOUNDVALUE_checkplugin: $FOUNDVALUE_checkplugin" ; fi

	if [ $FOUNDVALUE_checkplugin -gt 0 ]; then
		let RVALUE++
	fi
	if $DEBUG ; then _log "DEBUG: _check_plugin(): after all plugin-checks: RVALUE: $RVALUE" ; fi

	return ${RVALUE}
}


################################################################
#
#   name         : _check_loadaverage
#   parameter      : none
#   global return   : none
#   return         : 1      : if loadaverage is higher (greater) than $LOADAVERAGE, no shutdown
#               : 0      : if loadaverage is lower (less) than $LOADAVERAGE
#
# This script checks if the loadaverage is higher than $LOADAVERAGE over the last 1 minute
# if yes -> no shutdown, next cycle
# if no -> next check and shutdown if all cycles failed
#
_check_loadaverage()
{
	# ## disabled for testing
	# _log "DEBUG: _check_loadaverage() disabled for testing"
	# return 0

	RVALUE=0
	# grab first line, with the load averages; use C-locale to avoid internationalization issues
	CURRENT_LOAD_AVERAGE_LINE=$(LC_ALL=C top -b -n 1 | head -1)
	# grab first value, with the one-minute load average in decimal notation
	CURRENT_LOAD_AVERAGE_DECIMAL=$(echo $CURRENT_LOAD_AVERAGE_LINE | sed -E 's/.*load average: ([0-9.]+).*/\1/')
    # convert to integer value by removing decimal point and assuming two fixed decimal places;
    # for pretty display, remove leading zeros
    CURRENT_LOAD_AVERAGE=$(printf "%d" $(echo $CURRENT_LOAD_AVERAGE_DECIMAL | sed 's/[.]//'))

	if $DEBUG; then
		_log "DEBUG: -------------------------------------------"
		_log "DEBUG: _check_loadaverage(): First line of output from 'top' command:"
		_log "DEBUG: _check_loadaverage(): '$CURRENT_LOAD_AVERAGE_LINE'"
		_log "DEBUG: _check_loadaverage(): CURRENT_LOAD_AVERAGE_DECIMAL: $CURRENT_LOAD_AVERAGE_DECIMAL"
		_log "DEBUG: _check_loadaverage(): CURRENT_LOAD_AVERAGE: $CURRENT_LOAD_AVERAGE"
	fi

	if [ $CURRENT_LOAD_AVERAGE -gt $LOADAVERAGE ]; then
		_log "INFO: Load average ($CURRENT_LOAD_AVERAGE_DECIMAL -> $CURRENT_LOAD_AVERAGE) is higher than target ($LOADAVERAGE) - no shutdown"
		let RVALUE++
	else
		_log "INFO: Load average ($CURRENT_LOAD_AVERAGE_DECIMAL -> $CURRENT_LOAD_AVERAGE) is lower than target ($LOADAVERAGE)"
	fi

	if $DEBUG ; then _log "DEBUG: _check_loadaverage(): RVALUE: $RVALUE" ; fi

	return ${RVALUE}
}

################################################################
#
#   name         : _check_net_status
#   parameter      : Array-# of NIC
#   global return   : none
#   return         : 0      : if no active socket has been found, ready for shutdown
#                  : 1 or more      : if at least one active socket has been found, no shutdown
#
_check_net_status()
{
	# ## disabled for testing
	# _log "DEBUG: _check_net_status() disabled for testing"
	# return 0

	NUMPROC=0
	NICNR_NETSTATUS="$1"

	_log "INFO: Check Connections for '${NIC[${NICNR_NETSTATUS}]}'"

	# check for each given socket number in NSOCKETNUMBERS if it is currently stated active in "netstat"
	for NSOCKET in ${NSOCKETNUMBERS//,/ } ; do
		LP=0
		IPWORD="${CLASS[$NICNR_NETSTATUS]}.${SERVERIP[$NICNR_NETSTATUS]}:$NSOCKET"

		if $DEBUG ; then _log "DEBUG: _check_net_status(): ss -n | grep ESTAB | grep ${IPWORD}"; fi

		LINES=$(ss -n | grep ESTAB | grep ${IPWORD})

		if $DEBUG ; then _log "DEBUG: _check_net_status(): Result: $LINES"; fi # changed LINE in LINES

		#if $DEBUG ; then _log "DEBUG: _check_net_status(): echo ${LINES} | grep -c ${WORD2}"; fi

		# had to add [[:space:]] because without it, this command also wrong values are found:
		# searching for port 445 also finds port 44547
		RESULT=$(echo ${LINES} | egrep -c "${IPWORD}[[:space:]]")

		let NUMPROC=$NUMPROC+$RESULT

		if $DEBUG ; then _log "DEBUG: _check_net_status(): Is socket present: $RESULT"; fi

		# Check which IP is connected on the specified Port
		# old:
		# CONIP=$(netstat -an | grep ${WORD1} | echo ${WORD2} | awk '{print $5}'| sed 's/\.[0-9]*$//g' | uniq)

		[[ $(echo ${LINES} | awk '{print $6}') =~ (.*):[0-9]*$ ]] && CONIP=${BASH_REMATCH[1]}

		# Set PORTPROTOCOL - only default ports are defined here
		case $NSOCKET in
			80|8080) PORTPROTOCOL="HTTP" ;;
			22)    	PORTPROTOCOL="SSH" ;;
			21)  	PORTPROTOCOL="FTP" ;;
			139|445) PORTPROTOCOL="SMB/CIFS" ;;
			443)	PORTPROTOCOL="HTTPS" ;;
			548)	PORTPROTOCOL="AFP" ;;
			873)	PORTPROTOCOL="RSYNC" ;;
			3306)	PORTPROTOCOL="MYSQL" ;;
			3689)   PORTPROTOCOL="DAAP" ;;
			6991)   PORTPROTOCOL="BITTORRENT" ;;
			9091)   PORTPROTOCOL="BITTORRENT_WEBIF" ;;
			49152)  PORTPROTOCOL="UPNP" ;;
			51413)	PORTPROTOCOL="BITTORRENT" ;;
			*)      PORTPROTOCOL="unknown" ;;
		esac

		if [ $RESULT -gt 0 ]; then _log "INFO: _check_net_status(): Found active connection on port $NSOCKET ($PORTPROTOCOL) from $CONIP"; fi

	done   # > NSOCKET in ${NSOCKETNAMES//,/ } ; do

	# Extra Check for connected users on the CLI if other processes are negative -> [ $NUMPROC -eq 0 ]
	if [ $NUMPROC -eq 0 ]; then
        if [ "$CHECK_CLI" = "true" ]; then
            # 'w -h' lists all connected users
            # egrep -v '^\s*$' removes all empty lines
            USERSCONNECTED="$(w -h | egrep -v '^\s*$')"

            if $DEBUG; then _log "DEBUG: _check_net_status(): USERSCONNECTED: '$USERSCONNECTED'"; fi

            if [ $(echo "$USERSCONNECTED"  | egrep -v '^\s*$' | wc -l) -gt 0 ]; then
                _log "INFO: There is a user (locally) connected -> no shutdown"
                ASD_CONNECTED_USER=$(echo "$USERSCONNECTED" | awk '{print $1}')
                ASD_CONNECTED_FROM=$(echo "$USERSCONNECTED" | awk '{print $3}')
                # Check, if it is a local user
                [[ "$ASD_CONNECTED_FROM" =~ ^.*:.*$ ]] && ASD_CONNECTED_FROM=$(echo "$USERSCONNECTED" | awk '{print $2}')

                _log "INFO: It is '$ASD_CONNECTED_USER' on/from '$ASD_CONNECTED_FROM'"
                let NUMPROC++
            fi
        fi
	fi

	# Extra Samba-Check for connected Clients only if other processes are negative -> [ $NUMPROC -eq 0 ]
	if [ $NUMPROC -eq 0 ]; then
        if [ "$CHECK_SAMBA" = "true" ]; then
            if [ $(/usr/bin/smbstatus | egrep -i "no locked|sessionid.tdb not initialised|locking.tdb not initialised" | wc -l) != "1" ]; then
                _log "INFO: Samba connected (reported by smbstatus) -> no shutdown"
                let NUMPROC++
            fi
        fi
	fi

	if ! $DEBUG ; then { [ $NUMPROC -gt 0 ] && _log "INFO: Found $NUMPROC active socket(s) from Port(s): $NSOCKETNUMBERS" ; }; fi

	if $DEBUG ; then _log "DEBUG: _check_net_status(): $NUMPROC socket(s) active on ${NIC[$NICNR_NETSTATUS]}."; fi

	# return the number of processes we found
	return $NUMPROC

}

################################################################
#
#   name         : _check_ul_dl_rate
#   parameter      : Array-# of NIC
#   global return   : none
#   return         : 0      : if no (not enough) network activity has been found, ready for shutdown
#               : 1      : if enough network activity has been found, no shutdown
#
# Checks for activity on given NIC. It compares the RX and TX bytes
# in every cycle to detect if they significantly changed.
# If they haven't, it will force the system to sleep or do the next check
#
_check_ul_dl_rate()
{
	# ## disabled for testing
	# _log "DEBUG: _check_ul_dl_rate() disabled for testing"
	# return 0

	NICNR_ULDLCHECK="$1"

	# creation of the directory is in the main script

	_log "INFO: ULDL-Traffic-Check for '${NIC[${NICNR_ULDLCHECK}]}'"

	# RX in kB
    	RX=$(ifconfig ${NIC[${NICNR_ULDLCHECK}]} |grep RX |grep bytes | sed -r 's/.*bytes([ ]|:)//g; :a;N;$!ba;s/\n//g' | awk '{printf("%.0f\n", ($1/1024))}')

	# TX in kB
    	TX=$(ifconfig ${NIC[${NICNR_ULDLCHECK}]} |grep TX |grep bytes | sed -r 's/.*bytes([ ]|:)//g; :a;N;$!ba;s/\n//g' | awk '{printf("%.0f\n", ($1/1024))}')

	# Check if RX/TX Files Exist
	RX_FILE=$RXTXTMPDIR/rx-${NICNR_ULDLCHECK}.tmp
	TX_FILE=$RXTXTMPDIR/tx-${NICNR_ULDLCHECK}.tmp
	if [ -f $RX_FILE ] && [ -f $TX_FILE ]; then
		if $DEBUG; then _log "DEBUG: _check_ul_dl(): $RX_FILE and $TX_FILE exist"; fi
		p_RX=$(cat $RX_FILE) ## store previous RX value in p_RX
		p_TX=$(cat $TX_FILE) ## store previous TX value in p_TX

		echo $RX > $RX_FILE ## Write new packets to RX file
		echo $TX > $TX_FILE ## Write new packets to TX file

		if $DEBUG; then
			_log "DEBUG: _check_ul_dl(): actual     RX: $RX"
			_log "DEBUG: _check_ul_dl(): previous p_RX: $p_RX"
			_log "DEBUG: _check_ul_dl(): actual     TX: $TX"
			_log "DEBUG: _check_ul_dl(): previous p_TX: $p_TX"
		fi

		# Calculate threshold limit
		let ULDLINCREASE=$ULDLRATE*$SLEEP
		if $DEBUG; then _log "DEBUG: _check_ul_dl(): ULDLINCREASE: $ULDLINCREASE"; fi

		t_RX=$(expr $p_RX + $ULDLINCREASE)
		t_TX=$(expr $p_TX + $ULDLINCREASE)

		# Calculate difference between the last and the actual value
		diff_RX=$(expr $RX - $p_RX)
		diff_TX=$(expr $TX - $p_TX)

		# Calculate dl/ul-rate in kB/s - format xx.x
		LAST_DL_RATE=$(echo $diff_RX $SLEEP | awk '{ printf("%.1f\n", ($1/$2) ) }')
		LAST_UL_RATE=$(echo $diff_TX $SLEEP | awk '{ printf("%.1f\n", ($1/$2) ) }')

		_log "INFO: ${NIC[${NICNR_ULDLCHECK}]}: over the last $SLEEP seconds: DL: $LAST_DL_RATE kB/s; UL: $LAST_UL_RATE kB/s"

		# If network bytes have not increased over given value
		if $DEBUG; then
			_log "DEBUG: _check_ul_dl(): SLEEP: $SLEEP"
			_log "DEBUG: _check_ul_dl(): t_RX: $t_RX"
			_log "DEBUG: _check_ul_dl(): diff_RX: $diff_RX"
			_log "DEBUG: _check_ul_dl(): t_TX: $t_TX"
			_log "DEBUG: _check_ul_dl(): diff_TX: $diff_TX"
			_log "DEBUG: _check_ul_dl(): check: RX:$RX -le t_RX:$t_RX"
			_log "DEBUG: _check_ul_dl(): check: TX:$TX -le t_TX:$t_TX"
		fi

		if [ $RX -le $t_RX -a $TX -le $t_TX ]; then
			_log "INFO: ${NIC[${NICNR_ULDLCHECK}]}: UL- and DL-Rate is under $ULDLRATE kB/s -> next check"
			return 0 # return value -> shutdown
		else
			_log "INFO: ${NIC[${NICNR_ULDLCHECK}]}: UL- or DL-Rate is over $ULDLRATE kB/s -> no shutdown"
			return 1 # -> no shutdown
		fi # > if [ $RX -le $t_RX ] && [ $TX -le $t_TX ]; then

	# RX/TX-Files doesn't Exist
	else
		echo $RX > $RX_FILE ## Write new packets to RX file
		echo $TX > $TX_FILE ## Write new packets to TX file

		if $DEBUG; then
			_log "DEBUG: rx.tmp and/or tx.tmp do not exist - writing values to files"
		fi

		# This is the obviously the first run, because of tx.tmp and/or rx.tmp doesn't exist
		return 0
	fi # > # if [ -f $RX_FILE ] && [ -f $TX_FILE ]; then

	_log "ERROR: _check_ul_dl_rate: This should not happen - Exit 42"
	exit 42
}

################################################################
#
#   name         	: _check_clock
#   parameter      	: UPHOURS : range of hours, where system should go to sleep, e.g. 6..20
#   global return   : none
#   return         	: 0      : if actual value of hours is in DOWN range, ready for shutdown
#               	: 1      : if actual value of hours is in UP range, no shutdown
#
_check_clock()
{
	CLOCKOK=true

	if  [[ "$UPHOURS" =~ ^([0-9]{1,2})\.{2}([0-9]{1,2}$) ]]; then
		CLOCKSTART=${BASH_REMATCH[1]}
		CLOCKEND=${BASH_REMATCH[2]}
		CLOCKCHECK=$(date +%H | sed 's/^0//g')
		CLOCKMINUTES=$(date +%M)
		TIMETOSLEEP=0
		SECONDSTOSLEEP=0
		TIMETOSLEEP=0
		if $DEBUG ; then
			_log "DEBUG: _check_clock(): CLOCKOK: $CLOCKOK; CLOCKSTART: $CLOCKSTART ; CLOCKEND: $CLOCKEND "
			_log "DEBUG: _check_clock(): CLOCKCHECK: $CLOCKCHECK "
		fi
		_log "INFO: Checking the time: stay up or shutdown ..."

		if [[ $CLOCKEND -gt $CLOCKSTART ]]; then

				# aktuelle Zeit liegt zwischendrin
				if [[ $CLOCKCHECK -ge $CLOCKSTART && $CLOCKCHECK -lt $CLOCKEND ]]; then
					CLOCKOK=true
					let TIMETOSLEEP=$CLOCKEND-$CLOCKCHECK-1

					if $DEBUG ; then
						_log "DEBUG: CHECK 1"
						_log "DEBUG: _check_clock(): CLOCKCHECK: $CLOCKCHECK; CLOCKSTART: $CLOCKSTART ; CLOCKEND: $CLOCKEND -> forced to stay up"
					fi
				else
					CLOCKOK=false
					if $DEBUG ; then
						_log "DEBUG: CHECK 2"
						_log "DEBUG: _check_clock(): CLOCKCHECK: $CLOCKCHECK; CLOCKSTART: $CLOCKSTART ; CLOCKEND: $CLOCKEND -> shutdown-check"
					fi
				fi
		else
				if [[ $CLOCKCHECK -ge $CLOCKSTART || $CLOCKCHECK -lt $CLOCKEND ]]; then
					CLOCKOK=true
					let TIMETOSLEEP=$CLOCKEND-$CLOCKCHECK-1
					if $DEBUG ; then
						_log "DEBUG: CHECK 3"
						_log "DEBUG: _check_clock(): CLOCKCHECK: $CLOCKCHECK; CLOCKSTART: $CLOCKSTART ; CLOCKEND: $CLOCKEND -> forced to stay up"
					fi
				else
					CLOCKOK=false
					if $DEBUG ; then
						_log "DEBUG: CHECK 4"
						_log "DEBUG: _check_clock(): CLOCKCHECK: $CLOCKCHECK; CLOCKSTART: $CLOCKSTART ; CLOCKEND: $CLOCKEND -> shutdown-check"
					fi
				fi
		fi # > [[ $CLOCKEND -gt $CLOCKSTART ]]; then
	fi # > [[ "$UPHOURS" =~ ^([0-9]{1,2})\.{2}([0-9]{1,2}$) ]]; then

	# Calculating the time before shutdown-Phase
	if [ $TIMETOSLEEP -gt 0 ]; then # only if $TIMETOSLEEP > 0; otherwise calculations are obsolete
		let SECONDSTOSLEEP=$TIMETOSLEEP*3600
		let MINUTESTOSLEEP=60-$CLOCKMINUTES-5 # Minutes until full Hour minus 5 min
		let SECONDSTOSLEEP=$SECONDSTOSLEEP+$MINUTESTOSLEEP*60 # Seconds until 5 minutes before shutdown-Range

		# The following two should point to shutdown-range minus 5 minutes
		let TIMEHOUR=$CLOCKCHECK+$TIMETOSLEEP # actual time plus hours to sleep
		let TIMEMINUTES=$CLOCKMINUTES+$MINUTESTOSLEEP # actual time (minutes) plus minutes to sleep
	fi

	if $DEBUG; then
		_log "DEBUG: _check_clock(): TIMETOSLEEP: $TIMETOSLEEP"
		_log "DEBUG: _check_clock(): SECONDSTOSLEEP: $SECONDSTOSLEEP"
		_log "DEBUG: _check_clock(): MINUTESTOSLEEP: $MINUTESTOSLEEP"
		_log "DEBUG: _check_clock(): Final: SECONDSTOSLEEP: $SECONDSTOSLEEP"
		_log "DEBUG: _check_clock(): TIMEHOUR: $TIMEHOUR - TIMEMINUTES: $TIMEMINUTES"
	fi

	if $CLOCKOK; then
		_log "INFO: System is in Stayup-Range. No need to do anything. Sleeping ..."
		_log "INFO: Sleeping until $TIMEHOUR:$TIMEMINUTES -> $SECONDSTOSLEEP seconds"
		sleep $SECONDSTOSLEEP
		return 1
	else
		_log "INFO: System is in Shutdown-Range. Do further checks ..."
		return 0
	fi
}

################################################################
#
#   name         	: _check_hddio
#   parameter      	: HDDIORATE : Rate in kB/s of HDD-IO
#   global return   : none
#   return         	: 0      : if actual value of hddio is lower than the defined value, ready for shutdown
#               	: 1      : if actual value of hddio is higher than the defined value, no shutdown
#
_check_hddio()
{
	# ## disabled for testing
	# _log "DEBUG: _check_processes() disabled for testing"
	# return 0

	HDDIO_CNT=0
	HDDIO_FIRSTRUN=0

	# function to write values to file
	f_check_hdd_io_write_to_file() {
		echo "r $OMV_ASD_HDD_IN" > $HDDIOTMPDIR/hddio_dev_$OMV_HDD.tmp ## Write new packets to hddio file
		echo "w $OMV_ASD_HDD_OUT" >> $HDDIOTMPDIR/hddio_dev_$OMV_HDD.tmp ## Write new packets to hddio file
	}

	# do this for every HDD mounted in OMV
	if $DEBUG; then
		_log "DEBUG: ls -l $HDDIOTMPDIR ## Begin ----------"
		ls -l $HDDIOTMPDIR | grep -v total | while read line; do
			_log "DEBUG: $line"
		done
		_log "DEBUG: ls -l $HDDIOTMPDIR ## End ----------"
	fi

	iostat -kd > $HDDIOTMPDIR/iostat.txt

	if $DEBUG; then
		_log "DEBUG: ## iostat -kd ## Begin ----------"
		while read line; do
			_log "DEBUG: $line"
		done < $HDDIOTMPDIR/iostat.txt
		_log "DEBUG: ## iostat -kd ## End ----------"
	fi

	for OMV_HDD in $(mount -l | grep /dev/sd | sed 's/.*\(sd.\).*/\1/g' | sort -u); do
		OMV_IOSTAT="$(egrep ^${OMV_HDD} $HDDIOTMPDIR/iostat.txt)"

		OMV_ASD_HDD_IN="$(echo "$OMV_IOSTAT" | awk '{print $5}')"
		OMV_ASD_HDD_OUT="$(echo "$OMV_IOSTAT" | awk '{print $6}')"

		# is there any function to achieve this in OMV?
		OMV_HDD_NAME="$( blkid | grep /dev/$OMV_HDD | grep LABEL | sed 's/.*LABEL="\(.*\)" UUID.*/\1/g')"

		if $DEBUG; then
			_log "DEBUG: HDD-IO: ===== /dev/$OMV_HDD -> $OMV_HDD_NAME ====="

			_log "DEBUG: ## iostat -kd | egrep ^${OMV_HDD} ## Begin ----------"
			cat $HDDIOTMPDIR/iostat.txt | egrep ^${OMV_HDD} | while read line; do
				_log "DEBUG: $line"
			done
			_log "DEBUG: ## iostat -kd | egrep ^${OMV_HDD} ## End ----------"

			_log "DEBUG: check_hddio() actual iostat-values: r: OMV_ASD_HDD_IN:  $OMV_ASD_HDD_IN"
			_log "DEBUG: check_hddio() actual iostat-values: w: OMV_ASD_HDD_OUT: $OMV_ASD_HDD_OUT"
		fi

		if [ -f $HDDIOTMPDIR/hddio_dev_$OMV_HDD.tmp ]; then

			HDDIO_DEV_TMP="$(cat $HDDIOTMPDIR/hddio_dev_$OMV_HDD.tmp)"

			if $DEBUG; then
				_log "DEBUG: _check_hddio(): HDDIO_RATE: $HDDIO_RATE"
				_log "DEBUG: _check_hddio(): hddio_dev_$OMV_HDD.tmp exists"
				_log "DEBUG: ## $HDDIOTMPDIR/hddio_dev_$OMV_HDD.tmp: File content ## Begin ----------"
				while read line; do
					_log "DEBUG: $line"
				done < $HDDIOTMPDIR/hddio_dev_$OMV_HDD.tmp
				_log "DEBUG: ## $HDDIOTMPDIR/hddio_dev_$OMV_HDD.tmp: File content ## End ----------"
			fi

			# store previous READ value in p_HDDIO_READ
			p_HDDIO_READ=$(echo "$HDDIO_DEV_TMP" | grep r | sed 's/^r //g')
			#p_HDDIO_READ=$(cat $HDDIOTMPDIR/hddio_dev_$OMV_HDD.tmp | grep r | sed 's/^r //g')

			# store previous WRITE value in p_HDDIO_WRITE
			#p_HDDIO_WRITE=$(cat $HDDIOTMPDIR/hddio_dev_$OMV_HDD.tmp | grep w | sed 's/^w //g')
			p_HDDIO_WRITE=$(echo "$HDDIO_DEV_TMP" | grep w | sed 's/^w //g')

			if $DEBUG; then
				#_log "DEBUG: check_hddio(): r: p_HDDIO_READ:  $p_HDDIO_READ"
				#_log "DEBUG: check_hddio(): w: p_HDDIO_WRITE: $p_HDDIO_WRITE"
				_log "DEBUG: check_hddio(): r: actual OMV_ASD_HDD_IN: $OMV_ASD_HDD_IN"
				_log "DEBUG: check_hddio(): r: prev p_HDDIO_READ: $p_HDDIO_READ ($HDDIOTMPDIR/hddio_dev_$OMV_HDD.tmp)"
				_log "DEBUG: check_hddio(): w: actual OMV_ASD_HDD_OUT: $OMV_ASD_HDD_OUT"
				_log "DEBUG: check_hddio(): w: prev p_HDDIO_WRITE: $p_HDDIO_WRITE  ($HDDIOTMPDIR/hddio_dev_$OMV_HDD.tmp)"
			fi

			# check if values seems to be correct (with RegEx)
			[[ "$p_HDDIO_READ" =~ ^([0-9]{1,})$ ]] && \
			[[ "$p_HDDIO_WRITE" =~ ^([0-9]{1,})$ ]] || {
				_log "WARN: Invalid value found in $HDDIOTMPDIR/hddio_dev_$OMV_HDD.tmp"
				_log "WARN: READ: '$p_HDDIO_READ' --- WRITE: '$p_HDDIO_WRITE'"
				_log "WARN: Deleting and rewriting the file"
				rm -f $HDDIOTMPDIR/hddio_dev_$OMV_HDD.tmp
				f_check_hdd_io_write_to_file
				continue # next HDD
				}

			f_check_hdd_io_write_to_file

			# Calculate threshold limit (defined kB/s multiplied with $SLEEP) to get the total value of kB over the $SLEEP-time
			let HDDIO_INCREASE=$HDDIO_RATE*$SLEEP

			# Calculate the total value
			t_HDDIO_READ=$(expr $p_HDDIO_READ + $HDDIO_INCREASE)
			t_HDDIO_WRITE=$(expr $p_HDDIO_WRITE + $HDDIO_INCREASE)

			# Calculate difference between the last and the actual value
			diff_HDDIO_READ=$(expr $OMV_ASD_HDD_IN - $p_HDDIO_READ)
			diff_HDDIO_WRITE=$(expr $OMV_ASD_HDD_OUT - $p_HDDIO_WRITE)

			# Calculate hddio-rate in kB/s - format xx.x
			LAST_HDDIO_READ_RATE=$(echo $diff_HDDIO_READ $SLEEP | awk '{ printf("%.1f\n", ($1/$2) ) }')
			LAST_HDDIO_WRITE_RATE=$(echo $diff_HDDIO_WRITE $SLEEP | awk '{ printf("%.1f\n", ($1/$2) ) }')

			#_log "INFO: HDD-IO: '/dev/$OMV_HDD -> $OMV_HDD_NAME' (last ${SLEEP}s): READ $LAST_HDDIO_READ_RATE kB/s; WRITE: $LAST_HDDIO_WRITE_RATE kB/s"

			# If hddio bytes have not increased over given value
			if $DEBUG; then
				#_log "DEBUG: check_hddio(): SLEEP: $SLEEP"
				_log "DEBUG: check_hddio(): HDDIO_INCREASE: $HDDIO_INCREASE"
				_log "DEBUG: check_hddio(): t_HDDIO_READ: $t_HDDIO_READ"
				_log "DEBUG: check_hddio(): diff_HDDIO_READ: $diff_HDDIO_READ"
				_log "DEBUG: check_hddio(): t_HDDIO_WRITE: $t_HDDIO_WRITE"
				_log "DEBUG: check_hddio(): diff_HDDIO_WRITE: $diff_HDDIO_WRITE"
				_log "DEBUG: check_hddio(): check: 'OMV_ASD_HDD_IN: $OMV_ASD_HDD_IN' -le 't_HDDIO_READ: $t_HDDIO_READ'"
				_log "DEBUG: check_hddio(): check: 'OMV_ASD_HDD_OUT: $OMV_ASD_HDD_OUT'  -le 't_HDDIO_WRITE: $t_HDDIO_WRITE'"
				_log "DEBUG: check_hddio(): '/dev/$OMV_HDD -> $OMV_HDD_NAME' (last ${SLEEP}s): r: $LAST_HDDIO_READ_RATE kB/s; w: $LAST_HDDIO_WRITE_RATE kB/s"
			fi

			if [ $OMV_ASD_HDD_IN -le $t_HDDIO_READ -a $OMV_ASD_HDD_OUT -le $t_HDDIO_WRITE ]; then
				_log "INFO: HDD-IO: '/dev/$OMV_HDD -> $OMV_HDD_NAME' (last ${SLEEP}s): r: $LAST_HDDIO_READ_RATE w: $LAST_HDDIO_WRITE_RATE is under $HDDIO_RATE -> next HDD"
				 continue # next HDD
			else
				_log "INFO: HDD-IO for '/dev/$OMV_HDD -> $OMV_HDD_NAME' (last ${SLEEP}s): r: $LAST_HDDIO_READ_RATE w: $LAST_HDDIO_WRITE_RATE is over $HDDIO_RATE -> no shutdown"
				return 1 # This HDD-IO is over the defined value, no need to do further HDD-IO-Checks
			fi # > if [ $HDDIO_READ -le $t_HDDIO_READ ] && [ $HDDIO_WRITE -le $t_HDDIO_WRITE ]; then

		# HDDIO_READ/HDDIO_WRITE-Files doesn't exist
		else
			f_check_hdd_io_write_to_file
			# This is the obviously the first run, because of dev_$OMV_HDD.tmp doesn't exist
			if $DEBUG; then
				_log "DEBUG: hddio_dev_$OMV_HDD.tmp doesn't exist - writing values to file"
			fi
		fi # > # if [ -f $TMPDIR/hddio_dev_$OMV_HDD.tmp ]; then

	done
	# No HDD-IO is over the defined value -> shutdown
	_log "INFO: HDD-IO all checks for HDD-IO finished"
	return 0
}

################################################################
#
#   name:	 _check_config
#   parameter : none
#   return: 	none
#

_check_config()
{
	## Check Parameters from Config and setting default variables:
	_log "INFO: ------------------------------------------------------"
	_log "INFO: Checking config"

	[[ "$ENABLE" = "true" || "$ENABLE" = "false" ]] || { _log "WARN: ENABLE not set properly. It has to be 'true' or 'false'"
			_log "WARN: Set ENABLE to false -> exiting here ..."
			exit 0; }

	if [ "$FAKE" = "true" ]; then
		VERBOSE="true"; DEBUG="true"
		_log "INFO: Fake-Mode in on"
	else
		[[ "$FAKE" = "true" || "$FAKE" = "false" || "$FAKE" = "" ]] || { _log "WARN: FAKE not set properly. It has to be 'true', 'false' or empty."
			_log "WARN: Set FAKE to true -> Testmode with VERBOSE on"
			FAKE="true"; VERBOSE="true"; DEBUG="TRUE"; }
	fi

	if [ ! -z "$PLUGINCHECK" ]; then
		[[ "$PLUGINCHECK" = "true" || "$PLUGINCHECK" = "false" ]] || { _log "WARN: AUTOUNRARCHECK not set properly. It has to be 'true' or 'false'."
				_log "WARN: Set PLUGINCHECK to false"
				PLUGINCHECK="false"; }
	fi

	# Flag: 1 - 999 (cycles)
	[[ "$CYCLES" =~ ^([1-9]|[1-9][0-9]|[1-9][0-9]{2})$ ]] || {
			_log "WARN: Invalid parameter format: Flag"
			_log "WARN: You set it to '$CYCLES', which is not a correct syntax. Only '1' - '999' is allowed."
			_log "WARN: Setting CYCLES to 5"
			CYCLES="5"; }

	# CheckClockActive together with UPHOURS
	[[ "$CHECKCLOCKACTIVE" = "true" || "$CHECKCLOCKACTIVE" = "false" ]] || { _log "WARN: CHECKCLOCKACTIVE not set properly. It has to be 'true' or 'false'."
		_log "WARN: Set CHECKCLOCKACTIVE to false"
		CHECKCLOCKACTIVE="false"; }

	# Check UpHours only if CHECKCLOCKACTIVE is "true"
	if [ "$CHECKCLOCKACTIVE" = "true" ]; then
		[[ "$UPHOURS" =~ ^(([0-1]?[0-9]|[2][0-3])\.{2}([0-1]?[0-9]|[2][0-3]))$ ]] || {
			_log "WARN: Invalid parameter list format: UPHOURS [hour1..hour2]"
			_log "WARN: You set it to '$UPHOURS', which is not a correct syntax. Maybe it's empty?"
			_log "WARN: Setting UPHOURS to 6..20"
			UPHOURS="6..20"; }
	fi

	# Had to define REGEX here, because the script doesn't work from systemstart, but from the CLI (WTF?)
	REGEX="^([A-Za-z0-9_\.-]{1,})+(,[A-Za-z0-9_\.-]{1,})*$"
	if  [ "$LOADPROCNAMES" = "-" ]; then
			_log "INFO: LOADPROCNAMES is disabled - No processes being checked"
			LOADPROCNAMES=""
	elif [ "$LOADPROCNAMES" = "" ]; then
			_log "INFO: LOADPROCNAMES is set to: 'smbd,nfsd,transmission-daemon,mt-daapd,forked-daapd' (default)"
			LOADPROCNAMES="smbd,nfsd,transmission-daemon,mt-daapd,forked-daapd"
	else
			[[ "$LOADPROCNAMES" =~ $REGEX ]] || {
					_log "WARN: Invalid parameter list format: LOADPROCNAMES [lproc1,lproc2,lproc3,...]"
					_log "WARN: You set it to '$LOADPROCNAMES', which is not a correct syntax."
					_log "WARN: exiting ..."
					exit 1; }
	fi

	#TempProcNames
	if  [ "$TEMPPROCNAMES" = "-" ]; then
			_log "INFO: TEMPPROCNAMES is disabled - No processes being checked"
			TEMPPROCNAMES=""
	elif  [ "$TEMPPROCNAMES" = "" ]; then
		_log "INFO: TEMPPROCNAMES is set to: in.'tftpd' (default)"
		_log "INFO: If you want more processes monitored, please have a look at the expert-settings"
			TEMPPROCNAMES="in.tftpd"
	else
		[[ "$TEMPPROCNAMES" =~ $REGEX ]] || {
			_log "WARN: Invalid parameter list format: TEMPPROCNAMES [tproc1,tproc2,tproc3,...]"
			_log "WARN: You set it to '$TEMPPROCNAMES', which is not a correct syntax."
			_log "WARN: exiting ..."
			exit 1; }
	fi

	# Port-Numbers with at least 2 digits
	[[ "$NSOCKETNUMBERS" =~ ^([0-9]{2,5})+(,[0-9]{2,5})*$ ]] || {
			_log "WARN: Invalid parameter list format: NSOCKETNUMBERS [nsocket1,nsocket2,nsocket3,...]"
			_log "WARN: You set it to '$NSOCKETNUMBERS', which is not a correct syntax. Maybe it's empty? Only  Port-Numbers with at least 2 digits are allowed."
			_log "WARN: Setting NSOCKETNUMBERS to 21,22 (FTP and SSH)"
			NSOCKETNUMBERS="22"; }

	# Pinglist
	IPCHECK=true
	if [ -z $PINGLIST ]; then
		if [ "$RANGE" = "-" ]; then
				_log "INFO: RANGE is set to '-' -> no IP-Check"
				IPCHECK=false
		else
			[[ "$RANGE" =~ ^([1-9]{1}[0-9]{0,2})?([1-9]{1}[0-9]{0,2}\.{2}[1-9]{1}[0-9]{0,2})?(,[1-9]{1}[0-9]{0,2})*((,[1-9]{1}[0-9]{0,2})\.{2}[1-9]{1}[0-9]{0,2})*$ ]] || {
					_log "WARN: Invalid parameter list format: RANGE [v..v+n,w,x+m..x,y,z..z+o]"
					_log "WARN: You set it to '$RANGE', which is not a correct syntax."
					_log "WARN: Setting RANGE to 2..254"
					RANGE="2..254"; }
		fi
	else
		if [ -f "$PINGLIST" ]; then
			_log "INFO: PINGLIST is set in the conf, reading IPs from '$PINGLIST'"
			USEOWNPINGLIST="true"
		else
			_log "WARN: PINGLIST is set in the conf, but the file isn't there"
			_log "WARN: Setting RANGE to 2..254"
			RANGE="2..254"
		fi
	fi

	# $HDDIOCHECK" = "true"
	if [ ! -z "$HDDIOCHECK" ]; then
		[[ "$HDDIOCHECK" = "true" || "$HDDIOCHECK" = "false" ]] || { _log "WARN: HDDIOCHECK not set properly. It has to be 'true' or 'false'."
				_log "WARN: Set HDDIOCHECK to false"
				HDDIOCHECK="false"; }
	fi

	# HDDIO
	if [ "$HDDIOCHECK" = "true" ]; then

		# check if iostat is executable and installed (package 'sysstat')
		if which iostat > /dev/null 2>&1; then

			# HDDIO_RATE (max 6 digits -> 1 - 999999 kB/s)
			[[ "$HDDIO_RATE" =~ ^([1-9]|[1-9][0-9]{1,5})$ ]] || {
				_log "WARN: Invalid parameter format: HDDIO_RATE"
				_log "WARN: You set it to '$HDDIO_RATE', which is not a correct syntax. Maybe it's empty?"
				_log "WARN: Set HDDIO_RATE to 500"
				HDDIO_RATE=500; }
		else
			_log "WARN: iostat is not found! Please install it with 'apt-get install sysstat'"
			_log "WARN: HDDIOCHECK is set to false"
			HDDIOCHECK="false"
		fi
	else
		_log "WARN: HDDIOCHECK is set to false"
		_log "WARN: Ignoring HDDIO_RATE"
		HDDIOCHECK="false"
	fi

	# Sleep: 1 - 9999
	[[ "$SLEEP" =~ ^([1-9]|[1-9][0-9]{1,3})$ ]] || {
			_log "WARN: Invalid parameter format: SLEEP (sec)"
			_log "WARN: You set it to '$SLEEP', which is not a correct syntax.  Only '1' - '9999' is allowed. Maybe it's empty?"
			_log "WARN: Setting SLEEP to 180 sec"
			SLEEP=180; }

	# $ULDLCHECK" = "true"
	if [ ! -z "$ULDLCHECK" ]; then
		[[ "$ULDLCHECK" = "true" || "$ULDLCHECK" = "false" ]] || { _log "WARN: ULDLCHECK not set properly. It has to be 'true' or 'false'."
				_log "WARN: Set ULDLCHECK to false"
				ULDLCHECK="false"; }
	fi

	# ULDLRATE (max 6 digits -> 1 - 999999 kB/s)
	if [ "$ULDLCHECK" = "true" ]; then
		[[ "$ULDLRATE" =~ ^([1-9]|[1-9][0-9]{1,5})$ ]] || {
			_log "WARN: Invalid parameter format: ULDLRATE"
			_log "WARN: You set it to '$ULDLRATE', which is not a correct syntax. Maybe it's empty?"
			_log "WARN: Set ULDLRATE to 50"
			ULDLRATE=50; }
	else
		_log "WARN: ULDLCHECK is set to false"
		_log "WARN: Ignoring ULDLRATE"
	fi

	# SHUTDOWNCOMMAND - check acpi power states with pm-is-supported
	# if SHUTDOWNCOMMAND is set
	# Thx to http://wiki.ubuntuusers.de/pm-utils
	PM_HIBERNATE=false
	if [ ! -z "$SHUTDOWNCOMMAND" ]; then
		_log "INFO: SHUTDOWNCOMMAND is set to '$SHUTDOWNCOMMAND'"
		# check, if pm-utils is installed
		if ! which pm-is-supported 1>/dev/null; then
			_log "WARN: SHUTDOWNCOMMAND is set, but pm-is-supported not found"
			_log "WARN: Please install the package pm-utils with 'apt-get install pm-utils'!"
			_log "WARN: Unset SHUTDOWNCOMMAND -> do normal shutdown"
			unset $SHUTDOWNCOMMAND
		else
			# check POWER MANAGEMENT MODES
			_log "INFO: Your Kernel supports the following modes from pm-utils:"
			pm-is-supported --suspend         && _log "INFO: Kernel supports SUSPEND (SUSPEND to RAM)" && PM_SUSPEND=true
			pm-is-supported --hibernate       && _log "INFO: Kernel supports HIBERNATE (SUSPEND to DISK)" && PM_HIBERNATE=true
			pm-is-supported --suspend-hybrid  && _log "INFO: Kernel supports HYBRID-SUSPEND (to DISK & to RAM)" && PM_SUSPEND_HYBRID=true

			# check, if pm-suspend is supported
			if [ "$SHUTDOWNCOMMAND" = "pm-suspend" -a ! "$PM_SUSPEND" = "true" ]; then
				_log "WARN: You set 'SHUTDOWNCOMMAND=\"pm-suspend\", but your PC doesn't support this!"
				_log "WARN: Setting it to 'shutdown -h now'"
				SHUTDOWNCOMMAND="shutdown -h now"
			fi
			# check, if pm-hibernate is supported
			if [ "$SHUTDOWNCOMMAND" = "pm-hibernate" -a ! "$PM_HIBERNATE" = "true" ]; then
				_log "WARN: You set 'SHUTDOWNCOMMAND=\"pm-hibernate\", but your PC doesn't support this!"
				_log "WARN: Setting it to 'shutdown -h now'"
				SHUTDOWNCOMMAND="shutdown -h now"
			fi
			# check, if pm-suspend-hybrid is supported
			if [ "$SHUTDOWNCOMMAND" = "pm-suspend-hybrid" -a ! "$PM_SUSPEND_HYBRID" = "true" ]; then
				_log "WARN: You set 'SHUTDOWNCOMMAND=\"pm-suspend-hybrid\", but your PC doesn't support this!"
				_log "WARN: Setting it to 'shutdown -h now'"
				SHUTDOWNCOMMAND="shutdown -h now"
			fi
		fi
	fi

	# LOADAVERAGECHECK = "true"
	if [ ! -z "$LOADAVERAGECHECK" ]; then
		[[ "$LOADAVERAGECHECK" = "true" || "$LOADAVERAGECHECK" = "false" ]] || { _log "WARN: LOADAVERAGECHECK not set properly. It has to be 'true' or 'false'."
				_log "WARN: Set LOADAVERAGECHECK to false"
				LOADAVERAGECHECK="false"; }
	fi

	# LOADAVERAGE (max 3 digits)
	if [ "$LOADAVERAGECHECK" = "true" ]; then
		[[ "$LOADAVERAGE" =~ ^([1-9]|[1-9][0-9]{1,2})$ ]] || {
			_log "WARN: Invalid parameter format: LOADAVERAGE"
			_log "WARN: You set it to '$LOADAVERAGE', which is not a correct syntax. Maybe it's empty?"
			_log "WARN: Set LOADAVERAGECHECK to 20 (0.20)"
			LOADAVERAGE=20; }
	else
		_log "WARN: LOADAVERAGECHECK is set to false"
		_log "WARN: Ignoring LOADAVERAGE"
	fi
}

################################################################
#
#   name:	 	_check_networkconfig
#   parameter : none
#   return: 	none
#
_check_networkconfig()
{
	# Read IP-Adress and SERVERIP from e.g. 'ifconfig eth0'
	_log "INFO: ------------------------------------------------------"
	_log "INFO: Reading NICs ,IPs, ..."
	NICNR=0
	FOUNDIP=0

	# check FORCE_NIC, if set, then set it to NIC[0]
	if [ -z "$FORCE_NIC" ]; then
		# set the default NICs
		# make sure that we filter out any suffixes for sub interfaces when using VLANs and stuff (i.e. "eth0.3@eth0" becomes "eth0.3" only).
		FORCE_NIC="$(ip link | awk -F': ' '/: en|: eth|: wlan|: bond|: usb/ {print $2}' | sed 's/\@.*//g')"
	else
		_log "INFO: FORCE_NIC found: NIC is now $FORCE_NIC"
		_log "INFO: If the following checks fail, then try to uncomment FORCE_NIC to do a normal network-check"
	fi

	for NWADAPTERS in $FORCE_NIC; do
		let NICNR++
		NIC[$NICNR]=$NWADAPTERS

		if ip link show up | grep ${NIC[$NICNR]} > /dev/null; then
			_log "INFO: NIC '${NIC[$NICNR]}' found: try to get IP"

			NW_WAIT=0
			while true; do
				let NW_WAIT++
				if [ $NW_WAIT -le 5 ]; then
					if ! ifconfig ${NIC[$NICNR]} | egrep -q "inet "; then
						_log "INFO: _check_networkconfig(): Run: #${NW_WAIT}: No internet-Adress found - wait 60 sec for initializing the network"
						sleep 60
					else
						_log "INFO: _check_networkconfig(): Run: #${NW_WAIT}: IP-Adress found"
						break
					fi
				else
					_log "WARN: No internet-Adress for ${NIC[$NICNR]} found after 5 minutes - The script will not work maybe ..."
					break
				fi
			done

			IPFROMIFCONFIG[$NICNR]="$(ifconfig ${NIC[$NICNR]} | egrep "inet " | sed -r 's/[ ]*(Bcast|netmask).*//g; s/[ ]*inet[ ](ad[d]r:)?//g')"
			SERVERIP[$NICNR]="$(echo ${IPFROMIFCONFIG[$NICNR]} | sed 's/.*\.//g')"
			CLASS[$NICNR]="$(echo ${IPFROMIFCONFIG[$NICNR]} | sed 's/\(.*\..*\..*\)\..*/\1/g')"
			_log "INFO: '${NIC[$NICNR]}' has IP: ${IPFROMIFCONFIG[$NICNR]}"

			if $DEBUG; then
				# ifconfig in extra variables for easier debugging
				IPFROMIFCONFIG_DEBUG_1="$(ifconfig ${NIC[$NICNR]} | egrep "inet ")"
				IPFROMIFCONFIG_DEBUG_2="$(ifconfig ${NIC[$NICNR]} | egrep "inet " | sed 's/[ ]*Bcast.*//g')"
				# Log-Output all the stuff
				_log "DEBUG: ifconfig ${NIC[$NICNR]} (Begin) ====================================="
				# Output of ifconfig line for line
				ifconfig ${NIC[$NICNR]} | while read IFCONFIGLINE
				do
					_log "DEBUG: $IFCONFIGLINE"
				done
				_log "DEBUG: ifconfig ${NIC[$NICNR]} (End) ======================================="
				_log "DEBUG: IPFROMIFCONFIG_DEBUG_1: '$IPFROMIFCONFIG_DEBUG_1'"
				_log "DEBUG: IPFROMIFCONFIG_DEBUG_2: '$IPFROMIFCONFIG_DEBUG_2'"
				_log "DEBUG: _check_networkconfig(): IPFROMIFCONFIG$NICNR: ${IPFROMIFCONFIG[$NICNR]}"
				_log "DEBUG: _check_networkconfig(): SERVERIP$NICNR: ${SERVERIP[$NICNR]}"
				_log "DEBUG: _check_networkconfig(): CLASS$NICNR: ${CLASS[$NICNR]}"
			fi

			# if both variables found, then count 1 up
			if [ ! -z "${SERVERIP[$NICNR]}" ] && [ ! -z "${CLASS[$NICNR]}" ]; then
				let FOUNDIP++

				# bond0 has priority, even if there are eth0 and eth1
				if [ "${NIC[$NICNR]}" = "bond0" ]; then
					_log "INFO: NIC '${NIC[$NICNR]}' found, skipping all others. bond0 has priority"
					break
				fi
			fi

			# Check CLASS and SERVERIP if they are correct
			[[ "${CLASS[$NICNR]}" =~ ^(25[0-5]|2[0-4][0-9]|[0-1]{1}[0-9]{2}|[1-9]{1}[0-9]{1}|[1-9])\.(25[0-5]|2[0-4][0-9]|[0-1]{1}[0-9]{2}|[1-9]{1}[0-9]{1}|[1-9]|0)\.(25[0-5]|2[0-4][0-9]|[0-1]{1}[0-9]{2}|[1-9]{1}[0-9]{1}|[1-9]|0)$ ]] || {
				_log "WARN: Invalid parameter format: Class: nnn.nnn.nnn]"
				_log "WARN: It is set to '${CLASS[$NICNR]}', which is not a correct syntax. Maybe parsing 'ifconfig ' did something wrong"
				_log "WARN: Please report this Bug and the CLI-output of 'ifconfig'"
				_log "WARN: unsetting NIC[$NICNR]: ${NIC[$NICNR]} ..."
				unset NIC[$NICNR]; }

			[[ "${SERVERIP[$NICNR]}" =~ ^(25[0-4]|2[0-4][0-9]|[0-1]{1}[0-9]{2}|[1-9]{1}[0-9]{1}|[1-9])$ ]] || {
				_log "WARN: Invalid parameter format: SERVERIP [iii]"
				_log "WARN: It is set to '${SERVERIP[$NICNR]}', which is not a correct syntax. Maybe parsing 'ifconfig' did something wrong"
				_log "WARN: Please report this Bug and the CLI-output of 'ifconfig'"
				_log "WARN: unsetting NIC[$NICNR]: ${NIC[$NICNR]} ..."
				unset NIC[$NICNR]; }

		else
			_log "INFO: NIC '${NIC[$NICNR]}' not found, skipping '${NIC[$NICNR]}'"
			if $DEBUG; then _log "DEBUG: before unset: NIC[$NICNR]: ${NIC[$NICNR]}"; fi
			unset NIC[$NICNR]
			if $DEBUG; then _log "DEBUG: after unset: NIC[$NICNR]: ${NIC[$NICNR]}"; fi
		fi
	done

	if [ $FOUNDIP = 0 ]; then
		_log "WARN: No SERVERIP or CLASS found"
		_log "WARN: exiting ..."
		exit 1
	fi
}

################################################################
#
#   name         : _check_system_active
#   parameter      : none
#   global return   : none
#   return         : 0      : if no active host has been found
#               : 1      : if at least one active host has been found, no shutdown
#
_check_system_active()
{
	# Set CNT to 1, because if $CHECKCLOCKACTIVE is successfull or not active, $CNT will be 0
	CNT=1

	# PRIO 0: Do a check, if the actual time is wihin the range of defined STAYUP-phase for this system
	# e.g. 06:00 - 20:00, stay up, otherwise shutdown
	# then: no need to ping all PCs

	if $CHECKCLOCKACTIVE ; then # when $CHECKCLOCKACTIVE is on, then check the Clock

		# if the Clock is in the given Range to shutdown
		#_check_clock $UPHOURS &&
		_check_clock &&
			{
				CNT=0
			}

			if $DEBUG ; then _log "DEBUG: _check_clock(): call _check_clock -> CNT: $CNT; UPHOURS: $UPHOURS "; fi

	else
		# If $CHECKCLOCKACTIVE is off, then Begin with CNT=0 and ping
		CNT=0
		if $DEBUG; then _log "DEBUG: _check_clock is inactive. Setting CNT=0"; fi
	fi # > if $CHECKCLOCKACTIVE ; then

	# call array "1 until $NICNR" (value is set after scriptstart)
	for NICNR_CHECKSYSTEMACTIVE in $(seq 1 $NICNR); do


		# if NIC is set (not empty) then check IPs connections, else skip it
		if [ ! -z "${NIC[$NICNR_CHECKSYSTEMACTIVE]}" ]; then
			if $DEBUG; then _log "DEBUG: _check_system_active() is running - NICNR_CHECKSYSTEMACTIVE: $NICNR_CHECKSYSTEMACTIVE"; fi

			if [ $CNT -eq 0 ]; then
				## PRIO 1: Ping each IP address in parameter list. if we find one -> CNT != 0 we'll
				# stop as there's really no point continuing to looking for more.

				# only check IPs, if RANGE is not set to "-"
				if [ $IPCHECK = "true" ]; then
					_ping_range $NICNR_CHECKSYSTEMACTIVE
					PINGRANGERETURN="$?"
					if [ "$PINGRANGERETURN" -gt 0 ]; then
						let CNT++
						if $DEBUG; then _log "DEBUG: _ping_range() -> RETURN: $PINGRANGERETURN"; fi
					fi
					if $DEBUG ; then _log "DEBUG: _check_system_active(): call _ping_range -> CNT: $CNT "; fi
				else
					_log "INFO: No IPCHECK -> RANGE was set to '-' in the config"
				fi
			else
				if $DEBUG ; then _log "DEBUG: _check_system_active(): _ping_range not called -> CNT: $CNT "; fi
			fi

			if [ $CNT -eq 0 ]; then
			# PRIO 2: Do a check for some active network sockets, maybe, one never knows...
			# If there is at least one active, we leave this function with a 'bogus find'
				_check_net_status $NICNR_CHECKSYSTEMACTIVE

				### Internal debugging
				#echo "_check_net_status disabled for debugging!!!!"

				if [ $? -gt 0 ]; then
					let CNT++
				fi

				if $DEBUG ; then _log "DEBUG: _check_system_active(): call _check_net_status -> CNT: $CNT "; fi
			else
				if $DEBUG ; then _log "DEBUG: _check_system_active(): _check_net_status not called -> CNT: $CNT "; fi
			fi   # > if[ $CNT -eq 0 ]; then

			if [ $CNT -eq 0 ]; then
				# PRIO 3: _check_ul_dl_rate
				# Do a check for ul-dl-rate
				# I've put it here, because every NIC should be checked for uldl-rate
				if [ "$ULDLCHECK" = "true" ] ; then
					_check_ul_dl_rate $NICNR_CHECKSYSTEMACTIVE
					if [ $? -gt 0 ]; then
						let CNT++
					fi

					if $DEBUG ; then _log "DEBUG: _check_system_active(): call _check_ul_dl_rate -> CNT: $CNT "; fi
				fi
			else
				if $DEBUG ; then _log "DEBUG: _check_system_active(): _check_ul_dl_rate not called -> CNT: $CNT "; fi
			fi   # > if[ $CNT -eq 0 ]; then

		fi # >  if [ ! -z "${NIC[$NICNR_CHECKSYSTEMACTIVE]}" ]; then

	done  # > NICNR_CHECKSYSTEMACTIVE in $(seq 1 $NICNR); do

	if [ $CNT -eq 0 ]; then
		# PRIO 4: Do a HDDIO-Check
		if [ "$HDDIOCHECK" = "true" ] ; then
			_check_hddio
			if [ $? -gt 0 ]; then
				let CNT++
			fi

			if $DEBUG ; then _log "DEBUG: _check_system_active(): call _check_hddio -> CNT: $CNT "; fi
		fi
	else
		if $DEBUG ; then _log "DEBUG: _check_system_active(): _check_hddio not called -> CNT: $CNT "; fi
	fi   # > if[ $CNT -eq 0 ]; then



	if [ $CNT -eq 0 ]; then
		# PRIO 5: Do a check for some active processes, maybe, one never knows...
		# If there is at least one active, we leave this function with a 'bogus find'
		_check_processes
		if [ $? -gt 0 ]; then
			let CNT++
		fi

		if $DEBUG ; then _log "DEBUG: _check_system_active(): call _check_processes -> CNT: $CNT "; fi
	else
		if $DEBUG ; then _log "DEBUG: _check_system_active(): _check_processes not called -> CNT: $CNT "; fi
	fi   # > if[ $CNT -eq 0 ]; then

	if [ $CNT -eq 0 ]; then
		# PRIO 6: Do a LOADAVERAGE-Check
		if [ "$LOADAVERAGECHECK" = "true" ] ; then
			_check_loadaverage
			if [ $? -gt 0 ]; then
				let CNT++
			fi

			if $DEBUG ; then _log "DEBUG: _check_system_active(): call _check_loadaverage -> CNT: $CNT "; fi
		fi
	else
		if $DEBUG ; then _log "DEBUG: _check_system_active(): _check_loadaverage not called -> CNT: $CNT "; fi
	fi   # > if[ $CNT -eq 0 ]; then

	if [ $CNT -eq 0 ]; then
		# PRIO 7: Do a PlugIn-Check for any existing files, setup in plugins
		if [ "$PLUGINCHECK" = "true" ] ; then
			_check_plugin
			if [ $? -gt 0 ]; then
				let CNT++
			fi

			if $DEBUG ; then _log "DEBUG: _check_system_active(): call _check_plugin -> CNT: $CNT "; fi
		fi
	else
		if $DEBUG ; then _log "DEBUG: _check_system_active(): _check_plugin not called -> CNT: $CNT "; fi
	fi   # > if[ $CNT -eq 0 ]; then

	return ${CNT};
}

###############################################################
######## START OF BODY FUNCTION SCRIPT AUTOSHUTDOWN.SH ########
###############################################################

logger -s -t "logger: $(basename "$0" | sed 's/\.sh$//g')[$$]" -p $FACILITY.info "INFO: ' XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX'"
logger -s -t "logger: $(basename "$0" | sed 's/\.sh$//g')[$$]" -p $FACILITY.info "INFO: ' XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX'"
logger -s -t "logger: $(basename "$0" | sed 's/\.sh$//g')[$$]" -p $FACILITY.info "INFO: ' XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX'"
logger -s -t "logger: $(basename "$0" | sed 's/\.sh$//g')[$$]" -p $FACILITY.info "INFO: ' X Version: $VERSION'"
logger -s -t "logger: $(basename "$0" | sed 's/\.sh$//g')[$$]" -p $FACILITY.info "INFO: ' Initialize logging to $FACILITY'"

if [ -f /etc/autoshutdown.conf ]; then
	. /etc/autoshutdown.conf
	_log "INFO: /etc/autoshutdown.conf loaded"
else
	_log "WARN: cfg-File not found! Please check Path /etc for autoshutdown.conf"
	exit 1
fi

if [ "$VERBOSE" = "true" ]; then
	DEBUG="true"
else
	DEBUG="false"
fi

_check_config

# enable / disable check here
if ! $ENABLE; then
	_log "INFO: script disabled by autoshutdown.conf"
	_log "INFO: nothing to do. Exiting here ..."
	exit 0
fi

_check_networkconfig

#### Testing fping ####
if ! which fping > /dev/null; then
	echo "WARN: fping not found! Please install it with 'apt-get install fping'"
	_log "WARN: fping not found! Please install it with 'apt-get install fping'"
	exit 1
fi

# If the tmp-dir doesn't exist, create it
if [ ! -d $TMPDIR ]; then
	mkdir $TMPDIR 2> /dev/null
	[[ $? = 0 ]] && _log "INFO: $TMPDIR created" || {
		_log "WARN: Can't create $TMPDIR! Exiting ...!"
		exit 1
		}
fi

# If the pinglist or pinglistactive exists, delete it (at every start of the script)
if [ -f $TMPDIR/pinglist ]; then
	rm -f $TMPDIR/pinglist 2> /dev/null
	[[ $? = 0 ]] && _log "INFO: Pinglist deleted" || _log "WARN: Can't delete Pinglist!"
fi

# Init the counter
FCNT=$CYCLES

# functional start of script
if $DEBUG ; then
	_log "INFO:XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
	_log "DEBUG: ### DEBUG:"
	_log "DEBUG: CLASS and SERVERIP: see above"
	_log "DEBUG: CYCLES: $CYCLES"
	_log "DEBUG: SLEEP: $SLEEP"
	_log "DEBUG: CHECKCLOCKACTIVE: $CHECKCLOCKACTIVE"
	_log "DEBUG: UPHOURS: $UPHOURS"
	_log "DEBUG: RANGE: $RANGE"
	_log "DEBUG: LOADPROCNAMES: $LOADPROCNAMES"
	_log "DEBUG: NSOCKETNUMBERS: $NSOCKETNUMBERS"
	_log "DEBUG: TEMPPROCNAMES: $TEMPPROCNAMES"
	_log "DEBUG: VERBOSE: $VERBOSE"
	_log "DEBUG: FAKE: $FAKE"
	_log "DEBUG: SHUTDOWNCOMMAND: $SHUTDOWNCOMMAND"
	_log "DEBUG: HDDIOCHECK: $HDDIOCHECK"
	_log "DEBUG: HDDIO_RATE: $HDDIO_RATE"
	_log "DEBUG: ULDLCHECK: $ULDLCHECK"
	_log "DEBUG: ULDLRATE: $ULDLRATE"
	_log "DEBUG: LOADAVERAGECHECK: $LOADAVERAGECHECK"
	_log "DEBUG: LOADAVERAGE: $LOADAVERAGE"
	_log "DEBUG: TMPDIR: $TMPDIR"
	_log "DEBUG: PLUGINCHECK: $PLUGINCHECK"
	# List all PlugIns
	_log "DEBUG: PlugIns found in /etc/autoshutdown.d:"
	for ASD_plugin_firstcheck in /etc/autoshutdown.d/*; do
		_log "DEBUG: Plugin: $ASD_plugin_firstcheck"
	done
fi   # > if $DEBUG ;then

_log "INFO:---------------- script started ----------------------"
_log "INFO: ${CYCLES} test cycles until shutdown is issued."

# Creation of the dir for ULDLCHECK
RXTXTMPDIR="$TMPDIR/txrx"
if [ "$ULDLCHECK" = "true" ]; then
	# clearing for the first run of ULDLCHECK
	if [ -d $RXTXTMPDIR ]; then
		if $DEBUG; then _log "DEBUG: _check_ul_dl_rate(): tmpdir: $RXTXTMPDIR exists"; fi
		rm $RXTXTMPDIR/*.tmp >/dev/null 2>&1 && if $DEBUG; then _log "DEBUG: $RXTXTMPDIR/*.tmp deleted @ start of script"; fi
	else
		if $DEBUG ; then _log "DEBUG: _check_ul_dl_rate(): creating tmpdir: $RXTXTMPDIR"; fi
		mkdir $RXTXTMPDIR && if $DEBUG; then _log "DEBUG: _check_ul_dl_rate(): $RXTXTMPDIR created successfully"; fi
	fi
fi

# Creation of the dir for HDDIOCHECK
HDDIOTMPDIR="$TMPDIR/hddio"
if [ "$HDDIOCHECK" = "true" ]; then
        if [ ! -d $HDDIOTMPDIR ]; then
                        if $DEBUG ; then _log "DEBUG: _check_hddio(): creating tmpdir: $HDDIOTMPDIR"; fi
                        mkdir $HDDIOTMPDIR && if $DEBUG; then _log "DEBUG: _check_hddio(): $HDDIOTMPDIR created successfully"; fi
                else
                        if $DEBUG ; then _log "DEBUG: _check_hddio(): tmpdir: $HDDIOTMPDIR exists"; fi
        fi
        # clearing for the first run of HDDIOCHECK
        rm $HDDIOTMPDIR/hddio_dev_*.tmp >/dev/null 2>&1
        rm $HDDIOTMPDIR/iostat.txt >/dev/null 2>&1
        if $DEBUG; then _log "DEBUG: $HDDIOTMPDIR/hddio_dev_*.tmp and iostat.txt deleted @ start of script"; fi
fi

if [ "$FAKE" = "true" ]; then
	_log "INFO: FAKE-Mode in on, dont't wait for first check"
else
	_log "INFO: Waiting 5 min until the first check"
	sleep 5m	# or: sleep 300
fi

for NICNR_START in $(seq 1 $NICNR); do
	# if NIC is set (not empty) then check IPs connections, else skip it
	if [ ! -z "${NIC[$NICNR_START]}" ]; then
		_log "INFO: script is doing checks for NIC: ${NIC[$NICNR_START]} - ${CLASS[$NICNR_START]}.${SERVERIP[$NICNR_START]}"
	fi
done

while : ; do
	_log "INFO:------------------------------------------------------"
	_log "INFO: new supervision cycle started - check active hosts or processes"

	# Main loop, just keep pinging and checking for processes, to decide whether we can shutdown or not...
	if _check_system_active; then

			# Nothing found so sub one from the count and check if we can shutdown yet.
			let FCNT--

			_log "INFO: No active hosts or processes within network range, ${FCNT} cycles until shutdown..."

			if [ $FCNT -eq 0 ]; then
				_shutdown;
			fi   # > if [ $FCNT -eq 0 ]; then
	else
		# Live IP found so reset count
		FCNT=${CYCLES};
	fi   # > if _check_system_active

	# Wait for the required time before checking again.
	_log "INFO: sleep for ${SLEEP}s."
	sleep $SLEEP;

done   # > while : ; do

echo "This should not happen!" && exit 42
#EOF####### END OF SCRIPT AUTOSHUTDOWN.SH ########
