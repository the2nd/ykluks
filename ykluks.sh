#!/bin/sh

type getarg >/dev/null 2>&1 || . /lib/dracut-lib.sh

YKLUKS_CONF="/etc/ykluks.conf"
if [ -f "$YKLUKS_CONF" ] ; then
	. "$YKLUKS_CONF"
fi

LUKS_UUIDS="$(getarg rd.ykluks.uuid | cut -d '-' -f 2- | tr ',' '\n')"

display_msg () {
	local MSG="$1"
	(plymouth display-message --text="$MSG";sleep 1;plymouth hide-message --text="$MSG") &
}

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
			display_msg "$YUBIKEY_MSG"
			YUBIKEY_MSG=""
		fi
	done

	while true ; do
		YUBIKEY_PASS="$(/usr/bin/systemd-ask-password --no-tty "$YKLUKS_PROMPT")"
		LUKS_PASSPHRASE="$(ykchalresp -2 "$YUBIKEY_PASS")"
		YUBIKEY_MSG="Received response from yubikey."
		display_msg "$YUBIKEY_MSG"
		LUKS_OPEN_FAILURE="false"
		for UUID in $LUKS_UUIDS ; do
			DEV="$(blkid -U "$UUID")"
			if echo "$LUKS_PASSPHRASE" | cryptsetup luksOpen "$DEV" luks-$UUID ; then
				LUKS_MSG="Luks device opened successful: $DEV"
				display_msg "$LUKS_MSG"
			else
				LUKS_MSG="Failed to open luks device: $DEV (Wrong password?)"
				display_msg "$LUKS_MSG"
				LUKS_OPEN_FAILURE="true"
			fi
		done
		if ! $LUKS_OPEN_FAILURE ; then
			break
		fi
	done
}

if [ "$LUKS_UUIDS" != "" ] ; then
	handle_yubikey
fi

rm /etc/udev/rules.d/69-yubikey.rules
systemctl daemon-reload

# Make sure we hide devices from dom0 after yubikey/luks setup.
hide_devices
