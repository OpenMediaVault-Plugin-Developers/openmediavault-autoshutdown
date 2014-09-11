<?php
/**
 * @license   http://www.gnu.org/licenses/gpl.html GPL Version 3
 * @author    Marcel Beck <marcel.beck@mbeck.org>
 * @copyright (c) 2012 Marcel Beck
 * @copyright (c) 2013-2014 OpenMediaVault Plugin Developers
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
require_once("openmediavault/object.inc");
require_once("openmediavault/config.inc");
require_once("openmediavault/error.inc");
require_once("openmediavault/util.inc");
require_once("openmediavault/rpcservice.inc");
require_once("openmediavault/notify.inc");

class OMVRpcServiceAutoShutdown extends OMVRpcServiceAbstract
{
    public function getName()
    {
        return "AutoShutdown";
    }

    private function getPluginName()
    {
        return strtolower( $this->getName() );
    }

    private function getXPath()
    {
        return sprintf( "//services/%s", $this->getPluginName() );
    }

    private function getEventMessagePath()
    {
        return sprintf( "org.openmediavault.services.%s", $this->getPluginName() );
    }

    /**
     * Initialize the RPC service.
     */
    public function initialize()
    {
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
        $this->validateMethodContext(
            $context,
            array( "role" => OMV_ROLE_ADMINISTRATOR )
        );

        // Get configuration object
        $object = $xmlConfig->get( $this->getXPath() );
        if (is_null($object))
        {
            throw new OMVException(
                OMVErrorMsg::E_CONFIG_GET_OBJECT_FAILED,
                $this->getXPath()
            );
        }

        // Modify result data
        $object['enable']           = boolval($object['enable']);
        $object['cycles']           = intval($object['cycles']);
        $object['sleep']            = intval($object['sleep']);
        $object['shutdowncommand']  = intval($object['shutdowncommand']);

        $object['checkclockactive'] = boolval($object['checkclockactive']);
        $object['uphours-begin']    = intval($object['uphours-begin']);
        $object['uphours-end']      = intval($object['uphours-end']);

        $object['uldlcheck']        = boolval($object['uldlcheck']);
        $object['uldlrate']         = intval($object['uldlrate']);
        $object['loadaveragecheck'] = boolval($object['loadaveragecheck']);
        $object['loadaverage']      = intval($object['loadaverage']);
        $object['hddiocheck']       = boolval($object['hddiocheck']);
        $object['hddiorate']        = intval($object['hddiorate']);

        $object['syslog']           = boolval($object['syslog']);
        $object['verbose']          = boolval($object['verbose']);
        $object['fake']             = boolval($object['fake']);

        return $object;
    }

    /**
     * Set configuration object.
     */
    function setSettings($params, $context)
    {
        global $xmlConfig;

        // Validate the RPC caller context.
        $this->validateMethodContext(
            $context,
            array( "role" => OMV_ROLE_ADMINISTRATOR )
        );

        // Validate the parameters of the RPC service method.
        $this->validateMethodParams($params, '{
            "type"       : "object",
            "properties" : {
                "enable"           : { "type" : "boolean" },
                "cycles"           : { "type" : "integer", "minimum" : 1, "maximum" : 999 },
                "sleep"            : { "type" : "integer", "minimum" : 1, "maximum" : 9999 },
                "range"            : { "type" : "string" },
                "shutdowncommand"  : { "type" : "integer", "minimum" : 0, "maximum" : 2 },
                "checkclockactive" : { "type" : "boolean" },
                "uphours-begin"    : { "type" : "integer", "minimum" : 0, "maximum" : 23 },
                "uphours-end"      : { "type" : "integer", "minimum" : 0, "maximum" : 23 },
                "nsocketnumbers"   : { "type" : "string" },
                "uldlcheck"        : { "type" : "boolean" },
                "uldlrate"         : { "type" : "integer" },
                "loadaveragecheck" : { "type" : "boolean" },
                "loadaverage"      : { "type" : "integer" },
                "hddiocheck"       : { "type" : "boolean" },
                "hddiorate"        : { "type" : "integer" },
                "syslog"           : { "type" : "boolean" },
                "verbose"          : { "type" : "boolean" },
                "fake"             : { "type" : "boolean" },
                "extraoptions"     : { "type" : "string" }
            }
        }');

        // Get the existing configuration object.
        $oldObject = $xmlConfig->get( $this->getXPath() );
        if (is_null($oldObject))
        {
            throw new OMVException(
                OMVErrorMsg::E_CONFIG_GET_OBJECT_FAILED,
                $this->getXPath()
            );
        }

        // Update the configuration.
        $object = array(
            "enable"           => array_boolval($params, 'enable'),
            "cycles"           => intval($params['cycles']),
            "sleep"            => intval($params['sleep']),
            "range"            => $params['range'],
            "shutdowncommand"  => intval($params['shutdowncommand']),
            "checkclockactive" => array_boolval($params, 'checkclockactive'),
            "uphours-begin"    => intval($params['uphours-begin']),
            "uphours-end"      => intval($params['uphours-end']),
            "nsocketnumbers"   => $params['nsocketnumbers'],
            "uldlcheck"        => array_boolval($params, 'uldlcheck'),
            "uldlrate"         => intval($params['uldlrate']),
            "loadaveragecheck" => array_boolval($params, 'loadaveragecheck'),
            "loadaverage"      => intval($params['loadaverage']),
            "hddiocheck"       => array_boolval($params, 'hddiocheck'),
            "hddiorate"        => intval($params['hddiorate']),
            "syslog"           => array_boolval($params, 'syslog'),
            "verbose"          => array_boolval($params, 'verbose'),
            "fake"             => array_boolval($params, 'fake'),
            "extraoptions"     => $params['extraoptions']
        );

        // Set configuration object
        if (FALSE === $xmlConfig->replace($this->getXPath(), $object))
        {
            throw new OMVException(
                OMVErrorMsg::E_CONFIG_SET_OBJECT_FAILED
            );
        }

        // Notify configuration changes.
        $dispatcher = &OMVNotifyDispatcher::getInstance();
        $dispatcher->notify(
            OMV_NOTIFY_MODIFY,
            $this->getEventMessagePath(),
            $object
        );

        // Return the configuration object.
        return $object;
    }
}

// Register the RPC service.
$rpcServiceMgr = &OMVRpcServiceMgr::getInstance();
$rpcServiceMgr->registerService(new OMVRpcServiceAutoShutdown());
