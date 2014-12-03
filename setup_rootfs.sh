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


# Enables the given systemd service.
# Signature: sd_enable <chroot> <service name, without .service>
sd_enable() {
    /usr/bin/systemctl --no-reload enable "${1}.service"
}


# Disables the given systemd service.
# Signature: sd_disable <chroot> <service name, without .service>
sd_disable() {
    /usr/bin/systemctl --no-reload disable "${1}.service"
}


set -eu

/usr/sbin/env-update
source /etc/profile

export ETP_NONINTERACTIVE=1
export LC_ALL=en_US.UTF-8

echo "Removing /install-data..."
rm -rf /install-data

echo "Updating repositories..."
FORCE_EAPI=2 equo update

for repo in $(equo repo list -q); do
    echo "Optimizing mirrors of ${repo}"
    equo repo mirrorsort "${repo}"
done

echo "Updating system..."
equo upgrade --purge
echo -5 | equo conf update

echo "Removing useless cruft..."
equo remove sys-fs/zfs

echo "Installing Compute Image Packages..."
equo install google-daemon gcimagebundle google-startup-scripts
sd_enable google-accounts-manager
sd_enable google-address-manager
sd_enable google-startup-scripts
sd_enable google

echo "Installing NetworkManager..."
equo install net-misc/networkmanager
sd_enable NetworkManager
sd_enable NetworkManager-wait-online

echo "Installing kernel and bootloader..."
equo install linux-sabayon syslinux

echo "Configuring kernel..."
eselect bzimage set 1

echo "Installing Google Cloud SDK..."
mkdir -p /usr/share/google
cloud_bashrc=/etc/bash/bashrc.d/00-google-cloud.sh
touch "${cloud_bashrc}"
chmod +x "${cloud_bashrc}"
pushd /usr/share/google
wget https://dl.google.com/dl/cloudsdk/release/google-cloud-sdk.tar.gz
tar -x -z -f google-cloud-sdk.tar.gz
rm google-cloud-sdk.tar.gz
./google-cloud-sdk/install.sh --usage-reporting=false \
    --rc-path="${cloud_bashrc}" --bash-completion=true \
    --disable-installation-options --path-update=true
popd


echo "Cleaning temporary data..."
rm -rf /var/lib/entropy/client/database/*/{sabayonlinux.org,sabayon-weekly,sabayon-limbo}
rm -rf /var/lib/entropy/client/packages
rm -rf /var/tmp/{entropy,portage}

echo "Configuring systemd..."
echo "ForwardToConsole=yes" >> /etc/systemd/journald.conf

echo "Configuring ntp..."
sd_enable systemd-timesyncd
echo "Servers=metadata.google.internal" >> /etc/systemd/timesyncd.conf

echo "Configuring services..."
sd_disable installer-gui
sd_disable installer-text
sd_disable sabayonlive
sd_disable x-setup
sd_disable alsa-store
sd_disable alsa-restore
sd_disable alsa-state

echo "Configuring sshd..."
sd_enable sshd
echo "GOOGLE" > /etc/ssh/sshd_not_to_be_run

echo "Configuring /etc/hosts..."
echo "169.254.169.254 metadata.google.internal metadata" >> /etc/hosts

echo "Configuring timezone..."
ln -sf /usr/share/zoneinfo/UTC /etc/localtime

echo "Cleaning lock files and system specific ids..."
rm -f /etc/entropy/.hw.hash
rm -f /run/entropy/entropy.lock
rm -rf /var/log/entropy /var/lib/entropy/logs

echo "Configuring users..."
passwd -d root  # disable root password, only ssh allowed

echo "Configuring fstab..."
echo "# GCE setup script.
LABEL=/   /          ext4     defaults         1 1
none      /dev/shm   tmpfs    defaults         0 0
devpts    /dev/pts   devpts   gid=5,mode=620   0 0
" > /etc/fstab

echo "Configuring bootloader..."
mkdir -p /boot/extlinux
ln -sf extlinux /boot/syslinux
cat > /boot/syslinux/syslinux.cfg <<EOF
PROMPT 1
TIMEOUT 20
DEFAULT sabayon

LABEL sabayon
  linux /boot/bzImage
  append root=LABEL=/ vga=normal nomodeset dovirtio panic=10
  initrd /boot/Initrd
EOF
ln -sf syslinux.cfg /boot/syslinux/extlinux.conf

echo "Installing bootloader..."
extlinux --install /boot/syslinux

echo "Caching linker stuff..."
ldconfig

echo "Final cleanups..."
rm --one-file-system -rf /run/* /var/lock/*

echo "Operations inside tarball chroot done."
