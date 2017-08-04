#!/bin/sh

type getarg >/dev/null 2>&1 || . /lib/dracut-lib.sh

YKLUKS_CONF="/etc/ykluks.conf"
if [ -f "$YKLUKS_CONF" ] ; then
	. "$YKLUKS_CONF"
fi

#LUKS_UUID="$(cat /proc/cmdline | tr ' ' '\n' | grep rd.ykluks.uuid | cut -d '=' -f 2 | cut -d '-' -f 2-)"
LUKS_UUID="$(getarg rd.ykluks.uuid | cut -d '-' -f 2-)"

hide_devices () {
	# Find all networking devices currenly installed...
	HIDE_PCI="`lspci -mm -n | grep '^[^ ]* "02'|awk '{print $1}'`"

	# ... and optionally all USB controllers...
	if getargbool 0 rd.ykluks.hide_all_usb; then
	    HIDE_PCI="$HIDE_PCI `lspci -mm -n | grep '^[^ ]* "0c03'|awk '{print $1}'`"
	fi

	HIDE_PCI="$HIDE_PCI `getarg rd.ykluks.hide_pci | tr ',' ' '`"

	modprobe xen-pciback 2>/dev/null || :

	# ... and hide them so that Dom0 doesn't load drivers for them
	for dev in $HIDE_PCI; do
	    BDF=0000:$dev
	    if [ -e /sys/bus/pci/devices/$BDF/driver ]; then
		echo -n $BDF > /sys/bus/pci/devices/$BDF/driver/unbind
	    fi
	    echo -n $BDF > /sys/bus/pci/drivers/pciback/new_slot
	    echo -n $BDF > /sys/bus/pci/drivers/pciback/bind
	done
}

handle_yubikey () {
	LUKS_DEV="$(blkid -U "$LUKS_UUID")"
	WAIT_COUNTER="0"
	YUBIKEY_MSG="Please insert your yubikey..."
	while ! ykchalresp -2 test > /dev/null 2>&1 ; do
		if [ "$WAIT_COUNTER" -lt 3 ] ; then
			WAIT_COUNTER="$[$WAIT_COUNTER+1]"
			sleep 1
			continue
		fi
		if [ "$SHOW_YK_INSERT_MSG" != "true" ] ; then
			exit
		fi
		if [ "$YUBIKEY_MSG" == "" ] ; then
			sleep 1
		else
			plymouth display-message --text="$YUBIKEY_MSG"
			HIDE_MSG="$YUBIKEY_MSG"
			YUBIKEY_MSG=""
		fi
	done

	if [ "$HIDE_MSG" != "" ] ; then
		plymouth hide-message --text="$HIDE_MSG"
	fi

	while true ; do
		YUBIKEY_PASS="$(/usr/bin/systemd-ask-password --no-tty "$YKLUKS_PROMPT")"
		LUKS_PASSPHRASE="$(ykchalresp -2 "$YUBIKEY_PASS")"
		if echo "$LUKS_PASSPHRASE" | cryptsetup luksOpen "$LUKS_DEV" luks-$LUKS_UUID ; then
			break
		fi
	done

}

if [ "$LUKS_UUID" != "" ] ; then
	handle_yubikey
fi

# Make sure we hide devices from dom0 after yubikey/luks setup.
hide_devices
