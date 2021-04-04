#!/usr/bin/env bash 

#Installation script for debian autoshutdown from Github https://github.com/mnul/debian-autoshutdown
#created by Manuel Kimmerle (https://github.com/mnul), 2021
#



#Variables
giturl="https://github.com/mnul/debian-autoshutdown/archive/refs/heads/master.zip"
OLDPWD=$(pwd) #save current working dir
TMPDIR=/tmp/debian-autoshutdown
ZIPNAME="debian-autoshutdown.zip"

#Install-Script starts here



if [ $USER != 'root' ] #check if script is run as root, if not exit
  then
    echo "Install-script must be run as root. Rerun as root or use sudo."
    echo "Install will exit"
    exit
fi

if [[ -d $TMPDIR ]] #check if tempfolder exists, if so remove it
  then
    echo "Folder Autoshutdown exists. I'll delete it first."
    rm -rf $TMPDIR
  else
    echo "Creating temporary folder /tmp/debian/autoshutdown"
fi
sudo mkdir $TMPDIR
cd $TMPDIR

if [[ $(pwd) != $TMPDIR ]]
  then
    echo "Couldn't change into Temp-directory. Exiting"
    exit
fi


if [ -x "$(which wget)" ] ;
  then
    wget -O $ZIPNAME $giturl
elif [ -x "$(which curl)" ];
  then
    curl $giturl -L -o $ZIPNAME
else
  echo "Could not find wget or curl, please install it first."
  echo "Script exiting"
  exit
fi

if [ -x "$(which unzip)" ];
  then
    unzip -q $ZIPNAME
  else
    echo "Could not find program unzip. Install it first. Exiting"
    exit
fi

cd debian-autoshutdown-master

sudo cp -R etc/* /etc/
sudo cp -R srv/* /srv/
sudo cp -R lib/* /lib/

