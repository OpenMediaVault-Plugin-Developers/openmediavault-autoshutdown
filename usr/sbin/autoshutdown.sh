#!/bin/bash
#==============================================================================
#
#          FILE:    autoshutdown.sh
#
#         USAGE:    copy this script to /usr/sbin and the config-file to /etc
#
#   DESCRIPTION:    shuts down a PC/Server - variable options
#
#  REQUIREMENTS:    Debian / Ubuntu-based system
#
#          BUGS:    if you find any: https://github.com/OpenMediaVault-Plugin-Developers/openmediavault-autoshutdown
#
#        AUTHOR:    Solo0815 - R. Lindlein (Ubuntu-Port, OMV-Changes), it should work on any Debain-based System, too
#                   based on autoshutdown.sh v0.7.008 by chrikai, see:
#                   https://sourceforge.net/apps/phpbb/freenas/viewtopic.php?f=12&t=2158&start=60
#==============================================================================

# Changelog:    see extra file!

######## VARIABLE DEFINITION ########
RESULT=0                    # Declare reusable RESULT variable to check function return values

# Variables that normal users should normaly not define - PowerUsers can do it here or add it to the config
LPREPEAT=5                  # Number of test cycles for finding and active LOADPROCNAMES-Process (default=5)
TPREPEAT=5                  # Number of test cycles for finding and active TEMPPROCNAMES-Process (default=5)

############## LOGGING ##############
FACILITY="local6"           # Facility to log to -> see rsyslog.conf
DEBUG="false"               # Default debug logging mode is enabled
VERBOSE="false"             # Default if verbose logging mode is enabled
SYSLOG="false"              # Default if logging should go to syslog

FAKE="false"                # Default fake mode operation

######## STORAGE DEFINITION #########
declare -A p_HDDIO_DEVS     # Associative array for storing _check_hddio read and wrtn values

######## CONSTANT DEFINITION ########
CTOPPARAM="-b -d 1 -n 1"    # Define common parameters for the top command line "-b -d 1 -n 1" (Debian/Ubuntu)
STOPPARAM="-i $CTOPPARAM"   # Add specific parameters for the top command line  "-i $CTOPPARAM" (Debian/Ubuntu)

# tmp-directory
TMPDIR="/tmp/autoshutdown"


######## FUNCTION DECLARATION ########

###############################################################################
#
#   name          : _log
#   parameter     : $1: Log message in format "PRIORITY: MESSAGE"
#                 : $2: 'force' will force logging to syslog and sent to stderr
#   return        : none
#
_log()
{
    [[ "${1}" =~ ^([A-Za-z]*):\ *(.*) ]] && {
       local priority=${BASH_REMATCH[1]}
       local message=${BASH_REMATCH[2]}
    }
    [ "${FAKE}" == "true" ] && message="FAKE-Mode: ${message}"
    message="$(basename "${0%.*}")[$$]: ${priority}: '${message}'"

    [[ "${VERBOSE}" == "true" || "${FAKE}" == "true" ]] &&
        echo "$(date '+%b %e %H:%M:%S') ${USER}: ${message}"

    local stderr=""
    [ "${2}" == "force" ] && stderr="--stderr"
    [[ "${SYSLOG}" == "true" || "${2}" == "force" ]] &&
        logger "${stderr}" -p "${FACILITY}.${priority}" "${message}"
}


###############################################################################
#
#   name          : _ping_range
#   parameter     : none
#   return        : CNT : Number of active IP hosts within given IP range
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


###############################################################################
#
#   name          : _shutdown
#   parameter     : none
#   return        : none, script exit point
#
_shutdown()
{
    # We've had no responses for the required number of consecutive scans
    # defined in CYCLES shutdown & power off.

    if [ -z "${SHUTDOWNCOMMAND}" ]; then
        SHUTDOWNCOMMAND="shutdown -h now"
        _log "INFO: No shutdown command set: setting it to '${SHUTDOWNCOMMAND}'"
    fi

    # When FAKE-Mode is on:
    [ "$FAKE" == "true" ] && {
        _log "INFO: Fake-shutdown issued: '${SHUTDOWNCOMMAND}' - Command is not executed because of Fake-Mode" force
        _log "INFO: autoshutdowe will end here."
        _log "INFO:"
        exit 0
    }

    # Without Fake-Mode:
    _log "INFO: Shutdown issued: '${SHUTDOWNCOMMAND}'" force
    _log "INFO:"

    # Write everything to disk/stick and shutdown, hibernate, $whatever is
    # configured.
    if sync; then eval "${SHUTDOWNCOMMAND}" && exit 0; fi
    # Sleep 5 minutes to allow the /etc/init.d/autoshutdown to kill the script
    # and give the right log-message. If we exit here immediately, there are
    # errors in the log.
    sleep 5m
    # We need this just for debugging - the system should be shutdown here.
    _log "INFO: 5 minutes are over" force
    sleep 5m
    _log "INFO: Another 5 minutes are over" force
    exit 0
}


