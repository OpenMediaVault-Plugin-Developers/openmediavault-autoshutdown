/**
 * @license   http://www.gnu.org/licenses/gpl.html GPL Version 3
 * @author    Volker Theile <volker.theile@openmediavault.org>
 * @author    OpenMediaVault Plugin Developers <plugins@omv-extras.org>
 * @copyright Copyright (c) 2009-2013 Volker Theile
 * @copyright Copyright (c) 2013-2019 OpenMediaVault Plugin Developers
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */
// require("js/omv/module/admin/diagnostic/log/plugin/Plugin.js")

Ext.define("OMV.module.admin.diagnostic.log.plugin.AutoShutdown", {
    extend: "OMV.module.admin.diagnostic.log.plugin.Plugin",
    alias: "omv.plugin.diagnostic.log.autoshutdown",

    id: "autoshutdown",
    text: _("AutoShutdown"),
    stateful: true,
    stateId: "92a5f193-e76a-481e-a1c0-12db308c97c0",
    columns: [{
        text: _("Date & Time"),
        sortable: true,
        dataIndex: "date",
        stateId: "date",
        renderer: OMV.util.Format.localeTimeRenderer()
    },{
        text: _("Type"),
        sortable: true,
        dataIndex: "type",
        stateId: "type",
        flex: 1
    },{
        text: _("Log"),
        sortable: true,
        dataIndex: "log",
        stateId: "log",
        flex: 1
    }],
    rpcParams: {
        id: "autoshutdown"
    },
    rpcFields : [
        { name: "date", type: "string" },
        { name: "type", type: "string" },
        { name: "log", type: "string" }
    ]
});
