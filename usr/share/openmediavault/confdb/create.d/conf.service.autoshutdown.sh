#!/bin/sh
#
# @license   http://www.gnu.org/licenses/gpl.html GPL Version 3
# @author    Volker Theile <volker.theile@openmediavault.org>
# @author    OpenMediaVault Plugin Developers <plugins@omv-extras.org>
# @copyright Copyright (c) 2009-2013 Volker Theile
# @copyright Copyright (c) 2013-2019 OpenMediaVault Plugin Developers
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.

set -e

. /usr/share/openmediavault/scripts/helper-functions

SERVICE_XPATH_NAME="autoshutdown"
SERVICE_XPATH="/config/services/${SERVICE_XPATH_NAME}"

if ! omv_config_exists "${SERVICE_XPATH}"; then
    omv_config_add_node "/config/services" "${SERVICE_XPATH_NAME}"
    omv_config_add_key "${SERVICE_XPATH}" "enable" "0"
    omv_config_add_key "${SERVICE_XPATH}" "cycles" "6"
    omv_config_add_key "${SERVICE_XPATH}" "sleep" "180"
    omv_config_add_key "${SERVICE_XPATH}" "range" "2..254"
    omv_config_add_key "${SERVICE_XPATH}" "shutdowncommand" "0"
    omv_config_add_key "${SERVICE_XPATH}" "checkclockactive" "0"
    omv_config_add_key "${SERVICE_XPATH}" "uphours_begin" "6"
    omv_config_add_key "${SERVICE_XPATH}" "uphours_end" "20"
    omv_config_add_key "${SERVICE_XPATH}" "nsocketnumbers" "21,22,80,139,445,3689,6991,9091,49152"
    omv_config_add_key "${SERVICE_XPATH}" "uldlcheck" "1"
    omv_config_add_key "${SERVICE_XPATH}" "uldlrate" "50"
    omv_config_add_key "${SERVICE_XPATH}" "loadaveragecheck" "0"
    omv_config_add_key "${SERVICE_XPATH}" "loadaverage" "40"
    omv_config_add_key "${SERVICE_XPATH}" "hddiocheck" "1"
    omv_config_add_key "${SERVICE_XPATH}" "hddiorate" "401"
    omv_config_add_key "${SERVICE_XPATH}" "checksamba" "1"
    omv_config_add_key "${SERVICE_XPATH}" "checkcli" "1"
    omv_config_add_key "${SERVICE_XPATH}" "syslog" "1"
    omv_config_add_key "${SERVICE_XPATH}" "verbose" "0"
    omv_config_add_key "${SERVICE_XPATH}" "fake" "0"
    omv_config_add_key "${SERVICE_XPATH}" "extraoptions" ""
fi

exit 0