###############################################################################
#
#   name          : _ident_num_proc
#   parameter     : $1...$(n-1) : Parameter for command 'top'
#                 : $n          : Search pattern for command 'grep'
#   return        : $NUMOFPROCESSES
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
            _log "ERR: _ident_num_proc() This should not happen. Exit 42"
            ;;
    esac

    let NUMOFPROCESSES=$NUMOFPROCESSES_PS+$NUMOFPROCESSES_TOP
    if $DEBUG; then
        _log "DEBUG: _ident_num_proc(): NUMOFPROCESSES_PS: $NUMOFPROCESSES_PS"
        _log "DEBUG: _ident_num_proc(): NUMOFPROCESSES_TOP: $NUMOFPROCESSES_TOP"
    fi

    return $NUMOFPROCESSES
}


###############################################################################
#
#   name          : _check_processes
#   parameter     : none
#   global return : none
#   return        : 0         : If no active process has been found
#                 : 1 or more : If at least one active process has been found
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
    for LPROCESS in ${LOADPROCNAMES//,/ }; do
        LP=0
        IPROC=0
        for ((N=0;N < ${LPREPEAT};N++ )); do
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

    if ! $DEBUG ; then { [ $NUMPROC -gt 0 ] && _log "INFO: Found $NUMPROC active processes in $LOADPROCNAMES"; }; fi

    # check for each given command name in TEMPPROCNAMES if it is currently stated present in "top"
    # i found, that for sshd, ... there are processes only present in "ps" or "top" output when is is used.
    # it can not be guaranteed, that top states these services active, as they usually wait for user input
    # no "-I" parameter on the command line, but shear presence is enough
    for TPROCESS in ${TEMPPROCNAMES//,/ }; do
        TP=0
        IPROC=0
        for ((N=0;N < ${TPREPEAT};N++ )); do
            _ident_num_proc ${CTOPPARAM} ${TPROCESS} tempproc
            RESULT=$?
            TP=$(($TP|$RESULT))
            [ $RESULT -gt 0 ] && let IPROC++
        done

        let CHECK=$CHECK+$TP

        if ! $DEBUG ; then { [ $TP -gt 0 ] && _log "INFO: _check_processes(): Found active process $TPROCESS"; }; fi

        if $DEBUG ; then _log "DEBUG: _check_processes(): > $TPROCESS: found $IPROC of $TPREPEAT cycles active"; fi

    done   # > for TPROCESS in ${TEMPPROCNAMES//,/ } ; do

    if ! $DEBUG ; then { [ $CHECK -gt 0 ] &&_log "INFO: Found $CHECK active processes in $TEMPPROCNAMES"; }; fi

    let NUMPROC=$NUMPROC+$CHECK

    if $DEBUG ; then _log "DEBUG: _check_processes(): $NUMPROC process(es) active."; fi

    # only return we found a process
    return $NUMPROC
}


###############################################################################
#
#   name          : _check_plugin
#   parameter     : none
#   global return : none
#   return        : 0 : If file has not been found
#                 : 1 : If file has been found
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
            _log "DEBUG: -----------------------------------------------------"
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
                    _log "INFO: _check_plugin(): PlugIn: ${PLUGIN_name[$ASD_pluginNR]} -> content found (${PLUGIN_content[$ASD_pluginNR]}) - no shutdown"
                    let FOUNDVALUE_checkplugin++
                else
                    # content not found
                    _log "INFO: _check_plugin(): PlugIn: ${PLUGIN_name[$ASD_pluginNR]} -> content not found (${PLUGIN_content[$ASD_pluginNR]})"
                fi

            # content not defined and file found
            else
                _log "INFO: _check_plugin(): PlugIn: ${PLUGIN_name[$ASD_pluginNR]} -> File found - no shutdown"
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


###############################################################################
#
#   name          : _check_loadaverage
#   parameter     : none
#   global return : none
#   return        : 1 : If loadaverage is higher (greater) than $LOADAVERAGE, no shutdown
#                 : 0 : If loadaverage is lower (less) than $LOADAVERAGE
#
# This script checks if the loadaverage is higher than $LOADAVERAGE over the last 1 minute
# if yes -> no shutdown, next cycle
# if no  -> next check and shutdown if all cycles failed
#
_check_loadaverage()
{
    # ## disabled for testing
    # _log "DEBUG: _check_loadaverage() disabled for testing"
    # return 0

    local RVALUE=0
    # Get the load averages.
    local CURRENT_LOAD_AVERAGE_LINE
    CURRENT_LOAD_AVERAGE_LINE="$(LC_ALL=C cat "/proc/loadavg")"
    # Get load average in decimal notation.
    local CURRENT_LOAD_AVERAGE_DECIMAL
    CURRENT_LOAD_AVERAGE_DECIMAL="$(awk '{print $1}' <<< "${CURRENT_LOAD_AVERAGE_LINE}")"
    # Convert to integer value by removing decimal point and assuming two fixed decimal places.
    local CURRENT_LOAD_AVERAGE
    CURRENT_LOAD_AVERAGE="$(sed 's/[.]//;s/^0*//g;s/^$/0/' <<< "${CURRENT_LOAD_AVERAGE_DECIMAL}")"

    if "${DEBUG}"; then
        _log "DEBUG: -----------------------------------------------------"
        _log "DEBUG: _check_loadaverage(): Output from '/proc/loadavg': ${CURRENT_LOAD_AVERAGE_LINE}"
        _log "DEBUG: _check_loadaverage(): CURRENT_LOAD_AVERAGE_DECIMAL: ${CURRENT_LOAD_AVERAGE_DECIMAL}"
        _log "DEBUG: _check_loadaverage(): CURRENT_LOAD_AVERAGE: ${CURRENT_LOAD_AVERAGE}"
    fi

    local MSG="INFO: _check_loadaverage(): Load average (${CURRENT_LOAD_AVERAGE_DECIMAL} -> ${CURRENT_LOAD_AVERAGE}) is"
    if [ "${CURRENT_LOAD_AVERAGE}" -gt "${LOADAVERAGE}" ]; then
        MSG+=" higher than target (${LOADAVERAGE}) - no shutdown"
        RVALUE=1
    else
        MSG+=" lower than target (${LOADAVERAGE})"
    fi
    _log "${MSG}"

    if "${DEBUG}"; then _log "DEBUG: _check_loadaverage(): RVALUE: ${RVALUE}"; fi

    return "${RVALUE}"
}


###############################################################################
#
#   name          : _check_net_status
#   parameter     : Array-# of NIC
#   global return : none
#   return        : 0         : If no active socket has been found, ready for shutdown
#                 : 1 or more : If at least one active socket has been found, no shutdown
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
        IP="${CLASS[$NICNR_NETSTATUS]}.${SERVERIP[$NICNR_NETSTATUS]}"

        LINES="$(ss -n | awk -v regex="^([[]::ffff:)?${IP}[]]?:${NSOCKET}$" '$2 ~ /^ESTAB$/ && $5 ~ regex')"

        if $DEBUG ; then _log "DEBUG: _check_net_status(): Result: $LINES"; fi # changed LINE in LINES

        let NUMPROC+="$([ -n "${LINES}" ] && wc -l <<< "${LINES}" || echo -n "0")"

        if $DEBUG ; then _log "DEBUG: _check_net_status(): Is socket present: $([ -n "${LINES}" ] && echo -n "true" || echo -n "false")"; fi

        CONIPS="$(awk '{gsub(/^([[]::ffff:)?/,"",$6);gsub(/[]]?:[0-9]+$/,"",$6); print $6}' <<< "${LINES}" |
                    sort -u)"

        # Set PORTPROTOCOL - only default ports are defined here
        case $NSOCKET in
            80|8080) PORTPROTOCOL="HTTP" ;;
            22)      PORTPROTOCOL="SSH" ;;
            21)      PORTPROTOCOL="FTP" ;;
            139|445) PORTPROTOCOL="SMB/CIFS" ;;
            443)     PORTPROTOCOL="HTTPS" ;;
            548)     PORTPROTOCOL="AFP" ;;
            873)     PORTPROTOCOL="RSYNC" ;;
            3306)    PORTPROTOCOL="MYSQL" ;;
            3689)    PORTPROTOCOL="DAAP" ;;
            6991)    PORTPROTOCOL="BITTORRENT" ;;
            9091)    PORTPROTOCOL="BITTORRENT_WEBIF" ;;
            49152)   PORTPROTOCOL="UPNP" ;;
            51413)   PORTPROTOCOL="BITTORRENT" ;;
            *)       PORTPROTOCOL="unknown" ;;
        esac

        if [ -n "${LINES}" ]; then _log "INFO: _check_net_status(): Found active connection on port $NSOCKET ($PORTPROTOCOL) from ${CONIPS//$'\n'/, }"; fi

    done   # > NSOCKET in ${NSOCKETNAMES//,/ } ; do

    # Extra check to detect established connection in a container from a host port.
    _check_docker_status
    let NUMPROC+=${?}

    if ! $DEBUG ; then { [ $NUMPROC -gt 0 ] && _log "INFO: Found $NUMPROC active socket(s) from Port(s): $NSOCKETNUMBERS" ; }; fi

    if $DEBUG ; then _log "DEBUG: _check_net_status(): $NUMPROC socket(s) active on ${NIC[$NICNR_NETSTATUS]}."; fi

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

    # return the number of processes we found
    return $NUMPROC
}


