#!/bin/bash

YKLUKS_CONF="/etc/ykluks.conf"
DRACUT_MOD_DIR="/usr/lib/dracut/modules.d/99ykluks/"

mkdir -p "$DRACUT_MOD_DIR"
cp module-setup.sh ykluks.sh "$DRACUT_MOD_DIR"
chown -R root: "$DRACUT_MOD_DIR"

if [ -e "$YKLUKS_CONF" ] ; then
	echo "Not overriding $YKLUKS_CONF..."
else
	cp ykluks.conf /etc/
fi
