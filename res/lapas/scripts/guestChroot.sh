#!/bin/bash
[ "$USER" != "root" ] && echo "ERROR: Must be root. Use 'su - root'." && exit 1
[ -z "$BASH_VERSION" ] && echo "ERROR: Must run with bash, not sh/dash." && exit 1

. "$(dirname "$0")/config" || { echo "ERROR: Failed to load config."; exit 1; }

mkdir "${LAPAS_GUESTROOT_DIR}" || { echo "ERROR: Could not create ${LAPAS_GUESTROOT_DIR}"; exit 1; }
mount "${LAPAS_GUESTIMG_PATH}" "${LAPAS_GUESTROOT_DIR}" || { echo "ERROR: Failed to mount guest image."; exit 1; }
mount --bind "${LAPAS_TFTP_DIR}/boot" "${LAPAS_GUESTROOT_DIR}/boot" || { echo "ERROR: Failed to bind-mount boot."; exit 1; }

pushd "${LAPAS_GUESTROOT_DIR}" >/dev/null || { echo "ERROR: pushd failed."; exit 1; }
echo "Entering chroot now.."
./bin/arch-chroot ./ || { echo "ERROR: arch-chroot failed."; popd >/dev/null; exit 1; }

echo "####################"
echo "Updating bootmenu..."
"${LAPAS_SCRIPTS_DIR}/updateBootmenus.sh" || { echo "ERROR: updateBootmenus.sh failed."; popd >/dev/null; exit 1; }

popd >/dev/null || { echo "ERROR: popd failed."; exit 1; }

umount "${LAPAS_GUESTROOT_DIR}/boot" || { echo "ERROR: Failed to unmount boot."; exit 1; }
umount "${LAPAS_GUESTROOT_DIR}" || { echo "ERROR: Failed to unmount guest root."; exit 1; }
rmdir "${LAPAS_GUESTROOT_DIR}" || { echo "ERROR: Failed to remove guest root dir."; exit 1; }
