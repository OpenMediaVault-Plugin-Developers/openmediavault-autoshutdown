#!/bin/sh
#
# @license   http://www.gnu.org/licenses/gpl.html GPL Version 3
# @author    OpenMediaVault Plugin Developers <plugins@omv-extras.org>
# @copyright Copyright (c) 2020-2024 OpenMediaVault Plugin Developers
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

omv_config_add_key "${SERVICE_XPATH}" "upmins_begin" "0"
omv_config_add_key "${SERVICE_XPATH}" "upmins_end" "0"
omv_config_add_key "${SERVICE_XPATH}" "checkprocnames" "1"
omv_config_add_key "${SERVICE_XPATH}" "loadprocnames" "smbd,nfsd,mt-daapd,forked-daapd"
omv_config_add_key "${SERVICE_XPATH}" "tempprocnames" "in.tftpd"
omv_config_add_key "${SERVICE_XPATH}" "plugincheck" "0"

exit 0