###############################################################################
#
#   name          : _check_docker_status
#   parameter     : none
#   global return : none
#   return        : 0         : If no active socket has been found, ready for shutdown
#                 : 1 or more : If at least one active socket has been found, no shutdown
#
_check_docker_status()
{
    command -v docker &>- || return 0
    local active=0
    for container in $(docker ps --format "{{ .Names }}"); do
        local details; read -ra details <<< "$(docker inspect --format \
            '{{ .State.Pid }} {{ .NetworkSettings.IPAddress }}
             {{- ""}} {{ range $key, $value := .NetworkSettings.Ports }}
                {{- ""}}{{ range . }}{{ .HostPort }}:{{ index (split $key "/") 0 }}
                {{- ""}}{{ end }}
             {{- ""}} {{ end }}' \
            "${container}")"
        [[ "${#details[@]}" -eq 0 || ! ("${details[*]}" =~ :) ]] && continue
        local port_map=()
        for ports in "${details[@]: -2}"; do
            if [[ "${ports}" =~ - ]]; then
                local host_map;
                mapfile -t host_map < <(seq $(sed 's:-: :' <<< "${ports%:*}"))
                local con_map;
                mapfile -t con_map < <(seq $(sed 's:-: :' <<< "${ports#*:}"))
                for index in "${!host_map[@]}"; do
                    [[ "${NSOCKETNUMBERS}," == *",${host_map["${index}"]},"* ]] &&
                        port_map["${host_map["${index}"]}"]="${con_map["${index}"]}";
                done
                continue
            fi
            [[ "${NSOCKETNUMBERS}," == *",${ports#*:},"* ]] &&
                port_map["${ports%:*}"]="${ports#*:}"
        done
        [ "${#port_map[@]}" -eq 0 ] && continue
        for target in "${!port_map[@]}"; do
            local lines; lines="$(
                nsenter -t "${details[0]}" -n ss -n |
                awk -v \
                    regex="^([[]::ffff:)?${details[1]}[]]?:${port_map[${target}]}$" \
                    '$2 ~ /^ESTAB$/ && $5 ~ regex' ||
                true)"
            local con_ips; con_ips="$(
                awk '{gsub(/^([[]::ffff:)?/,"",$6);
                      gsub(/[]]?:[0-9]+$/,"",$6);
                      print $6}' <<< "${lines}" |
                sort -u)"
            [ -n "${lines}" ] &&
                { (( active+="$(wc -l <<< "${lines}")" ));
                  _log "INFO: _check_docker_status(): Found active connection on port ${target} (${container}) from ${con_ips//$'\n'/, }"; }
        done
    done
    return "${active}"
}


