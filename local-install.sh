#!/usr/bin/env bash 

#Installation script for debian autoshutdown from Github https://github.com/mnul/debian-autoshutdown
#created by Manuel Kimmerle (https://github.com/mnul)



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
sudo cp /etc/autoshutdown.default /etc/autoshutdown.conf

echo ""
echo ""
echo "all files copied to their location!"
echo ""


sudo systemctl daemon-reload
sudo systemctl start autoshutdown
sudo systemctl enable autoshutdown
sudo systemctl daemon-reload

echo "" && echo "" && echo ""
echo "" && echo "" && echo ""
echo "Autoshutdown is now active with its default configuration"
echo ""
echo "to finish and configure the service you must edit its configuration file (in this case using the nano editor:"
echo ""
echo "->    sudo nano /etc/autoshutdown.conf"
echo ""
echo "Finally restart autoshutdown to enable your changes"
echo ""
echo "->    sudo systemctl restart autoshutdown"
echo ""
echo ""
echo "all done. Goodbye."
