#!/bin/bash
# Copyright 2014 Google Inc. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

DOWNLOAD_URL="http://dl.sabayon.org/iso/monthly"

TAR_FILE_TEMPLATE="Sabayon_Linux_-v-_amd64_tarball.tar.gz"
LATEST_FILE="LATEST_IS"

SCRIPT_DIR="${PWD}"

TAR_DIR="${SCRIPT_DIR}/tarball"
ROOTFS_DIR="${SCRIPT_DIR}/rootfs"

DISK_DIR="${SCRIPT_DIR}/disk"
DISK_SIZE="10G"

IMAGE_DEST_DIR="${PWD}"

set -eu

executables=(chroot dd fdisk losetup md5sum mkfs.ext4 parted tar truncate wget whoami)
for executable in "${executables[@]}"; do
    type -f "${executable}" > /dev/null || {
        echo "${executable} not available" >&2
        exit 1;
    }
done

if [ "$(whoami)" != "root" ]; then
    echo "Run this as root..." >&2
    exit 1
fi

# Download image
ver=$(wget -q -O - "${DOWNLOAD_URL}/${LATEST_FILE}")
if [ -z "${ver}" ]; then
    echo "Unable to download the 'latest' file." >&2
    exit 1
fi

tar_file_name="${TAR_FILE_TEMPLATE/-v-/${ver}}"
tar_file_name_md5="${tar_file_name}.md5"

tar_file_path="${TAR_DIR}/${tar_file_name}"
tar_file_path_md5="${TAR_DIR}/${tar_file_name_md5}"

if [ -e "${tar_file_path_md5}" ]; then
    echo "Checking ${tar_file_path}..."
    pushd "${TAR_DIR}"
    md5sum -c "${tar_file_name_md5}" && popd || {
        popd
        rm -f "${tar_file_path}";
    }
fi
if [ ! -e "${tar_file_path}" ]; then
    echo "Downloading ${tar_file_name}..."
    mkdir -p "${TAR_DIR}"
    wget -c "${DOWNLOAD_URL}/${tar_file_name}" -O "${tar_file_path}"
    wget "${DOWNLOAD_URL}/${tar_file_name_md5}" -O "${tar_file_path_md5}"

    pushd "${TAR_DIR}"
    md5sum -c "${tar_file_name_md5}" && popd || {
        popd
        rm -f "${tar_file_path}";
    }
fi

cleanup_mounts() {
    local path= dev=
    for ((i=${#dir_mounts[@]}-1; i>=0; i--)); do
        path="${dir_mounts[$i]}"
        echo "Trying to umount dir ${path}"
        umount "${path}" 2>/dev/null || true
    done
    for ((i=${#mount_devices[@]}-1; i>=0; i--)); do
        dev="${mount_devices[$i]}"
        echo "Trying to umount ${dev}"
        umount "${dev}" 2>/dev/null || true
    done
    for ((i=${#loop_devices[@]}-1; i>=0; i--)); do
        dev="${loop_devices[$i]}"
        echo "Removing loop device for ${dev}"
        losetup -d "${dev}" 2>/dev/null || true
    done
}
dir_mounts=()
loop_devices=()
mount_devices=()
trap "cleanup_mounts" 1 2 3 6 9 14 15 EXIT

echo "Preparing disk.raw disk at ${DISK_DIR}..."
rm --one-file-system -rf "${DISK_DIR}"
mkdir -p "${DISK_DIR}"

disk_file="${DISK_DIR}/disk.raw"

echo "Creating ${disk_file}..."
truncate "${disk_file}" --size "${DISK_SIZE}"

echo "Partitioning ${disk_file}..."
parted "${disk_file}" mklabel msdos
parted "${disk_file}" mkpart primary ext4 1 "${DISK_SIZE}"
parted "${disk_file}" set 1 boot on

echo "Configuring disk ${disk_file}..."
start_sector=$(fdisk -l "${disk_file}" | grep "^${disk_file}1" | awk '{ print $3 }')
part_offset=$((start_sector * 512))
echo "Start sector found at: ${start_sector}, assuming 512b sectors, start offset: ${part_offset}"

part_sectors=$(fdisk -l "${disk_file}" | grep "^${disk_file}1" | awk '{ print $5 }')
part_size=$((part_sectors * 512))
echo "Partition size: ${part_size} bytes (assumed 512b block size)"

echo "Mounting loop device for ${disk_file}, partition 1..."
loop_device=$(losetup -f --offset="${part_offset}" --sizelimit="${part_size}" "${disk_file}" --show)
if [ -z "${loop_device}" ]; then
    echo "Unable to mount loop device for ${disk_file}." >&2
    exit 1
fi
loop_devices+=( "${loop_device}" )

echo "Formatting loop device ${loop_device}..."
mkfs.ext4 "${loop_device}" -L /  # label used in cmdline and fstab

echo "Preparing ${ROOTFS_DIR} rootfs..."
mkdir -p "${ROOTFS_DIR}"

echo "Mounting loop device into ${ROOTFS_DIR}..."
mount "${loop_device}" "${ROOTFS_DIR}"
mount_devices+=( "${loop_device}" )

echo "Unpacking ${tar_file_path}..."
tar -x -z -f "${tar_file_path}" -C "${ROOTFS_DIR}"

echo "Copying /etc/resolv.conf over..."
cat /etc/resolv.conf > "${ROOTFS_DIR}/etc/resolv.conf"

echo "Configuring rootfs ${ROOTFS_DIR}..."
cp "setup_rootfs.sh" "${ROOTFS_DIR}/"
chmod +x "${ROOTFS_DIR}/setup_rootfs.sh"

echo "Mounting /proc, /dev and /dev/pts inside rootfs..."
mount --bind /proc "${ROOTFS_DIR}/proc"
dir_mounts+=( "${ROOTFS_DIR}/proc" )

mount --bind /dev "${ROOTFS_DIR}/dev"
dir_mounts+=( "${ROOTFS_DIR}/dev" )

mount --bind /dev/pts "${ROOTFS_DIR}/dev/pts"
dir_mounts+=( "${ROOTFS_DIR}/dev/pts" )

echo "Running setup_rootfs.sh..."
chroot "${ROOTFS_DIR}" "/setup_rootfs.sh"

umount "${ROOTFS_DIR}/dev/pts"
umount "${ROOTFS_DIR}/dev"
umount "${ROOTFS_DIR}/proc"

rm -f "${ROOTFS_DIR}/setup_rootfs.sh"

echo "Installing bootloader into ${disk_file}..."
dd if="${ROOTFS_DIR}/usr/share/syslinux/mbr.bin" of="${disk_file}" bs=440 count=1 conv=notrunc

echo "Umounting devices..."
umount "${loop_device}"
losetup -d "${loop_device}"

echo "Compressing ${disk_file}..."
pushd "${DISK_DIR}"
tar -Szcf "${IMAGE_DEST_DIR}/sabayon.tar.gz" "disk.raw"
popd
sync

echo "Done"