###############################################################################
#
#   name          : _check_ul_dl_rate
#   parameter     : Array-# of NIC
#   global return : none
#   return        : 0 : I no (not enough) network activity has been found, ready for shutdown
#                 : 1 : If enough network activity has been found, no shutdown
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

    _log "ERR: _check_ul_dl_rate: This should not happen - Exit 42"
    exit 42
}


###############################################################################
#
#   name          : _check_clock
#   parameter     : UPHOURS : range of hours, where system should go to sleep, e.g. 6..20
#   global return : none
#   return        : 0 : If actual value of hours is in DOWN range, ready for shutdown
#                 : 1 : If actual value of hours is in UP range, no shutdown
#
_check_clock()
{
    CLOCKOK=true

    if [[ "$UPHOURS" =~ ^([0-9]{1,2})\.{2}([0-9]{1,2}$) ]]; then
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


###############################################################################
#
#   name          : _check_hddio
#   parameter     : HDDIO_RATE : Rate in kB/s of HDD-IO
#   global return : none
#   return        : 0 : If actual value of hddio is lower than the defined value, ready for shutdown
#                 : 1 : If actual value of hddio is higher than the defined value, no shutdown
#
_check_hddio()
{
    # ## disabled for testing
    # _log "DEBUG: _check_processes() disabled for testing"
    # return 0

    local RVALUE=0

    if "${DEBUG}"; then
        _log "DEBUG: _check_hddio(): HDDIO_RATE: ${HDDIO_RATE} kB/s"
    fi

    while read -r OMV_HDD OMV_ASD_HDD_IN OMV_ASD_HDD_OUT; do
        if "${DEBUG}"; then
            _log "DEBUG: _check_hddio(): ========== Device: ${OMV_HDD} =========="
        fi

        if ! mount -l | grep -q "${OMV_HDD}"; then
            if "${DEBUG}"; then
                _log "DEBUG: _check_hddio(): Skipping as no mount point"
            fi
            continue
        fi

        if "${DEBUG}"; then
            blkid -s LABEL -s UUID | grep "${OMV_HDD}" | while read -r line; do
                _log "DEBUG: _check_hddio(): ${line}"
            done
            _log "DEBUG: _check_hddio(): actual: kB_read: ${OMV_ASD_HDD_IN}, kB_wrtn: ${OMV_ASD_HDD_OUT}"
        fi

        if [[ "${RVALUE}" -eq 1 ||
              -z "${p_HDDIO_DEVS["${OMV_HDD}_r"]:-}" ||
              -z "${p_HDDIO_DEVS["${OMV_HDD}_w"]:-}" ]]; then
            # Store current value.
            p_HDDIO_DEVS["${OMV_HDD}_r"]="${OMV_ASD_HDD_IN}"
            p_HDDIO_DEVS["${OMV_HDD}_w"]="${OMV_ASD_HDD_OUT}"

            if "${DEBUG}"; then
                _log "DEBUG: _check_hddio(): Store new read/write value for device"
            fi
            continue
        fi

        if "${DEBUG}"; then
            _log "DEBUG: _check_hddio(): previous: kB_read: ${p_HDDIO_DEVS["${OMV_HDD}_r"]}, kB_wrtn: ${p_HDDIO_DEVS["${OMV_HDD}_w"]}"
        fi

        # Calculate threshold limit (defined kB/s multiplied with $SLEEP) to get the total value of kB over the $SLEEP-time
        local HDDIO_INCREASE="$(("${HDDIO_RATE}" * "${SLEEP}"))"

        # Calculate the total value
        local t_HDDIO_READ="$(("${p_HDDIO_DEVS["${OMV_HDD}_r"]}" + "${HDDIO_INCREASE}"))"
        local t_HDDIO_WRITE="$(("${p_HDDIO_DEVS["${OMV_HDD}_w"]}" + "${HDDIO_INCREASE}"))"

        # Calculate difference between the last and the actual value
        local diff_HDDIO_READ="$(("${OMV_ASD_HDD_IN}" - "${p_HDDIO_DEVS["${OMV_HDD}_r"]}"))"
        local diff_HDDIO_WRITE="$(("$OMV_ASD_HDD_OUT" - "${p_HDDIO_DEVS["${OMV_HDD}_w"]}"))"

        # Calculate hddio-rate in kB/s - format xx.x
        local LAST_HDDIO_READ_RATE;
        LAST_HDDIO_READ_RATE="$(awk '{printf("%.1f",($1/$2))}' <<< "${diff_HDDIO_READ} ${SLEEP}")"
        local LAST_HDDIO_WRITE_RATE;
        LAST_HDDIO_WRITE_RATE="$(awk '{printf("%.1f",($1/$2))}' <<< "${diff_HDDIO_WRITE} ${SLEEP}")"

        # If hddio bytes have not increased over given value
        if "${DEBUG}"; then
            _log "DEBUG: _check_hddio(): HDDIO_INCREASE: ${HDDIO_INCREASE}"
            _log "DEBUG: _check_hddio(): t_HDDIO_READ: ${t_HDDIO_READ}"
            _log "DEBUG: _check_hddio(): diff_HDDIO_READ: ${diff_HDDIO_READ}"
            _log "DEBUG: _check_hddio(): t_HDDIO_WRITE: ${t_HDDIO_WRITE}"
            _log "DEBUG: _check_hddio(): diff_HDDIO_WRITE: ${diff_HDDIO_WRITE}"
            _log "DEBUG: _check_hddio(): check: 'OMV_ASD_HDD_IN: ${OMV_ASD_HDD_IN}' <= 't_HDDIO_READ: ${t_HDDIO_READ}'"
            _log "DEBUG: _check_hddio(): check: 'OMV_ASD_HDD_OUT: ${OMV_ASD_HDD_OUT}' <= 't_HDDIO_WRITE: ${t_HDDIO_WRITE}'"
        fi

        # Store current value.
        p_HDDIO_DEVS["${OMV_HDD}_r"]="${OMV_ASD_HDD_IN}"
        p_HDDIO_DEVS["${OMV_HDD}_w"]="${OMV_ASD_HDD_OUT}"

        local MSG="INFO: _check_hddio(): Device: ${OMV_HDD} (last ${SLEEP}s) "
              MSG+="kB_aread/s: ${LAST_HDDIO_READ_RATE}, "
              MSG+="kB_wrtn/s: ${LAST_HDDIO_WRITE_RATE}"

        if [[ "${OMV_ASD_HDD_IN}" -gt "${t_HDDIO_READ}" ||
              "${OMV_ASD_HDD_OUT}" -gt "${t_HDDIO_WRITE}" ]]; then
            _log "${MSG} is over: ${HDDIO_RATE} kB/s -> no shutdown"
            RVALUE=1
        else
            _log "${MSG} is under: ${HDDIO_RATE} kB/s -> next HDD"
        fi

    done < <(iostat -kdyNz | tail -n +4 | awk '!/^$/{print $1 " " $5 " " $6}')

    if "${DEBUG}"; then _log "DEBUG: _check_hddio(): RVALUE: ${RVALUE}"; fi

    # No HDD-IO is over the defined value -> shutdown
    _log "INFO: _check_hddio(): All checks complete"

    return "${RVALUE}"
}


###############################################################################
#
#   name          : _check_config
#   parameter     : none
#   return        : none
#
_check_config()
{
    ## Check Parameters from Config and setting default variables:
    _log "INFO: ------------------------------------------------------"
    _log "INFO: Checking config"

    [[ "$ENABLE" = "true" || "$ENABLE" = "false" ]] || {
        _log "WARNING: ENABLE not set properly. It has to be 'true' or 'false'"
        _log "WARNING: Set ENABLE to false -> exiting here ..."
        exit 0; }

    [[ "$FAKE" = "true" || "$FAKE" = "false" ]] || {
        _log "WARNING: FAKE not set properly. It has to be 'true' or 'false'"
        _log "WARNING: Set FAKE to true -> Testmode with VERBOSE on"
        FAKE="true"; }

    if [ ! -z "$PLUGINCHECK" ]; then
        [[ "$PLUGINCHECK" = "true" || "$PLUGINCHECK" = "false" ]] || {
            _log "WARNING: AUTOUNRARCHECK not set properly. It has to be 'true' or 'false'."
            _log "WARNING: Set PLUGINCHECK to false"
            PLUGINCHECK="false"; }
    fi

    # Flag: 1 - 999 (cycles)
    [[ "$CYCLES" =~ ^([1-9]|[1-9][0-9]|[1-9][0-9]{2})$ ]] || {
        _log "WARNING: Invalid parameter format: Flag"
        _log "WARNING: You set it to '$CYCLES', which is not a correct syntax. Only '1' - '999' is allowed."
        _log "WARNING: Setting CYCLES to 5"
        CYCLES="5"; }

    # CheckClockActive together with UPHOURS
    [[ "$CHECKCLOCKACTIVE" = "true" || "$CHECKCLOCKACTIVE" = "false" ]] || {
        _log "WARNING: CHECKCLOCKACTIVE not set properly. It has to be 'true' or 'false'."
        _log "WARNING: Set CHECKCLOCKACTIVE to false"
        CHECKCLOCKACTIVE="false"; }

    # Check UpHours only if CHECKCLOCKACTIVE is "true"
    if [ "$CHECKCLOCKACTIVE" = "true" ]; then
        [[ "$UPHOURS" =~ ^(([0-1]?[0-9]|[2][0-3])\.{2}([0-1]?[0-9]|[2][0-3]))$ ]] || {
            _log "WARNING: Invalid parameter list format: UPHOURS [hour1..hour2]"
            _log "WARNING: You set it to '$UPHOURS', which is not a correct syntax. Maybe it's empty?"
            _log "WARNING: Setting UPHOURS to 6..20"
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
            _log "WARNING: Invalid parameter list format: LOADPROCNAMES [lproc1,lproc2,lproc3,...]"
            _log "WARNING: You set it to '$LOADPROCNAMES', which is not a correct syntax."
            _log "WARNING: exiting ..."
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
            _log "WARNING: Invalid parameter list format: TEMPPROCNAMES [tproc1,tproc2,tproc3,...]"
            _log "WARNING: You set it to '$TEMPPROCNAMES', which is not a correct syntax."
            _log "WARNING: exiting ..."
            exit 1; }
    fi

    # Port-Numbers with at least 2 digits
    [[ "$NSOCKETNUMBERS" =~ ^([0-9]{2,5})+(,[0-9]{2,5})*$ ]] || {
            _log "WARNING: Invalid parameter list format: NSOCKETNUMBERS [nsocket1,nsocket2,nsocket3,...]"
            _log "WARNING: You set it to '$NSOCKETNUMBERS', which is not a correct syntax. Maybe it's empty? Only  Port-Numbers with at least 2 digits are allowed."
            _log "WARNING: Setting NSOCKETNUMBERS to 21,22 (FTP and SSH)"
            NSOCKETNUMBERS="22"; }

    # Pinglist
    IPCHECK=true
    if [ -z $PINGLIST ]; then
        if [ "$RANGE" = "-" ]; then
                _log "INFO: RANGE is set to '-' -> no IP-Check"
                IPCHECK=false
        else
            [[ "$RANGE" =~ ^([1-9]{1}[0-9]{0,2})?([1-9]{1}[0-9]{0,2}\.{2}[1-9]{1}[0-9]{0,2})?(,[1-9]{1}[0-9]{0,2})*((,[1-9]{1}[0-9]{0,2})\.{2}[1-9]{1}[0-9]{0,2})*$ ]] || {
                    _log "WARNING: Invalid parameter list format: RANGE [v..v+n,w,x+m..x,y,z..z+o]"
                    _log "WARNING: You set it to '$RANGE', which is not a correct syntax."
                    _log "WARNING: Setting RANGE to 2..254"
                    RANGE="2..254"; }
        fi
    else
        if [ -f "$PINGLIST" ]; then
            _log "INFO: PINGLIST is set in the conf, reading IPs from '$PINGLIST'"
            USEOWNPINGLIST="true"
        else
            _log "WARNING: PINGLIST is set in the conf, but the file isn't there"
            _log "WARNING: Setting RANGE to 2..254"
            RANGE="2..254"
        fi
    fi

    # $HDDIOCHECK" = "true"
    if [ ! -z "$HDDIOCHECK" ]; then
        [[ "$HDDIOCHECK" = "true" || "$HDDIOCHECK" = "false" ]] || {
            _log "WARNING: HDDIOCHECK not set properly. It has to be 'true' or 'false'."
            _log "WARNING: Set HDDIOCHECK to false"
            HDDIOCHECK="false"; }
    fi

    # HDDIO
    if [ "$HDDIOCHECK" = "true" ]; then
        # HDDIO_RATE (max 6 digits -> 1 - 999999 kB/s)
        [[ "$HDDIO_RATE" =~ ^([1-9]|[1-9][0-9]{1,5})$ ]] || {
            _log "WARNING: Invalid parameter format: HDDIO_RATE"
            _log "WARNING: You set it to '$HDDIO_RATE', which is not a correct syntax. Maybe it's empty?"
            _log "WARNING: Set HDDIO_RATE to 500"
            HDDIO_RATE=500; }
    else
        _log "WARNING: HDDIOCHECK is set to false"
        _log "WARNING: Ignoring HDDIO_RATE"
        HDDIOCHECK="false"
    fi

    # Sleep: 1 - 9999
    [[ "$SLEEP" =~ ^([1-9]|[1-9][0-9]{1,3})$ ]] || {
        _log "WARNING: Invalid parameter format: SLEEP (sec)"
        _log "WARNING: You set it to '$SLEEP', which is not a correct syntax.  Only '1' - '9999' is allowed. Maybe it's empty?"
        _log "WARNING: Setting SLEEP to 180 sec"
        SLEEP=180; }

    # $ULDLCHECK" = "true"
    if [ ! -z "$ULDLCHECK" ]; then
        [[ "$ULDLCHECK" = "true" || "$ULDLCHECK" = "false" ]] || {
            _log "WARNING: ULDLCHECK not set properly. It has to be 'true' or 'false'."
            _log "WARNING: Set ULDLCHECK to false"
            ULDLCHECK="false"; }
    fi

    # ULDLRATE (max 6 digits -> 1 - 999999 kB/s)
    if [ "$ULDLCHECK" = "true" ]; then
        [[ "$ULDLRATE" =~ ^([1-9]|[1-9][0-9]{1,5})$ ]] || {
            _log "WARNING: Invalid parameter format: ULDLRATE"
            _log "WARNING: You set it to '$ULDLRATE', which is not a correct syntax. Maybe it's empty?"
            _log "WARNING: Set ULDLRATE to 50"
            ULDLRATE=50; }
    else
        _log "WARNING: ULDLCHECK is set to false"
        _log "WARNING: Ignoring ULDLRATE"
    fi

    # SHUTDOWNCOMMAND - check acpi power states with pm-is-supported
    # if SHUTDOWNCOMMAND is set
    # Thx to http://wiki.ubuntuusers.de/pm-utils
    PM_HIBERNATE=false
    if [ ! -z "$SHUTDOWNCOMMAND" ]; then
        _log "INFO: SHUTDOWNCOMMAND is set to '$SHUTDOWNCOMMAND'"
        # check POWER MANAGEMENT MODES
        _log "INFO: Your Kernel supports the following modes from pm-utils:"
        pm-is-supported --suspend         && _log "INFO: Kernel supports SUSPEND (SUSPEND to RAM)" && PM_SUSPEND=true
        pm-is-supported --hibernate       && _log "INFO: Kernel supports HIBERNATE (SUSPEND to DISK)" && PM_HIBERNATE=true
        pm-is-supported --suspend-hybrid  && _log "INFO: Kernel supports HYBRID-SUSPEND (to DISK & to RAM)" && PM_SUSPEND_HYBRID=true

        # check, if pm-suspend is supported
        if [ "$SHUTDOWNCOMMAND" = "pm-suspend" -a ! "$PM_SUSPEND" = "true" ]; then
            _log "WARNING: You set 'SHUTDOWNCOMMAND=\"pm-suspend\", but your PC doesn't support this!"
            _log "WARNING: Setting it to 'shutdown -h now'"
            SHUTDOWNCOMMAND="shutdown -h now"
        fi
        # check, if pm-hibernate is supported
        if [ "$SHUTDOWNCOMMAND" = "pm-hibernate" -a ! "$PM_HIBERNATE" = "true" ]; then
            _log "WARNING: You set 'SHUTDOWNCOMMAND=\"pm-hibernate\", but your PC doesn't support this!"
            _log "WARNING: Setting it to 'shutdown -h now'"
            SHUTDOWNCOMMAND="shutdown -h now"
        fi
        # check, if pm-suspend-hybrid is supported
        if [ "$SHUTDOWNCOMMAND" = "pm-suspend-hybrid" -a ! "$PM_SUSPEND_HYBRID" = "true" ]; then
            _log "WARNING: You set 'SHUTDOWNCOMMAND=\"pm-suspend-hybrid\", but your PC doesn't support this!"
            _log "WARNING: Setting it to 'shutdown -h now'"
            SHUTDOWNCOMMAND="shutdown -h now"
        fi
    fi

    # LOADAVERAGECHECK = "true"
    if [ ! -z "$LOADAVERAGECHECK" ]; then
        [[ "$LOADAVERAGECHECK" = "true" || "$LOADAVERAGECHECK" = "false" ]] || {
            _log "WARNING: LOADAVERAGECHECK not set properly. It has to be 'true' or 'false'."
            _log "WARNING: Set LOADAVERAGECHECK to false"
            LOADAVERAGECHECK="false"; }
    fi

    # LOADAVERAGE (max 3 digits)
    if [ "$LOADAVERAGECHECK" = "true" ]; then
        [[ "$LOADAVERAGE" =~ ^([1-9]|[1-9][0-9]{1,2})$ ]] || {
            _log "WARNING: Invalid parameter format: LOADAVERAGE"
            _log "WARNING: You set it to '$LOADAVERAGE', which is not a correct syntax. Maybe it's empty?"
            _log "WARNING: Set LOADAVERAGECHECK to 20 (0.20)"
            LOADAVERAGE=20; }
    else
        _log "WARNING: LOADAVERAGECHECK is set to false"
        _log "WARNING: Ignoring LOADAVERAGE"
    fi
}


###############################################################################
#
#   name          : _check_networkconfig
#   parameter     : none
#   return        : none
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
                        _log "INFO: _check_networkconfig(): Run: #${NW_WAIT}: No internet-Address found - wait 60 sec for initializing the network"
                        sleep 60
                    else
                        _log "INFO: _check_networkconfig(): Run: #${NW_WAIT}: IP-Address found"
                        break
                    fi
                else
                    _log "WARNING: No internet-Address for ${NIC[$NICNR]} found after 5 minutes - The script will not work maybe ..."
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
                _log "WARNING: Invalid parameter format: Class: nnn.nnn.nnn]"
                _log "WARNING: It is set to '${CLASS[$NICNR]}', which is not a correct syntax. Maybe parsing 'ifconfig ' did something wrong"
                _log "WARNING: Please report this Bug and the CLI-output of 'ifconfig'"
                _log "WARNING: unsetting NIC[$NICNR]: ${NIC[$NICNR]} ..."
                unset NIC[$NICNR]; }

            [[ "${SERVERIP[$NICNR]}" =~ ^(25[0-4]|2[0-4][0-9]|[0-1]{1}[0-9]{2}|[1-9]{1}[0-9]{1}|[1-9])$ ]] || {
                _log "WARNING: Invalid parameter format: SERVERIP [iii]"
                _log "WARNING: It is set to '${SERVERIP[$NICNR]}', which is not a correct syntax. Maybe parsing 'ifconfig' did something wrong"
                _log "WARNING: Please report this Bug and the CLI-output of 'ifconfig'"
                _log "WARNING: unsetting NIC[$NICNR]: ${NIC[$NICNR]} ..."
                unset NIC[$NICNR]; }

        else
            _log "INFO: NIC '${NIC[$NICNR]}' not found, skipping '${NIC[$NICNR]}'"
            if $DEBUG; then _log "DEBUG: before unset: NIC[$NICNR]: ${NIC[$NICNR]}"; fi
            unset NIC[$NICNR]
            if $DEBUG; then _log "DEBUG: after unset: NIC[$NICNR]: ${NIC[$NICNR]}"; fi
        fi
    done

    if [ $FOUNDIP = 0 ]; then
        _log "WARNING: No SERVERIP or CLASS found"
        _log "WARNING: exiting ..."
        exit 1
    fi
}


