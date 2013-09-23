/**
 * This file is part of OpenMediaVault.
 *
 * @license   http://www.gnu.org/licenses/gpl.html GPL Version 3
 * @author    Aaron Murray <aaron@omv-extras.org>
 * @copyright Copyright (c) 2013 Aaron Murray
 *
 * OpenMediaVault is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * any later version.
 *
 * OpenMediaVault is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with OpenMediaVault. If not, see <http://www.gnu.org/licenses/>.
 */
// require("js/omv/WorkspaceManager.js")
// require("js/omv/workspace/form/Panel.js")

Ext.define("OMV.module.admin.service.autoshutdown.Settings", {
	extend: "OMV.workspace.form.Panel",

	rpcService: "AutoShutdown",
	rpcGetMethod: "getSettings",
	rpcSetMethod: "setSettings",

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
				name: "flag",
				fieldLabel: _("Cycles"),
				minValue: 1,
				maxValue: 50,
				allowDecimals: false,
				allowBlank: false,
				value: 6,
				plugins: [{
					ptype: "fieldinfo",
					text: _("Set the number of total failures before shutdown.")
				}]
			},{
				xtype: "numberfield",
				name: "sleep",
				fieldLabel: _("Sleep"),
				minValue: 1,
				maxValue: 3600,
				allowDecimals: false,
				allowBlank: false,
				value: 180,
				plugins: [{
					ptype: "fieldinfo",
					text: _("Numbers of seconds between each check/loop.")
				}]
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
				fieldLabel: _("Check Clock"),
				checked: false,
				plugins: [{
					ptype: "fieldinfo",
					text: _("Check Clock to identify forced uptime.")
				}]
			},{
				xtype: "numberfield",
				name: "uphours-begin",
				fieldLabel: _("Hours Begin"),
				minValue: 0,
				maxValue: 23,
				allowDecimals: false,
				allowBlank: false,					
				width: 50,
				value: 6
			},{
				xtype: "numberfield",
				name: "uphours-end",
				fieldLabel: _("Hours End"),
				minValue: 0,
				maxValue: 23,
				allowDecimals: false,
				allowBlank: false,					
				width: 50,
				value: 20
			}]
		},{
			xtype: "fieldset",
			title: _("Experts"),
			fieldDefaults: {
				labelSeparator: ""
			},
			items: [{
				xtype: "checkbox",
				name: "syslog",
				fieldLabel: _("Log to Syslog"),
				checked: false,
				plugins: [{
					ptype: "fieldinfo",
					text: _("Write log informations to system logs.")
				}]
			},{
				xtype: "checkbox",
				name: "verbose",
				fieldLabel: _("Verbose"),
				checked: false,
				plugins: [{
					ptype: "fieldinfo",
					text: _("Verbose mode."),
				}]
			},{
				xtype: "checkbox",
				name: "fake",
				fieldLabel: _("Fake"),
				checked: false,
				plugins: [{
					ptype: "fieldinfo",
					text: _("Fake/Test mode."),
				}]
			},{
				xtype: "textarea",
				name: "extraoptions",
				fieldLabel: _("Extra options"),
				allowBlank: true,
				plugins: [{
					ptype: "fieldinfo",
					text: _("Please check the <a href='https://github.com/OMV-Plugins/autoshutdown/blob/master/src/README' target='_blank'>README</a> for more details.")
				}]
			},{
				xtype: "textfield",
				name: "autoshutdown_version",
				fieldLabel: _("Autoshutdown Version"),
				allowNone: true,
				readOnly: true,
				hiddenName: "autoshutdown_version"
			}]
		},{
			xtype: "fieldset",
			title: _("Network settings"),
			fieldDefaults: {
				labelSeparator: ""
			},
			items: [{
				xtype: "checkbox",
				name: "nw_intensesearch",
				fieldLabel: _("Delayed Networks"),
				checked: false,
				plugins: [{
					ptype: "fieldinfo",
					text: _("Waits for networks which are started after autoshutdown starts (example: on HP Microserver N40L). If autoshutdown doesn't find an IP for your OMV-Server, this may help.")
				}]
			},{
				xtype: "textfield",
				name: "range",
				fieldLabel: _("IP-Range"),
				value: "2..254",
				plugins: [{
					ptype: "fieldinfo",
					text: _("Define a range of IPs which should be scanned, via XXX.XXX.XXX.xxx last triple of IP address in a list. <br />The following scheme is mandatory v..v+m,w,x..x+n,y+o..y,z <br />  - define an ip range : &lt;start&gt;..&lt;end&gt; -> the two dots are mandatory <br />  - define a single ip : &lt;ip&gt; <br />  - all list entries are seperated by comma ',' <br />Please make sure to leave 1 and 255 out of the list !")
				}]
			},{
				xtype: "textfield",
				name: "custom_ports",
				fieldLabel: _("Custom Ports"),
				value: "",
				plugins: [{
					ptype: "fieldinfo",
					text: _("Define custom ports.  <a href='http://en.wikipedia.org/wiki/List_of_TCP_and_UDP_port_numbers' target='_blank'>List of Ports</a>")
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
