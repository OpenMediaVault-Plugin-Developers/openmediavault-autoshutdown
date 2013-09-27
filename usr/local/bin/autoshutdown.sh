#!/bin/bash

#=======================================================================
#
#          FILE:	autoshutdown.sh
#
#         USAGE:	copy this script to /usr/local/bin and the config-file to /etc
#
#   DESCRIPTION:	shuts down a PC/Server - variable options
#
#  REQUIREMENTS:  	Debian / Ubuntu-based system
#          BUGS:  	---
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

LOGGER="/usr/bin/logger"  	 # path and name of logger (default="/usr/bin/logger")
FACILITY="local6"         	# facility to log to -> see rsyslog.conf

							# for a separate Log:
							# Put the file "autoshutdownlog.conf" in /etc/rsyslog.d/

######## CONSTANT DEFINITION ########
VERSION="0.3.9.2"         # script version information
#CTOPPARAM="-d 1 -n 1"         # define common parameters for the top command line "-d 1 -n 1" (Debian/Ubuntu)
CTOPPARAM="-b -d 1 -n 1"         # define common parameters for the top command line "-b -d 1 -n 1" (Debian/Ubuntu)
STOPPARAM="-i $CTOPPARAM"   # add specific parameters for the top command line  "-i $CTOPPARAM" (Debian/Ubuntu)

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
		PINGLIST="/tmp/pinglist"
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
	if sync; then eval "$SHUTDOWNCOMMAND"; fi
	exit 0
	}

