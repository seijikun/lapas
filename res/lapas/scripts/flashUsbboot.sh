#!/bin/bash

# import LAPAS config
. $(dirname "$0")/config;

# https://superuser.com/questions/332252/how-to-create-and-format-a-partition-using-a-bash-script
# https://askubuntu.com/questions/873004/ubuntu-on-a-usb-stick-boot-in-both-bios-and-uefi-modes
# https://wiki.archlinux.org/title/Multiboot_USB_drive

if [ -z "$1" ]; then
	echo "Usage: $0 <targetDev>";
	exit 1;
fi
DEVICE="$1";

dd if=/dev/zero of="$DEVICE" bs=5M count=1 || exit $?;

echo "label: gpt
unit: sectors

size=1MiB,		type=21686148-6449-6E6F-744E-656564454649
size=50MiB,		type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B
				type=4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709, bootable
" | sfdisk "$DEVICE" || exit $?;

sgdisk --hybrid 1:2:3 "$DEVICE" || exit $?;


dd if=/dev/zero of="${DEVICE}2" bs=5M count=1 || exit $?;
dd if=/dev/zero of="${DEVICE}3" bs=5M count=1 || exit $?;
mkfs.fat -F32 "${DEVICE}2" || exit $?;
mkfs.ext4 "${DEVICE}3" || exit $?;

MNT_DIR=$(mktemp -d) || exit $?;
EFI_DIR="${MNT_DIR}/efi";
BOOT_DIR="${MNT_DIR}/boot";
mount "${DEVICE}3" "$MNT_DIR" || exit $?;
mkdir -p "${EFI_DIR}" || exit $?;
mkdir -p "${BOOT_DIR}" || exit $?;
mount "${DEVICE}2" "$EFI_DIR" || exit $?;

grub-install --target=x86_64-efi --recheck --removable --efi-directory="$EFI_DIR" --boot-directory="$BOOT_DIR" --no-uefi-secure-boot || exit $?;
grub-install --target=i386-pc --recheck --boot-directory="$BOOT_DIR" "$DEVICE" || exit $?;

# copy over configuration and theming
if [ -d "$LAPAS_TFTP_DIR/grub2/themes" ]; then
	cp -r "$LAPAS_TFTP_DIR/grub2/themes" "${BOOT_DIR}/grub/" || exit $?;
fi
cp "$LAPAS_TFTP_DIR/grub2/grub.cfg" "${BOOT_DIR}/grub/" || exit $?;
cp -a "$LAPAS_TFTP_DIR/boot/." "${BOOT_DIR}" || exit $?;
sync

umount "$EFI_DIR" || exit $?;
umount "$MNT_DIR" || exit $?;
rm -rf "$MNT_DIR";

echo "LAPAS usbboot flash succeeded."
echo "You may remove the device now."
