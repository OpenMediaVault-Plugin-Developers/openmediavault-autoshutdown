#!/bin/bash
scriptdate="$(date '+%Y%m%d_%H%M%S')"

cp -R ./etc ./usr / && echo "files in /etc and /usr copied"

if [ -f /etc/autoshutdown.conf ]; then
	mv /etc/autoshutdown.conf /etc/autoshutdown.conf_bak_$scriptdate
	echo "/etc/autoshutdown.conf backed up to /etc/autoshutdown.conf_bak_$scriptdate"
fi
cp ./etc/autoshutdown.default /etc/autoshutdown.conf
echo "default /etc/autoshutdown.conf created"

update-rc.d  remove autoshutdown
update-rc.d autoshutdown defaults

exit 0