################################################################
#
#   name      : _ident_num_proc
#   parameter   : $1...$(n-1)    : parameter for command 'top'
#            : $n         : search pattern for command 'grep'
#   return      : none
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
				_log "WARN: _ident_num_proc() This should not happen. Exit 42"
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
#   return         : 0      : if no active process has been found
#               : 1 or more      : if at least one active process has been found
#
_check_processes()
{
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
#   return			: 1      : if file has not been found
#   				: 0      : if file has been found
#
# With this plugin-system everyone can check if a specific file exists.
# If it exists, the machine won't shutdown
# You find sample plugins in /etc/autoshutdown.d
#
_check_plugin()
{
	FOUNDVALUE_checkplugin=0
	RVALUE=1

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
		let RVALUE--
	fi
	if $DEBUG ; then _log "DEBUG: _check_plugin(): after all plugin-checks: RVALUE: $RVALUE" ; fi

	return ${RVALUE}
}


################################################################
#
#   name         : _check_loadaverage
#   parameter      : none
#   global return   : none
#   return         : 1      : if loadaverage is higher (greater) than $LOADAVERAGE
#               : 0      : if loadaverage is lower (less) than $LOADAVERAGE
#
# This script checks if the loadaverage is higher than $LOADAVERAGE over the last 1 minute
# if yes -> no shutdown, next cycle
# if no -> next check and shutdown if all cycles failed
#
_check_loadaverage()
{
	RVALUE=1
	CURRENT_LOADAVERAGE_TEMP1="$(top -b -n 1 | grep 'load average')"
	CURRENT_LOADAVERAGE_TEMP2="$(echo $CURRENT_LOADAVERAGE_TEMP1 | awk '{print $11}' | sed 's/,//g')"
	if [ "$CURRENT_LOADAVERAGE_TEMP2" = "0.00" ]; then
		CURRENT_LOADAVERAGE=0
	else
		CURRENT_LOADAVERAGE=$(echo $CURRENT_LOADAVERAGE_TEMP2 | sed 's/[,.]//g' | sed 's/^0*//g')
	fi

	if $DEBUG; then
		_log "DEBUG: -------------------------------------------"
		_log "DEBUG: _check_loadaverage(): Output of: 'top -b -n 1 | grep 'load average'"
		_log "DEBUG: _check_loadaverage(): '$CURRENT_LOADAVERAGE_TEMP1'"
		_log "DEBUG: _check_loadaverage(): CURRENT_LOADAVERAGE_TEMP2: $CURRENT_LOADAVERAGE_TEMP2"
		_log "DEBUG: _check_loadaverage(): CURRENT_LOADAVERAGE: $CURRENT_LOADAVERAGE"
	fi
	
	if [ $CURRENT_LOADAVERAGE -gt $LOADAVERAGE ]; then
		_log "INFO: Loadaverage ($CURRENT_LOADAVERAGE_TEMP2 -> $CURRENT_LOADAVERAGE) is higher than target ($LOADAVERAGE) - no shutdown"
		let RVALUE--
	else
		_log "INFO: Loadaverage ($CURRENT_LOADAVERAGE_TEMP2 -> $CURRENT_LOADAVERAGE) is lower than target ($LOADAVERAGE)"
	fi

	if $DEBUG ; then _log "DEBUG: _check_loadaverage(): RVALUE: $RVALUE" ; fi

	return ${RVALUE}
}


# ################################################################
# #
# #   name         : _check_sabnzbd
# #   parameter      : none
# #   global return   : none
# #   return         : 1      : if sabnzdb is downloading
# #               : 0      : if sabnzdb is not downloading -> ready to shutdown
# #
# # This function checks sabnzbd to see if sabnzbd is currently downloading through the API
# # Original script here: https://forums.sabnzbd.org/viewtopic.php?t=5462#p39170
# #
# _check_sabnzbd()
# {
# 	RVALUE=1
# 	NICNR_SABRANGE="$1"
# 	NOTRAFFIC="0.00"
# 
# 	if $DEBUG; then
# 		_log "DEBUG: _check_sabnzbd(): Check for ${NIC[$NICNR_SABRANGE]} - ${CLASS[$NICNR_SABRANGE]}.${SERVERIP[$NICNR_SABRANGE]}"
# 		_log "DEBUG: _check_sabnzbd(): SABPORT: $SABPORT"
# 		_log "DEBUG: _check_sabnzbd(): SABAPIKEY: $SABAPIKEY"
# 		_log "DEBUG: _check_sabnzbd(): NOTRAFFIC: $NOTRAFFIC"
# 	fi
# 
# 	# Output to std-out, Timeout 5 sec (-T), retries 1 (-t)
# 	SABTRAFFIC="$(wget -q -t 1 -T 5 "http://${CLIENTIP}:${SABPORT}/sabnzbd/api?mode=qstatus&output=xml&apikey=${SABAPIKEY}"  -O - | xmlstarlet sel -t -v qstatus/kbpersec 2&> /dev/null)"
# 
# 	if $DEBUG; then _log "DEBUG: _check_sabnzbd(): SABTRAFFIC: $SABTRAFFIC"; fi
# 
# 	if [ -z $SABTRAFFIC ]; then
# 		_log "INFO: _check_sabnzbd(): couldn't find actual sabnzbd-traffic. Is sabnzbd running?"
# 	elif [ "$SABTRAFFIC" = "$NOTRAFFIC" ]; then
# 		_log "INFO: _check_sabnzbd(): no running downloads."
# 	else
# 		_log "INFO: Sabnzbd: download runniing with $SABTRAFFIC kb/s  - no shutdown."
# 		let RVALUE--
# 	fi
# 	
# 	if $DEBUG ; then _log "DEBUG: _check_sabnzbd(): RVALUE: $RVALUE" ; fi
# 
# 	return ${RVALUE}
# }

################################################################
#
#   name         : _check_net_status
#   parameter      : Array-# of NIC
#   global return   : none
#   return         : 0      : if no active socket has been found
#                  : 1 or more      : if at least one active socket has been found
#
_check_net_status()
{
	NUMPROC=0
	NICNR_NETSTATUS="$1"

	_log "INFO: Check Connections for '${NIC[${NICNR_NETSTATUS}]}'"

	# check for each given socket number in NSOCKETNUMBERS if it is currently stated active in "netstat"
	for NSOCKET in ${NSOCKETNUMBERS//,/ } ; do
		LP=0
		WORD="${CLASS[$NICNR_NETSTATUS]}.${SERVERIP[$NICNR_NETSTATUS]}:$NSOCKET"

		if $DEBUG; then
			_log "DEBUG: The following test for connections can fail, if 'autoshutdown' is running under the wrong user and NETSTATWORD not set in the config."
			_log "DEBUG: See 'readme' for further information about that"
		fi

		# NETSTATWORD is not set in autoshutdown.conf (only needed for CLI-testing the script
		if [ -z $NETSTATWORD ]; then
			if $DEBUG ; then _log "DEBUG: _check_net_status(): netstat -n | grep ESTABLISHED | grep ${WORD}"; fi
			LINES=$(netstat -n | grep ESTABLISHED | grep ${WORD})
		else
			if $DEBUG ; then _log "DEBUG: _check_net_status(): netstat -n | egrep "ESTABLISHED|${NETSTATWORD}" | grep ${WORD}"; fi
			LINES=$(netstat -n | egrep "ESTABLISHED|${NETSTATWORD}" | grep ${WORD})
		fi

		if $DEBUG ; then _log "DEBUG: _check_net_status(): Result: $LINES"; fi # changed LINE in LINES

		#if $DEBUG ; then _log "DEBUG: _check_net_status(): echo ${LINES} | grep -c ${WORD2}"; fi
		RESULT=$(echo ${LINES} | grep -c ${WORD})

		let NUMPROC=$NUMPROC+$RESULT

		if $DEBUG ; then _log "DEBUG: _check_net_status(): Is socket present: $RESULT"; fi

		# Check which IP is connected on the specified Port
		# old:
		# CONIP=$(netstat -an | grep ${WORD1} | echo ${WORD2} | awk '{print $5}'| sed 's/\.[0-9]*$//g' | uniq)

		[[ $(echo ${LINES} | awk '{print $5}') =~ (.*):[0-9]*$ ]] && CONIP=${BASH_REMATCH[1]}

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

	# Extra Samba-Check for connected Clients only if other processes are negative -> [ $NUMPROC -gt 0 ]
	if [ $NUMPROC -gt 0 ]; then
		if [ $(/usr/bin/smbstatus | grep -i "no locked" | wc -l) != "1" ]; then
			_log "INFO: Samba connected -> no shutdown"
			let NUMPROC++
		fi
	fi

	if ! $DEBUG ; then { [ $NUMPROC -gt 0 ] && _log "INFO: Found $NUMPROC active sockets in $NSOCKETNUMBERS" ; }; fi

	if $DEBUG ; then _log "DEBUG: _check_net_status(): $NUMPROC socket(s) active on ${NIC[$NICNR_NETSTATUS]}."; fi

	# return the number of processes we found
	return $NUMPROC

}

################################################################
#
#   name         : _check_ul_dl_rate
#   parameter      : Array-# of NIC
#   global return   : none
#   return         : 1      : if no (not enough) network activity has been found
#               : 0      : if enough network activity has been found
#
# Checks for activity in eth0. It compares the RX and TX bytes
# every cycle to detect if they significantly changed.
# If they haven't, it will force the system to sleep.
#

#ToDo: 
# - Bug-testing

_check_ul_dl_rate()
{
	NICNR_ULDLCHECK="$1"
	
	# creation of the directory is in the main script

	_log "INFO: ULDL-Traffic-Check for '${NIC[${NICNR_ULDLCHECK}]}'"

	# RX in kB
	RX=$(ifconfig ${NIC[${NICNR_ULDLCHECK}]} |grep bytes | awk '{print $2}' | sed 's/bytes://g' | awk '{ printf("%.0f\n", ($1/1024)) }')

	# TX in kB
	TX=$(ifconfig ${NIC[${NICNR_ULDLCHECK}]} |grep bytes | awk '{print $6}' | sed 's/bytes://g' | awk '{ printf("%.0f\n", ($1/1024)) }')

	# Check if RX/TX Files Exist
	if [ -f $RXTXTMPDIR/rx.tmp ] && [ -f $RXTXTMPDIR/tx.tmp ]; then
		if $DEBUG; then _log "DEBUG: _check_ul_dl(): rx.tmp and tx.tmp are existing"; fi
		p_RX=$(cat $RXTXTMPDIR/rx.tmp) ## store previous RX value in p_RX
		p_TX=$(cat $RXTXTMPDIR/tx.tmp) ## store previous TX value in p_TX

		echo $RX > $RXTXTMPDIR/rx.tmp ## Write new packets to RX file
		echo $TX > $RXTXTMPDIR/tx.tmp ## Write new packets to TX file

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

		_log "INFO: ${NIC[${NICNR_ULDLCHECK}]}: DL-Rate over the last $SLEEP seconds: $LAST_DL_RATE kB/s"
		_log "INFO: ${NIC[${NICNR_ULDLCHECK}]}: UL-Rate over the last $SLEEP seconds: $LAST_UL_RATE kB/s"

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
			return 1 # return value -> shutdown
		else
			_log "INFO: ${NIC[${NICNR_ULDLCHECK}]}: UL- or DL-Rate is over $ULDLRATE kB/s -> no shutdown"
			return 0
		fi # > if [ $RX -le $t_RX ] && [ $TX -le $t_TX ]; then

	# RX/TX-Files doesn't Exist
	else
		echo $RX > $RXTXTMPDIR/rx.tmp ## Write new packets to RX file
		echo $TX > $RXTXTMPDIR/tx.tmp ## Write new packets to TX file

		_log "INFO: rx.tmp and/or tx.tmp doesn't exist - writing values to files"

		# This is the obviously the first run, because of tx.tmp and/or rx.tmp doesn't exist - don't shutdown
		return 0
	fi # > # if [ -f $RXTXTMPDIR/rx.tmp ] && [ -f $RXTXTMPDIR/tx.tmp ]; then

	_log "INFO: _check_ul_dl_rate: This should not happen - Exit 42"
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
#   name:	 _check_config
#   parameter : none
#   return: 	none
#

_check_config() {
	## Check Parameters from Config and setting default variables:
	_log "INFO: ------------------------------------------------------"
	_log "INFO: Checking config"

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

	[[ "$CHECKCLOCKACTIVE" = "true" || "$CHECKCLOCKACTIVE" = "false" ]] || { _log "WARN: CHECKCLOCKACTIVE not set properly. It has to be 'true' or 'false'."
			_log "WARN: Set CHECKCLOCKACTIVE to false"
			CHECKCLOCKACTIVE="false"; }

	# Flag: 1 - 999 (cycles)
	[[ "$CYCLES" =~ ^([1-9]|[1-9][0-9]|[1-9][0-9]{2})$ ]] || {
			_log "WARN: Invalid parameter format: Flag"
			_log "WARN: You set it to '$CYCLES', which is not a correct syntax. Only '1' - '999' is allowed."
			_log "WARN: Setting CYCLES to 5"
			CYCLES="5"; }

	[[ "$UPHOURS" =~ ^(([0-1]?[0-9]|[2][0-3])\.{2}([0-1]?[0-9]|[2][0-3]))$ ]] || {
			_log "WARN: Invalid parameter list format: UPHOURS [hour1..hour2]"
			_log "WARN: You set it to '$UPHOURS', which is not a correct syntax. Maybe it's empty?"
			_log "WARN: Setting UPHOURS to 6..20"
			UPHOURS="6..20"; }

	if [ -z "$NETSTATWORD" ]; then
		if $DEBUG; then
			_log "INFO: NETSTATWORD not set in the config. The check for connections, like SSH (Port 22) will not work on the CLI until you set NETSTATWORD"
			_log "INFO: If you run this sript at systemstart with init.d it will work as expected"
			_log "INFO: Read the README for further Infos"
		fi
	else
		[[ "$NETSTATWORD" =~ ^([A-Z]{1,})$ ]] || {
			_log "WARN: Invalid parameter list format: NETSTATWORD [A-Z]"
			_log "WARN: You set it to '$NETSTATWORD', which is not a correct syntax, only UPPERCASE is allowed!"
			_log "WARN: Unsetting NETSTATWORD"
			unset NETSTATWORD; }
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

	if [ -z $PINGLIST ]; then
		[[ "$RANGE" =~ ^([1-9]{1}[0-9]{0,2})?([1-9]{1}[0-9]{0,2}\.{2}[1-9]{1}[0-9]{0,2})?(,[1-9]{1}[0-9]{0,2})*((,[1-9]{1}[0-9]{0,2})\.{2}[1-9]{1}[0-9]{0,2})*$ ]] || {
				_log "WARN: Invalid parameter list format: RANGE [v..v+n,w,x+m..x,y,z..z+o]"
				_log "WARN: You set it to '$RANGE', which is not a correct syntax."
				_log "WARN: Setting RANGE to 2..254"
				RANGE="2..254"; }
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

	# Sleep: 1 - 9999
	[[ "$SLEEP" =~ ^([1-9]|[1-9][0-9]{1,3})$ ]] || {
			_log "WARN: Invalid parameter format: SLEEP (sec)"
			_log "WARN: You set it to '$SLEEP', which is not a correct syntax.  Only '1' - '9999' is allowed. Maybe it's empty?"
			_log "WARN: Setting SLEEP to 180 sec"
			SLEEP=180; }

# 	# $SABNZBDCHECK" = "true"
# 	if [ ! -z "$SABNZBDCHECK" ]; then
# 		[[ "$SABNZBDCHECK" = "true" || "$SABNZBDCHECK" = "false" ]] || { _log "WARN: SABNZBDCHECK not set properly. It has to be 'true' or 'false'."
# 				_log "WARN: Set SABNZBDCHECK to false"
# 				SABNZBDCHECK="false"; }
# 	fi
# 
# 	# SABPORT (max 5 digits)
# 	[[ "$SABPORT" =~ ^([1-9]|[1-9][0-9]{1,4})$ ]] || {
# 		if [ "$SABNZBDCHECK" = "true" ]; then
# 			_log "WARN: Invalid parameter format: SABPORT"
# 			_log "WARN: You set it to '$SABPORT', which is not a correct syntax. Maybe it's empty?"
# 			if [ "$SABNZBDCHECK" = "true" ]; then
# 				_log "WARN: Set SABNZBDCHECK to false, because of invalid portnumber"
# 				SABNZBDCHECK="false"
# 			fi
# 		fi; }
# 
# 	# APIKEY
# 	REGEX="^([A-Za-z0-9]{1,})"
# 	if [ "$SABNZBDCHECK" = "true" ]; then
# 		if [ "$SABAPIKEY" = "" ]; then
# 				_log "WARN: APIKEY for sabnzbd is not set"
# 				if [ "$SABNZBDCHECK" = "true" ]; then
# 					_log "WARN: Set SABNZBDCHECK to false, because of missing APIKEY."
# 					SABNZBDCHECK="false"
# 				fi
# 		else
# 				[[ "$SABAPIKEY" =~ $REGEX ]] || {
# 						_log "WARN: Invalid APIKEY"
# 						_log "WARN: You set it to '$SABAPIKEY', which is not a correct syntax. Only a-zA-Z0-9 is allowed."
# 						if [ "$SABNZBDCHECK" = "true" ]; then
# 							_log "WARN: Set SABNZBDCHECK to false, because of invalid APIKEY"
# 							SABNZBDCHECK="false"
# 						fi; }
# 		fi
# 	fi

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
	if [ ! -z $SHUTDOWNCOMMAND ]; then
		# check, if pm-utils is installed
		if ! which pm-is-supported 1>/dev/null; then
			_log "WARN: SHUTDOWNCOMMAND is set, but pm-is-supported not found"
			_log "WARN: Please install the package pm-utils!"
			_log "WARN: Unset SHUTDOWNCOMMAND -> do normal shutdown"
			unset $SHUTDOWNCOMMAND
		else
			# check POWER MANAGEMENT MODES
			_log "INFO: Your Kernel supports the following modes from pm-utils:"
			pm-is-supported --suspend         && _log "INFO: Kernel supports SUSPEND (SUSPEND to RAM)"
			pm-is-supported --hibernate       && _log "INFO: Kernel supports HIBERNATE (SUSPEND to DISK)"
			pm-is-supported --suspend-hybrid  && _log "INFO: Kernel supports HYBRID-SUSPEND (to DISK & to RAM)"
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
_check_networkconfig() {
	# Read IP-Adress and SERVERIP from e.g. 'ifconfig eth0'
	_log "INFO: ------------------------------------------------------"
	_log "INFO: Reading NICs ,IPs, ..."
	NICNR=0
	FOUNDIP=0
	for NWADAPTERS in bond0 eth0 eth1; do
		let NICNR++
		NIC[$NICNR]=$NWADAPTERS

		if ip link show up | grep $NWADAPTERS > /dev/null; then
			_log "INFO: NIC '$NWADAPTERS' found: try to get IP"

			NW_WAIT=0
			while true; do
				let NW_WAIT++
				if [ $NW_WAIT -le 5 ]; then
					if ! ifconfig $NWADAPTERS | egrep -q "inet "; then
						_log "INFO: _check_networkconfig(): Run: #${NW_WAIT}: No internet-Adress found - wait 60 sec for initializing the network"
						sleep 60
					else
						_log "INFO: _check_networkconfig(): Run: #${NW_WAIT}: IP-Adress found"
						break
					fi
				else
					_log "WARN: No internet-Adress for $NIC[$NICNR] found after 5 minutes - The script will not work maybe ..."
					break
				fi
			done

			IPFROMIFCONFIG[$NICNR]="$(ifconfig $NWADAPTERS | egrep "inet " | sed 's/[ ]*Bcast.*//g; s/.*://g')"
			SERVERIP[$NICNR]="$(echo ${IPFROMIFCONFIG[$NICNR]} | sed 's/.*\.//g')"
			CLASS[$NICNR]="$(echo ${IPFROMIFCONFIG[$NICNR]} | sed 's/\(.*\..*\..*\)\..*/\1/g')"
			_log "INFO: '$NWADAPTERS' has IP: ${IPFROMIFCONFIG[$NICNR]}"

			if $DEBUG; then
				# ifconfig in extra variables for easier debugging
				IPFROMIFCONFIG_DEBUG_1="$(ifconfig $NWADAPTERS | egrep "inet ")"
				IPFROMIFCONFIG_DEBUG_2="$(ifconfig $NWADAPTERS | egrep "inet " | sed 's/[ ]*Bcast.*//g')"
				# Log-Output all the stuff
				_log "DEBUG: ifconfig $NWADAPTERS (Begin) ====================================="
				# Output of ifconfig line for line
				ifconfig $NWADAPTERS | while read IFCONFIGLINE
				do
					_log "DEBUG:           $IFCONFIGLINE"
				done
				_log "DEBUG: ifconfig $NWADAPTERS (End) ======================================="
				_log "DEBUG: IPFROMIFCONFIG_DEBUG_1: $IPFROMIFCONFIG_DEBUG_1"
				_log "DEBUG: IPFROMIFCONFIG_DEBUG_2: $IPFROMIFCONFIG_DEBUG_2"
				_log "DEBUG: _check_networkconfig(): IPFROMIFCONFIG$NICNR: ${IPFROMIFCONFIG[$NICNR]}"
				_log "DEBUG: _check_networkconfig(): SERVERIP$NICNR: ${SERVERIP[$NICNR]}"
				_log "DEBUG: _check_networkconfig(): CLASS$NICNR: ${CLASS[$NICNR]}"
			fi

			# if both variables found, then count 1 up
			if [ ! -z "${SERVERIP[$NICNR]}" ] && [ ! -z "${CLASS[$NICNR]}" ]; then
				let FOUNDIP++

				# bond0 has priority, even if there are eth0 and eth1
				if [ "$NWADAPTERS" = "bond0" ]; then
					_log "INFO: NIC '$NWADAPTERS' found, skipping all others. bond0 has priority"
					break
				fi
			fi

			# Check CLASS and SERVERIP if they are correct
			[[ "${CLASS[$NICNR]}" =~ ^(25[0-5]|2[0-4][0-9]|[0-1]{1}[0-9]{2}|[1-9]{1}[0-9]{1}|[1-9])\.(25[0-5]|2[0-4][0-9]|[0-1]{1}[0-9]{2}|[1-9]{1}[0-9]{1}|[1-9]|0)\.(25[0-5]|2[0-4][0-9]|[0-1]{1}[0-9]{2}|[1-9]{1}[0-9]{1}|[1-9]|0)$ ]] || {
				_log "WARN: Invalid parameter format: Class: nnn.nnn.nnn]"
				_log "WARN: It is set to '${CLASS[$NICNR]}', which is not a correct syntax. Maybe parsing 'ifconfig ' did something wrong"
				_log "WARN: Please report this Bug and the CLI-output of 'ifconfig'"
				_log "WARN: unsetting  $NIC[$NICNR] ..."
				unset NIC[$NICNR]; }

			[[ "${SERVERIP[$NICNR]}" =~ ^(25[0-4]|2[0-4][0-9]|[0-1]{1}[0-9]{2}|[1-9]{1}[0-9]{1}|[1-9])$ ]] || {
				_log "WARN: Invalid parameter format: SERVERIP [iii]"
				_log "WARN: It is set to '${SERVERIP[$NICNR]}', which is not a correct syntax. Maybe parsing 'ifconfig' did something wrong"
				_log "WARN: Please report this Bug and the CLI-output of 'ifconfig'"
				_log "WARN: unsetting  $NIC[$NICNR] ..."
				unset NIC[$NICNR]; }

		else
			_log "INFO: NIC '$NWADAPTERS' not found, skipping '$NWADAPTERS'"
			unset NIC[$NICNR]
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
#               : 1      : if at least one active host has been found
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
				_ping_range $NICNR_CHECKSYSTEMACTIVE
				PINGRANGERETURN="$?"
				if [ "$PINGRANGERETURN" -gt 0 ]; then
					let CNT++
					if $DEBUG; then _log "DEBUG: _ping_range() -> RETURN: $PINGRANGERETURN"; fi
				fi
				if $DEBUG ; then _log "DEBUG: _check_system_active(): call _ping_range -> CNT: $CNT "; fi
			else
				if $DEBUG ; then _log "DEBUG: _check_system_active(): _ping_range not called -> CNT: $CNT "; fi
			fi

			if [ $CNT -eq 0 ]; then
			# PRIO 2: Do a check for some active network sockets, maybe, one never knows...
			# If there is at least one active, we leave this function with a 'bogus find'
				_check_net_status $NICNR_CHECKSYSTEMACTIVE
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
					_check_ul_dl_rate $NICNR_CHECKSYSTEMACTIVE &&
					{
					let CNT++
					}

					if $DEBUG ; then _log "DEBUG: _check_system_active(): call _check_ul_dl_rate -> CNT: $CNT "; fi
				fi
			else
				if $DEBUG ; then _log "DEBUG: _check_system_active(): _check_ul_dl_rate not called -> CNT: $CNT "; fi
			fi   # > if[ $CNT -eq 0 ]; then

# 			if [ $CNT -eq 0 ]; then
# 				# PRIO 4: Sabnzbd-traffic-checked
# 				# Do a check for sabnzbd-downloading
# 				# I've put it here, because every NIC should be checked for sabnzbd-activity
# 				if [ "$SABNZBDCHECK" = "true" ] ; then
# 					_check_sabnzbd $NICNR_CHECKSYSTEMACTIVE &&
# 					{
# 					let CNT++
# 					}
# 
# 					if $DEBUG ; then _log "DEBUG: _check_system_active(): call _check_sabnzbd -> CNT: $CNT "; fi
# 
# 				fi
# 			else
# 				if $DEBUG ; then _log "DEBUG: _check_system_active(): _check_sabnzbd not called -> CNT: $CNT "; fi
# 			fi   # > if[ $CNT -eq 0 ]; then

		fi # >  if [ ! -z "${NIC[$NICNR_CHECKSYSTEMACTIVE]}" ]; then

	done  # > NICNR_CHECKSYSTEMACTIVE in $(seq 1 $NICNR); do

	if [ $CNT -eq 0 ]; then
		# PRIO 4: Do a check for some active processes, maybe, one never knows...
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
		# PRIO 5: Do a PlugIn-Check for any existing files, setup in plugins
		if [ "$PLUGINCHECK" = "true" ] ; then
			_check_plugin &&
				{
				let CNT++
				}

			if $DEBUG ; then _log "DEBUG: _check_system_active(): call _check_plugin -> CNT: $CNT "; fi
		fi
	else
		if $DEBUG ; then _log "DEBUG: _check_system_active(): _check_plugin not called -> CNT: $CNT "; fi
	fi   # > if[ $CNT -eq 0 ]; then

	if [ $CNT -eq 0 ]; then
		# PRIO 6: Do a LOADAVERAGE-Check
		if [ "$LOADAVERAGECHECK" = "true" ] ; then
			_check_loadaverage &&
				{
				let CNT++
				}

			if $DEBUG ; then _log "DEBUG: _check_system_active(): call _check_loadaverage -> CNT: $CNT "; fi
		fi
	else
		if $DEBUG ; then _log "DEBUG: _check_system_active(): _check_loadaverage not called -> CNT: $CNT "; fi
	fi   # > if[ $CNT -eq 0 ]; then

	return ${CNT};
}

###############################################################
######## START OF BODY FUNCTION SCRIPT AUTOSHUTDOWN.SH ########
###############################################################

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
_check_networkconfig

#### Testing fping ####
if ! which fping > /dev/null; then
	echo "WARN: fping not found! Please install it with 'apt-get install fping'"
	_log "WARN: fping not found! Please install it with 'apt-get install fping'"
	exit 1
fi

# If the pinglist or pinglistactive exists, delete it (at every start of the script)
if [ -f /tmp/pinglist ]; then
	rm -f /tmp/pinglist 2> /dev/null
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
	_log "DEBUG: LOADPROCNAMES: $LOADPROCNAMES"
	_log "DEBUG: NSOCKETNUMBERS: $NSOCKETNUMBERS"
	_log "DEBUG: TEMPPROCNAMES: $TEMPPROCNAMES"
# 	_log "DEBUG: STATUSFILECHECK: $STATUSFILECHECK"
# 	_log "DEBUG: STATUSFILEDIR: $STATUSFILEDIR"
	_log "DEBUG: VERBOSE: $VERBOSE"
	_log "DEBUG: FAKE: $FAKE"
	_log "DEBUG: SHUTDOWNCOMMAND: $SHUTDOWNCOMMAND"
	_log "DEBUG: NETSTATWORD: $NETSTATWORD"
# 	_log "DEBUG: SABNZBDCHECK: $SABNZBDCHECK"
# 	_log "DEBUG: SABPORT: $SABPORT"
# 	_log "DEBUG: SABAPIKEY: $SABAPIKEY"
	_log "DEBUG: PLUGINCHECK: $PLUGINCHECK"
	_log "DEBUG: ULDLCHECK: $ULDLCHECK"
	_log "DEBUG: ULDLRATE: $ULDLRATE"
	_log "DEBUG: LOADAVERAGECHECK: $LOADAVERAGECHECK"
	_log "DEBUG: LOADAVERAGE: $LOADAVERAGE"
	# List all PlugIns
	_log "DEBUG: PlugIns found in /etc/autoshutdown.d:"
	for ASD_plugin_firstcheck in /etc/autoshutdown.d/*; do
		_log "DEBUG: Plugin: $ASD_plugin_firstcheck"
	done
fi   # > if $DEBUG ;then

_log "INFO:---------------- script started ----------------------"
_log "INFO: ${CYCLES} test cycles until shutdown is issued."

# Creation of the dir for ULDLCHECK
RXTXTMPDIR="/tmp/autoshutdown_tx_rx"
if [ "$ULDLCHECK" = "true" ]; then
	if [ ! -d $RXTXTMPDIR ]; then
			if $DEBUG ; then _log "DEBUG: _check_ul_dl_rate(): creating tmpdir: $RXTXTMPDIR"; fi
			mkdir $RXTXTMPDIR && _log "DEBUG: _check_ul_dl_rate(): $RXTXTMPDIR created successfully"
		else
			if $DEBUG ; then _log "DEBUG: _check_ul_dl_rate(): tmpdir: $RXTXTMPDIR exists"; fi
	fi
	# clearing for the first run of ULDLCHECK
	if [ -f $RXTXTMPDIR/tx.tmp ]; then
		rm $RXTXTMPDIR/tx.tmp && if $DEBUG; then _log "DEBUG: $RXTXTMPDIR/tx.tmp deleted @ start of script"; fi
	fi
	if [ -f $RXTXTMPDIR/rx.tmp ]; then
		rm $RXTXTMPDIR/rx.tmp && if $DEBUG; then _log "DEBUG: $RXTXTMPDIR/rx.tmp deleted @ start of script"; fi
	fi
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
