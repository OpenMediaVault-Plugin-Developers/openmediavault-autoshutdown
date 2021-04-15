/**
 * @license   http://www.gnu.org/licenses/gpl.html GPL Version 3
 * @author    Volker Theile <volker.theile@openmediavault.org>
 * @author    OpenMediaVault Plugin Developers <plugins@omv-extras.org>
 * @copyright Copyright (c) 2009-2013 Volker Theile
 * @copyright Copyright (c) 2013-2021 OpenMediaVault Plugin Developers
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
// require("js/omv/WorkspaceManager.js")
// require("js/omv/workspace/form/Panel.js")

Ext.define("OMV.module.admin.service.autoshutdown.Settings", {
    extend: "OMV.workspace.form.Panel",

    rpcService: "AutoShutdown",
    rpcGetMethod: "getSettings",
    rpcSetMethod: "setSettings",

    plugins: [{
        ptype: "linkedfields",
        correlations: [{
            name: [
                "range"
            ],
            conditions: [
                { name: "ipcheck", value: true }
            ],
            properties: [
                "!readOnly",
                "!allowBlank"
            ]
        },{
            name: [
                "nsocketnumbers"
            ],
            conditions: [
                { name: "checksockets", value: true }
            ],
            properties: [
                "!readOnly",
                "!allowBlank"
            ]
        },{
            name: [
                "uldlrate"
            ],
            conditions: [
                { name: "uldlcheck", value: true }
            ],
            properties: [
                "!readOnly",
                "!allowBlank"
            ]
        },{
            name: [
                "loadaverage"
            ],
            conditions: [
                { name: "loadaveragecheck", value: true }
            ],
            properties: [
                "!readOnly",
                "!allowBlank"
            ]
        },{
            name: [
                "hddiorate"
            ],
            conditions: [
                { name: "hddiocheck", value: true }
            ],
            properties: [
                "!readOnly",
                "!allowBlank"
            ]
        },{
            name: [
                "loadprocnames"
            ],
            conditions: [
                { name: "checkprocnames", value: true }
            ],
            properties: [
                "!readOnly",
                "!allowBlank"
            ]
        },{
            name: [
                "tempprocnames"
            ],
            conditions: [
                { name: "checkprocnames", value: true }
            ],
            properties: [
                "!readOnly",
                "!allowBlank"
            ]
        },{
            name: [
                "wakealarm_uphours"
            ],
            conditions: [
                { name: "checkclockactive", value: true },
                { name: "wakealarm_set", value: true }
            ],
            properties: [
                "!readOnly"
            ]
        }]
    }],

    getFormItems: function() {
        var me = this;
        return [{
            xtype: "fieldset",
            title: _("General settings"),
            fieldDefaults: {
                labelSeparator: ""
            },
            items: [{
                xtype: "checkbox",
                name: "enable",
                fieldLabel: _("Enable"),
                checked: false
            },{
                xtype: "numberfield",
                name: "cycles",
                fieldLabel: _("Cycles"),
                minValue: 1,
                maxValue: 999,
                allowDecimals: false,
                allowBlank: false,
                value: 6,
                plugins: [{
                    ptype: "fieldinfo",
                    text: _("Set the number of cycles with no result (no PC online, etc) before shutdown.")
                }]
            },{
                xtype: "numberfield",
                name: "sleep",
                fieldLabel: _("Sleep"),
                minValue: 1,
                maxValue: 9999,
                allowDecimals: false,
                allowBlank: false,
                value: 180,
                plugins: [{
                    ptype: "fieldinfo",
                    text: _("Numbers of seconds between each cycle.")
                }]
            },{
                xtype: "combo",
                name: "shutdowncommand",
                fieldLabel: _("Shutdown Command"),
                mode: "local",
                store: new Ext.data.SimpleStore({
                    fields: [ "value", "text" ],
                    data: [
                        [ 0, _("Shutdown") ],
                        [ 1, _("Hibernate") ],
                        [ 2, _("Suspend") ],
                        [ 3, _("Hybrid Sleep") ],
                        [ 4, _("Suspend then Hibernate") ]
                    ]
                }),
                displayField: "text",
                valueField: "value",
                allowBlank: false,
                editable: false,
                triggerAction: "all",
                value: 0
            }]
        },{
            xtype: "fieldset",
            title: _("Forced Uptime"),
            fieldDefaults: {
                labelSeparator: ""
            },
            items: [{
                xtype: "checkbox",
                name: "checkclockactive",
                fieldLabel: _("Clock"),
                checked: false,
                boxLabel: _("Check Clock to identify forced uptime.")
            },{
                xtype: "fieldcontainer",
                fieldLabel: _("Uphours"),
                layout: "hbox",
                items: [{
                    xtype: "numberfield",
                    name: "uphours_begin",
                    fieldLabel: _("Begin:&emsp;Hour"),
                    minValue: 0,
                    maxValue: 23,
                    allowDecimals: false,
                    allowBlank: false,
                    value: 6
                },{
                    xtype: "numberfield",
                    name: "upmins_begin",
                    fieldLabel: _("&emsp;Minute"),
                    minValue: 0,
                    maxValue: 59,
                    allowDecimals: false,
                    allowBlank: false,
                    value: 0
                }]
            },{
                xtype: "fieldcontainer",
                fieldLabel: "&nbsp;",
                layout: "hbox",
                items: [{
                    xtype: "numberfield",
                    name: "uphours_end",
                    fieldLabel: _("End:&nbsp;&ensp;&emsp;Hour"),
                    minValue: 0,
                    maxValue: 23,
                    allowDecimals: false,
                    allowBlank: false,
                    value: 20
                },{
                    xtype: "numberfield",
                    name: "upmins_end",
                    fieldLabel: _("&emsp;Minute"),
                    minValue: 0,
                    maxValue: 59,
                    allowDecimals: false,
                    allowBlank: false,
                    value: 0
                }]
            }]
        },{
            xtype: "fieldset",
            title: _("WakeAlarm"),
            fieldDefaults: {
                labelSeparator: ""
            },
            items: [{
                xtype: "checkbox",
                name: "wakealarm_set",
                fieldLabel: _("WakeAlarm"),
                checked: false,
                boxLabel: _("Enable wake alarm on system.")
            },{
                xtype: "fieldcontainer",
                fieldLabel: _("WakeAlarm"),
                layout: "hbox",
                items: [{
                    xtype: "numberfield",
                    name: "wakealarm_hour",
                    fieldLabel: _("Time:&emsp;Hour"),
                    minValue: 0,
                    maxValue: 23,
                    allowDecimals: false,
                    allowBlank: false,
                    value: 8
                },{
                    xtype: "numberfield",
                    name: "wakealarm_mins",
                    fieldLabel: _("&emsp;Minute"),
                    minValue: 0,
                    maxValue: 59,
                    allowDecimals: false,
                    allowBlank: false,
                    value: 0
                }]
            },{
                xtype: "checkbox",
                name: "wakealarm_uphours",
                fieldLabel: _("WakeAlarm from Uphours"),
                checked: false,
                boxLabel: _("Set wake alarm using force uptime settings."),
                plugins: [{
                    ptype: "fieldinfo",
                    text: _("This only avalible if forced uptime is enabled.")
                }]
            }]
        },{
            xtype: "fieldset",
            title: _("Supervision Configuration"),
            fieldDefaults: {
                labelSeparator: ""
            },
            items: [{
                xtype: "fieldcontainer",
                fieldLabel: _("IP Range"),
                layout: "hbox",
                items: [{
                    xtype: "checkbox",
                    name: "ipcheck",
                    fieldLabel: "",
                    checked: true
                },{
                    xtype: "displayfield",
                    width: 25,
                    value: ""
                },{
                    xtype: "textfield",
                    name: "range",
                    fieldLabel: "",
                    value: "2..254,0x0..0xFFFF",
                    width: 800,
                    allowBlank: false,
                    plugins: [{
                        ptype: "fieldinfo",
                        text: _("Define a range of IPs which should be scanned.") + "<br />" +
                              _("The IP-Range should be a comma delimited list of the following:") + "<br />" + "- " +
                              _("Define an IPv4 range: &lt;START&gt;..&lt;END&gt; | iface@&lt;START&gt;..&lt;END&gt; | www.xxx.yyy.&lt;START&gt;..&lt;END&gt; | iface@xxx.yyy.zzz.&lt;START&gt;..&lt;END&gt;") + "<br />" + "- " +
                              _("Define a single IPv4: Last octet of IPv4 zzz | iface@zzz | www.xxx.yyy.zzz | iface@www.xxx.yyy.zzz") + "<br />" + "- " +
                              _("Define an IPv6 range: 0x&lt;START&gt;..0x&lt;END&gt; | iface@0x&lt;START&gt;..0x&lt;END&gt; | s:t:u:v:w:x:y:0x&lt;START&gt;..0x&lt;END&gt; | iface@s:t:u:v:w:x:y:0x&lt;START&gt;..0x&lt;END&gt;") + "<br />" + "- " +
                              _("Define a single IPv6: Last hextet of IPv6 0xzzzz | iface@0xzzzz  | s:t:u:v:w:x:y:z | iface@s:t:u:v:w:x:y:z") + "<br />" + "- " +
                              _("Define by FQDN: fqdn | iface@fqdn") + "<br />" +
                              _("If '&lt;START&gt;..&lt;END&gt;' or 'Last octet of IPv4' is set the first three octets of the iface IPv4 address is used.") + "<br />" +
                              _("If '0x&lt;START&gt;..0x&lt;END&gt;' or 'Last hextet of IPv6' is set the first seven hextets of the iface IPv6 address is used.") + "<br />" +
                              _("Please make sure to leave 1 and 255 out of the IPv4 range!")
                    }]
                }]
            },{
                xtype: "fieldcontainer",
                fieldLabel: _("Sockets"),
                layout: "hbox",
                items: [{
                    xtype: "checkbox",
                    name: "checksockets",
                    fieldLabel: "",
                    checked: true
                },{
                    xtype: "displayfield",
                    width: 25,
                    value: ""
                },{
                    xtype: "textfield",
                    name: "nsocketnumbers",
                    fieldLabel: "",
                    value: "21,22,80,3689,6991,9091,49152",
                    width: 800,
                    allowBlank: false,
                    plugins: [{
                        ptype: "fieldinfo",
                        text: _("Socket number to check for activity.") +
                                "  <a href='http://en.wikipedia.org/wiki/List_of_TCP_and_UDP_port_numbers' target='_blank'>" +
                              _("List of Ports") + "</a>"
                    }]
                }]
            },{
                xtype: "fieldcontainer",
                fieldLabel: _("ULDL Rate"),
                layout: "hbox",
                items: [{
                    xtype: "checkbox",
                    name: "uldlcheck",
                    fieldLabel: "",
                    checked: true
                },{
                    xtype: "displayfield",
                    width: 25,
                    value: ""
                },{
                    xtype: "numberfield",
                    name: "uldlrate",
                    fieldLabel: "",
                    minValue: 0,
                    maxValue: 9999,
                    allowDecimals: false,
                    allowBlank: false,
                    value: 50,
                    width: 800,
                    plugins: [{
                        ptype: "fieldinfo",
                        text: _("Define the network traffic in kB/s.")
                    }]
                }]
            },{
                xtype: "fieldcontainer",
                fieldLabel: _("Load Average"),
                layout: "hbox",
                items: [{
                    xtype: "checkbox",
                    name: "loadaveragecheck",
                    fieldLabel: "",
                    checked: false
                },{
                    xtype: "displayfield",
                    width: 25,
                    value: ""
                },{
                    xtype: "numberfield",
                    name: "loadaverage",
                    fieldLabel: "",
                    minValue: 0,
                    maxValue: 9999,
                    allowDecimals: false,
                    allowBlank: false,
                    value: 40,
                    width: 800,
                    plugins: [{
                        ptype: "fieldinfo",
                        text: _("If the load average of the server is above this value, then no shutdown.") + "<br />" +
                              _("Example: 50 means a loadaverage of 0.50, 8 means a loadaverage of 0.08, 220 means a loadaverage of 2.20")
                    }]
                }]
            },{
                xtype: "fieldcontainer",
                fieldLabel: _("HDDIO Rate"),
                layout: "hbox",
                items: [{
                    xtype: "checkbox",
                    name: "hddiocheck",
                    fieldLabel: "",
                    checked: true
                },{
                    xtype: "displayfield",
                    width: 25,
                    value: ""
                },{
                    xtype: "numberfield",
                    name: "hddiorate",
                    fieldLabel: "",
                    minValue: 0,
                    maxValue: 9999,
                    allowDecimals: false,
                    allowBlank: false,
                    value: 400,
                    width: 800,
                    plugins: [{
                        ptype: "fieldinfo",
                        text: _("If the HDD-IO-average of the server is above this value in kB/s, then no shutdown.")
                    }]
                }]
            },{
                xtype: "fieldcontainer",
                fieldLabel: _("Active Processes"),
                layout: "hbox",
                items: [{
                    xtype: "checkbox",
                    name: "checkprocnames",
                    fieldLabel: "",
                    checked: true
                },{
                    xtype: "displayfield",
                    width: 25,
                    value: ""
                },{
                    xtype: "textfield",
                    name: "loadprocnames",
                    fieldLabel: _("Load Processes"),
                    allowBlank: false,
                    value: "smbd,nfsd,mt-daapd,forked-daapd",
                    width: 800,
                    plugins: [{
                        ptype: "fieldinfo",
                        text: _("Names of processes with load dependent children. Set to '-' to disable.")
                    }]
                }]
            },{
                xtype: "fieldcontainer",
                fieldLabel: "&nbsp;",
                layout: "hbox",
                items: [{
                    xtype: "displayfield",
                    fieldLabel: "",
                    width: 43,
                    value: ""
                },{
                    xtype: "textfield",
                    name: "tempprocnames",
                    fieldLabel: _("Temp Processes"),
                    allowBlank: false,
                    value: "in.tftpd",
                    width: 800,
                    plugins: [{
                        ptype: "fieldinfo",
                        text: _("Names of processes only started when active. Set to '-' to disable.")
                    }]
                }]
            },{
                xtype: "checkbox",
                name: "checksamba",
                fieldLabel: _("SMB Status"),
                checked: true,
                boxLabel: _("Check SMB status for connected clients.")
            },{
                xtype: "checkbox",
                name: "checkcli",
                fieldLabel: _("Users"),
                checked: true,
                boxLabel: _("Check for connected users.")
            },{
                xtype: "checkbox",
                name: "smartcheck",
                fieldLabel: _("Smart Tests"),
                checked: true,
                boxLabel: _("Check if S.M.A.R.T. tests are running."),
                plugins: [{
                    ptype: "fieldinfo",
                    text: _("This only works if S.M.A.R.T. is supported directly.")
                }]
            },{
                xtype: "checkbox",
                name: "plugincheck",
                fieldLabel: _("Plugins"),
                checked: true,
                boxLabel: _("Check for users defined plugins."),
                plugins: [{
                    ptype: "fieldinfo",
                    text: _("Please check") + " <a href='https://github.com/OpenMediaVault-Plugin-Developers/openmediavault-autoshutdown/blob/master/etc/autoshutdown.default' target='_blank'>" +
                          _("autoshutdown.default") + "</a> " +
                          _("for more details.")
                }]
            }]
        },{
            xtype: "fieldset",
            title: _("Syslog Configuration"),
            fieldDefaults: {
                labelSeparator: ""
            },
            items: [{
                xtype: "checkbox",
                name: "syslog",
                fieldLabel: _("Log to Syslog"),
                checked: true,
                boxLabel: _("Write log informations to system logs.")
            },{
                xtype: "checkbox",
                name: "verbose",
                fieldLabel: _("Verbose"),
                checked: false,
                boxLabel: _("Verbose mode.")
            },{
                xtype: "checkbox",
                name: "fake",
                fieldLabel: _("Fake"),
                checked: false,
                boxLabel: _("Fake/Test mode.")
            }]
        },{
            xtype: "fieldset",
            title: _("Expert Settings"),
            fieldDefaults: {
                labelSeparator: ""
            },
            items: [{
                xtype: "textarea",
                name: "extraoptions",
                fieldLabel: _("Extra Options"),
                allowBlank: true,
                plugins: [{
                    ptype: "fieldinfo",
                    text: _("Please check") + " <a href='https://github.com/OpenMediaVault-Plugin-Developers/openmediavault-autoshutdown/blob/master/etc/autoshutdown.default' target='_blank'>" +
                          _("autoshutdown.default") + "</a> " +
                          _("for more details.")
                }]
            }]
        }];
    }
});

OMV.WorkspaceManager.registerPanel({
    id: "settings",
    path: "/service/autoshutdown",
    text: _("Settings"),
    position: 10,
    className: "OMV.module.admin.service.autoshutdown.Settings"
});