###############################################################################
#
#   name          : _check_system_active
#   parameter     : none
#   global return : none
#   return        : 0 : If no active host has been found
#                 : 1 : If at least one active host has been found, no shutdown
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

_log "INFO: XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX" force
_log "INFO: XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX" force
_log "INFO: XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX" force
_log "INFO: Openmediavault-autoshutdown version: $(\
    dpkg -s openmediavault-autoshutdown | awk '/Version:/{print $2}')" force
_log "INFO: Script md5sum: $(md5sum "${0}" | awk '{print $1}')" force
_log "INFO: Initialize logging to: ${FACILITY}" force

if [ -f /etc/autoshutdown.conf ]; then
    . /etc/autoshutdown.conf
    _log "INFO: /etc/autoshutdown.conf loaded"
else
    _log "WARNING: cfg-File not found! Please check Path /etc for autoshutdown.conf"
    exit 1
fi

# Set-up logging and modes.
[ "$FAKE" == "true" ] && VERBOSE="true"
[ "$VERBOSE" == "true" ] && DEBUG="true"

_check_config

# enable / disable check here
if [ "${ENABLE}" != "true" ]; then
    _log "INFO: script disabled by autoshutdown.conf"
    _log "INFO: nothing to do. Exiting here ..."
    exit 0
