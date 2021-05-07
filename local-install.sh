#!/usr/bin/env bash 

#Installation script for debian autoshutdown from Github https://github.com/mnul/debian-autoshutdown
#created by Manuel Kimmerle (https://github.com/mnul)

# variables
EXISTCONF=0


# script starts here

if [ $USER != 'root' ] #check if script is run as root, if not exit
  then
    echo "Install-script must be run as root. Rerun as root or use sudo."
    echo "Install will exit"
    exit
fi


sudo cp -R etc/* /etc/
sudo cp -R usr/* /usr/
sudo cp -R lib/* /lib/
sudo cp autoshutdown.service /etc/systemd/system/autoshutdown.service

# check if there is an existing autoshutdown.conf if so the skip copying.
if [ -f "/etc/autoshutdown.conf" ]
  then
    echo "" && echo "" && echo ""
    echo "configuration file exists, skipping creation of default configuration."
    EXISTCONF=1
  else  
    sudo cp /etc/autoshutdown.default /etc/autoshutdown.conf
    EXISTCONF=0
fi

echo ""
echo ""
echo "all files copied to their location!"
echo ""

# (re)start the service
sudo systemctl daemon-reload
sudo systemctl start autoshutdown
sudo systemctl enable autoshutdown
sudo systemctl daemon-reload

# Script copied. Let user know how to proceed

echo "***********************  DONE! ***********************************************"
echo "" && echo "" && echo ""
echo "" && echo "" && echo ""
if [ $EXISTCONF -eq 1 ]
  then
    echo "Autoshutdown is updated to the latest version."
    echo "" && echo ""
    echo "please compare your configured /etc/autoshutdown.conf and the default /etc/autoshutdown.default to see if configs have changed."
    echo ""
    echo "If so either update your current configuration to match the new default or start over by overwriting the current configuration with the new default"
  else
    echo "Autoshutdown is now active with its default configuration"
    echo ""
    echo "to finish and configure the service you must edit its configuration file (in this case using the nano editor:"
    echo ""
    echo "->    sudo nano /etc/autoshutdown.conf"
    echo ""
fi
echo "Finally restart autoshutdown to enable your changes"
echo ""
echo "->    sudo systemctl restart autoshutdown"
echo ""
echo ""
echo "all done. Goodbye."