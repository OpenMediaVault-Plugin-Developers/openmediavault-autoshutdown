<?php
/**
 * This file is part of OpenMediaVault-autoshutdown.
 *
 * @license   http://www.gnu.org/licenses/gpl.html GPL Version 3
 * @author    Marcel Beck <marcel.beck@mbeck.org>
 * @copyright Copyright (c) 2012 Marcel Beck
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
require_once("openmediavault/object.inc");
require_once("openmediavault/config.inc");
require_once("openmediavault/error.inc");
require_once("openmediavault/util.inc");
require_once("openmediavault/rpcservice.inc");
require_once("openmediavault/notify.inc");

class OMVRpcServiceAutoShutdown extends OMVRpcServiceAbstract {
	/**
	 * Get the RPC service name.
	 */
	public function getName() {
		return "AutoShutdown";
	}

	/**
	 * Initialize the RPC service.
	 */
	public function initialize() {
		$this->registerMethod("getSettings");
		$this->registerMethod("setSettings");
	}

    /**
     * Get configuration object.
     */
    function getSettings($params, $context)
    {
		global $xmlConfig;

		// Validate the RPC caller context.
		$this->validateMethodContext($context, array(
			  "role" => OMV_ROLE_ADMINISTRATOR
		  ));

		// Get configuration object
        $xpath  = "//services/autoshutdown";
        $object = $xmlConfig->get($xpath);
        if (is_null($object)) {
            throw new OMVException(OMVErrorMsg::E_CONFIG_GET_OBJECT_FAILED, $xpath);
        }
		
        // Modify result data
		$object['enable'] = boolval($object['enable']);
        $object['flag'] = intval($object['flag']);
        $object['sleep'] = intval($object['sleep']);
        $object['checkclockactive'] = boolval($object['checkclockactive']);
		$object['uphours-begin'] = intval($object['uphours-begin']);
        $object['uphours-end'] = intval($object['uphours-end']);
        $object['syslog'] = boolval($object['syslog']);
        $object['verbose'] = boolval($object['verbose']);
        $object['fake'] = boolval($object['fake']);
		$object['nw_intensesearch'] = boolval($object['nw_intensesearch']);
		
        return $object;
    }

    /**
     * Set configuration object.
     */
    function setSettings($params, $context)
    {
        global $xmlConfig;

		// Validate the RPC caller context.
		$this->validateMethodContext($context, array(
			"role" => OMV_ROLE_ADMINISTRATOR
		));

		// Validate the parameters of the RPC service method.
		$this->validateMethodParams($params, '{
			"type":"object",
			"properties":{
				"enable":{"type":"boolean"},
				"flag":{"type":"integer","minimum":1,"maximum":50},
				"sleep":{"type":"integer","minimum":1,"maximum":3600},
				"checkclockactive":{"type":"boolean"},
				"uphours-begin":{"type":"integer","minimum":0,"maximum":23},
				"uphours-end":{"type":"integer","minimum":0,"maximum":23},
				"syslog":{"type":"boolean"},
				"verbose":{"type":"boolean"},
				"fake":{"type":"boolean"},
				"extraoptions":{"type":"string"},
				"range":{"type":"string"},
				"custom_ports":{"type":"string"},
				"nw_intensesearch":{"type":"boolean"}				
			}
		}');
		
		// Get the existing configuration object.
		$xpath = "//services/autoshutdown";
		$oldObject = $xmlConfig->get($xpath);
		if(is_null($oldObject)) {
			throw new OMVException(OMVErrorMsg::E_CONFIG_GET_OBJECT_FAILED,
			  $xpath);
		}		
		
        // Update the configuration.
        $object = array(
            "enable" => array_boolval($params, 'enable'),
            "flag" => intval($params['flag']),
            "sleep" => intval($params['sleep']),
            "checkclockactive" => array_boolval($params, 'checkclockactive'),
            "uphours-begin" => intval($params['uphours-begin']),
            "uphours-end" => intval($params['uphours-end']),
            "syslog" => array_boolval($params, 'syslog'),
            "verbose" => array_boolval($params, 'verbose'),
            "fake" => array_boolval($params, 'fake'),
            "extraoptions" => $params['extraoptions'],
            'range' => $params['range'],
            'custom_ports' => $params['custom_ports'],
            "nw_intensesearch" => array_boolval($params, 'nw_intensesearch')
        );

        // Set configuration object
		if(FALSE === $xmlConfig->replace("//services/autoshutdown", $object)) {
			throw new OMVException(OMVErrorMsg::E_CONFIG_SET_OBJECT_FAILED);
		}

		// Notify configuration changes.
		$dispatcher = &OMVNotifyDispatcher::getInstance();
		$dispatcher->notify(OMV_NOTIFY_MODIFY,
		  "org.openmediavault.services.autoshutdown", $object);
		
		// Return the configuration object.
		return $object;		
    }

}

// Register the RPC service.
$rpcServiceMgr = &OMVRpcServiceMgr::getInstance();
$rpcServiceMgr->registerService(new OMVRpcServiceAutoShutdown());
?>