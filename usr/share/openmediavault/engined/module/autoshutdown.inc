<?php
/**
 * @license   http://www.gnu.org/licenses/gpl.html GPL Version 3
 * @author    Volker Theile <volker.theile@openmediavault.org>
 * @copyright (c) 2009-2013 Volker Theile
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
require_once("openmediavault/module.inc");
require_once("openmediavault/config.inc");
require_once("openmediavault/error.inc");
require_once("openmediavault/initscript.inc");
require_once("openmediavault/log.inc");

class OMVModuleAutoShutdown extends OMVModuleServiceAbstract
    implements OMVINotifyListener, OMVIModuleServiceStatus
{

    public function getName()
    {
        return "autoshutdown";
    }

    public function applyConfig()
    {
        $cmd = "omv-mkconf autoshutdown 2>&1";
        if (0 !== $this->exec($cmd, $output))
        {
            throw new OMVException(
                OMVErrorMsg::E_EXEC_FAILED,
                $cmd,
                implode("\n", $output)
            );
        }
    }

    public function startService()
    {
        $initd = new OMVSysVInitScript("autoshutdown", TRUE);
        $initd->exec();
    }

    public function getStatus()
    {
        global $xmlConfig;

        // Get the configuration object
        $xPath  = "//services/autoshutdown";
        $object = $xmlConfig->get($xPath);
        if (is_null($object))
        {
            throw new OMVException(
                OMVErrorMsg::E_CONFIG_GET_OBJECT_FAILED,
                $xPath
            );

        // Check if process is running. Init script does not support 'status'.
        $cmd = "ps --no-heading -C autoshutdown.sh";
        OMVUtil::exec($cmd, $output, $result);
        return array(
            "name"    => $this->getName(),
            "title"   => gettext("AutoShutdown"),
            "enabled" => boolval($object['enable']),
            "running" => !empty($output[0])
        );
    }

    /**
     * Bind listeners.
     */
    function bindListeners(OMVNotifyDispatcher $dispatcher)
    {
        $dispatcher->addListener(
            OMV_NOTIFY_MODIFY,
            "org.openmediavault.services.autoshutdown",
            array($this, "setDirty")
        );
    }
}

// Register module
$moduleMgr = &OMVModuleMgr::getInstance();
$moduleMgr->registerModule(new OMVModuleAutoShutdown());

// Register new logfile type
OMVLogFile::registerType(
    "autoshutdown",
    array(
        "filename" => "autoshutdown.log",
        "filepath" => "/var/log/autoshutdown.log",
        "regex"    => "/^(\S+\s+\d+\s+\S+)\s+.*\s+logger:\s+\S+:\s+(\S+):\s+(.*)$/",
        "columns"  => array(
            "date"  => array(
                "index" => 1,
                "func"  => create_function('$v', 'return strpdate($v,"M j G:i:s");')
             ),
            "type"  => 2,
            "log"   => 3
         )
    )
);