fi

_check_networkconfig

# If the tmp-dir doesn't exist, create it
if [ ! -d $TMPDIR ]; then
    mkdir $TMPDIR 2> /dev/null
    [[ $? = 0 ]] && _log "INFO: $TMPDIR created" || {
        _log "WARNING: Can't create $TMPDIR! Exiting ...!"
        exit 1
    }
fi

# If the pinglist or pinglistactive exists, delete it (at every start of the script)
if [ -f $TMPDIR/pinglist ]; then
    rm -f $TMPDIR/pinglist 2> /dev/null
    [[ $? = 0 ]] && _log "INFO: Pinglist deleted" || _log "WARNING: Can't delete Pinglist!"
fi

# Init the counter
FCNT=$CYCLES

# functional start of script
if $DEBUG ; then
    _log "DEBUG: XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
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

_log "INFO: ---------------- script started ----------------------"
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

if [ "$FAKE" = "true" ]; then
    _log "INFO: FAKE-Mode in on, dont't wait for first check"
else
    _log "INFO: Waiting 5 min until the first check"
    sleep 5m    # or: sleep 300
fi

for NICNR_START in $(seq 1 $NICNR); do
    # if NIC is set (not empty) then check IPs connections, else skip it
    if [ ! -z "${NIC[$NICNR_START]}" ]; then
        _log "INFO: script is doing checks for NIC: ${NIC[$NICNR_START]} - ${CLASS[$NICNR_START]}.${SERVERIP[$NICNR_START]}"
    fi
done

while : ; do
    _log "INFO: ------------------------------------------------------"
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
