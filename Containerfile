FROM docker.io/cachyos/cachyos-v3:latest AS output

ENV DRACUT_NO_XATTR=1

RUN \
# Move /var to /usr/lib/sysimage
grep "= */var" /etc/pacman.conf | sed "/= *\/var/s/.*=// ; s/ //" | xargs -n1 sh -c 'mkdir -p "/usr/lib/sysimage/$(dirname $(echo $1 | sed "s@/var/@@"))" && mv -v "$1" "/usr/lib/sysimage/$(echo "$1" | sed "s@/var/@@")"' '' && \
sed -i -e "/= *\/var/ s/^#//" -e "s@= */var@= /usr/lib/sysimage@g" -e "/DownloadUser/d" /etc/pacman.conf && \
\
# Chaotic-AUR setup
curl https://raw.githubusercontent.com/CachyOS/CachyOS-PKGBUILDS/master/cachyos-mirrorlist/cachyos-mirrorlist -o /etc/pacman.d/cachyos-mirrorlist && \
pacman -Syy --needed --overwrite "*" --noconfirm cachyos-keyring cachyos-mirrorlist cachyos-v3-mirrorlist cachyos-v4-mirrorlist cachyos-hooks archlinux-keyring pacman-mirrorlist && \
pacman -Syy --noconfirm && \
\
# Install packages
pacman -S --noconfirm base dracut linux-firmware ostree systemd btrfs-progs e2fsprogs xfsprogs binutils dosfstools skopeo dbus dbus-glib glib2 shadow udev wget crun && \
pacman -S --noconfirm librsvg libglvnd qt6-multimedia-ffmpeg plymouth acpid ddcutil dmidecode mesa-utils ntfs-3g vulkan-tools wayland-utils playerctl curl cosign && \
pacman -S --noconfirm distrobox podman shim networkmanager firewalld flatpak gamescope scx-scheds scx-manager sudo bash bash-completion fastfetch unzip ptyxis && \
\
# Chaotic keys
pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com && \
pacman-key --init && pacman-key --lsign-key 3056513887B78AEB && \
pacman -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' --noconfirm && \
pacman -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst' --noconfirm && \
echo -e '[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist' >> /etc/pacman.conf && \
pacman -Sy --noconfirm chaotic-aur/bootc && \
\
# Flatpak preinstall directory
mkdir -p /usr/share/flatpak/preinstall.d/ && \
\
# Systemd flatpak-preinstall.service
cat <<'EOF' > /usr/lib/systemd/system/flatpak-preinstall.service
[Unit]
Description=Preinstall Flatpaks
After=network-online.target
Wants=network-online.target
ConditionPathExists=/usr/bin/flatpak
Documentation=man:flatpak-preinstall(1)

[Service]
Type=oneshot
ExecStart=/usr/bin/flatpak preinstall -y
RemainAfterExit=true
Restart=on-failure
RestartSec=30

StartLimitIntervalSec=600
StartLimitBurst=3

[Install]
WantedBy=multi-user.target
EOF
\
# ZRAM & systemd-resolved
echo -e '[zram0]\nzram-size = min(ram, 8192)' >> /usr/lib/systemd/zram-generator.conf && \
echo -e 'enable systemd-resolved.service' >> usr/lib/systemd/system-preset/91-resolved-default.preset && \
echo -e 'L /etc/resolv.conf - - - - ../run/systemd/resolve/stub-resolv.conf' >> /usr/lib/tmpfiles.d/resolved-default.conf && \
systemctl preset systemd-resolved.service && \
\
# Homebrew setup
curl -s https://api.github.com/repos/ublue-os/packages/releases/latest \
  | jq -r '.assets[] | select(.name | test("homebrew-x86_64.*\\.tar\\.zst")) | .browser_download_url' \
  | xargs -I {} wget -O /usr/share/homebrew.tar.zst {} && \
echo '[[ -d /home/linuxbrew/.linuxbrew && $- == *i* ]] && eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' > /etc/profile.d/brew.sh && \
cat <<'EOF' > /usr/lib/systemd/system/brew-setup.service
[Unit]
Description=Setup Homebrew from tarball
After=local-fs.target
ConditionPathExists=!/var/home/linuxbrew/.linuxbrew
ConditionPathExists=/usr/share/homebrew.tar.zst

[Service]
Type=oneshot
ExecStart=/usr/bin/mkdir -p /tmp/homebrew
ExecStart=/usr/bin/mkdir -p /var/home/linuxbrew
ExecStart=/usr/bin/tar --zstd -xf /usr/share/homebrew.tar.zst -C /tmp/homebrew
ExecStart=/usr/bin/cp -R -n /tmp/homebrew/linuxbrew/.linuxbrew /var/home/linuxbrew
ExecStart=/usr/bin/chown -R 1000:1000 /var/home/linuxbrew
ExecStart=/usr/bin/rm -rf /tmp/homebrew
ExecStart=/usr/bin/touch /etc/.linuxbrew

[Install]
WantedBy=multi-user.target
EOF
systemctl enable brew-setup.service && \
\
# os-group-fix function
mkdir -p /usr/lib/systemd/system-preset /usr/lib/systemd/system && \
cat <<'EOF' > /usr/libexec/os-group-fix
#!/bin/sh
cat /usr/lib/sysusers.d/*.conf | grep -e "^g" | grep -v -e "^#" | awk "NF" | awk '{print $2}' | grep -v -e "wheel" -e "root" -e "sudo" | xargs -I{} sed -i "/{}/d" $1
EOF
chmod +x /usr/libexec/os-group-fix && \
cat <<'EOF' > /usr/lib/systemd/system/os-group-fix.service
[Unit]
Description=Fix groups
Wants=local-fs.target
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/libexec/os-group-fix /etc/group
ExecStart=/usr/libexec/os-group-fix /etc/gshadow
ExecStart=systemd-sysusers

[Install]
WantedBy=default.target multi-user.target
EOF
echo -e "enable os-group-fix.service" > /usr/lib/systemd/system-preset/01-os-group-fix.preset && \
\
# fix sudo
echo -e '%wheel ALL=(ALL:ALL) ALL' && \
\
# Enable system services
systemctl enable polkit.service NetworkManager.service firewalld.service flatpak-preinstall.service os-group-fix.service && \
\
# Enable other services
systemctl enable sddm jupiter-fan-control podman bazzite-grub-boot-success.timer bazzite-grub-boot-success.service bazzite-autologin.service && \
\
# NTSync
echo -e 'ntsync' > /etc/modules-load.d/ntsync.conf && \
\
# CachyOS bbr3 config
echo -e 'net.core.default_qdisc=fq \nnet.ipv4.tcp_congestion_control=bbr' > /etc/sysctl.d/99-bbr3.conf && \
\
# Kernel / handheld packages
bash -c 'BASE="https://build.cachyos.org/ISO/handheld"; DATE=$(date +%y%m%d); while ! curl --head --silent --fail "$BASE/$DATE/" >/dev/null 2>&1; do DATE=$(date -d "$DATE - 1 day" +%y%m%d); done; pacman -Sy --noconfirm --overwrite "*" --ask=4 $(curl -s "$BASE/$DATE/cachyos-handheld-linux-$DATE.pkgs.txt" | awk "{print \$1}" | grep -v firefox | grep -v calamares )' && \
pacman -S --noconfirm --overwrite "*" --ask=4 steamos-manager steamos-powerbuttond jupiter-fan-control steamdeck-dsp cachyos-handheld mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon opencl-mesa lib32-opencl-mesa rocm-opencl-runtime && \
\
# bazzite scripts
pacman -S --noconfirm --needed rsync && \
cd /tmp && git clone --depth 1 https://github.com/ublue-os/bazzite.git && \
rsync -a /tmp/bazzite/system_files/deck/kinoite/ / && \
rsync -a /tmp/bazzite/system_files/deck/shared/ / && cd / && \
ln -s /usr/bin/grub-editenv /usr/bin/grub2-editenv && \
mkdir -p /usr/lib/systemd/system && \
cat <<'EOF' > /usr/lib/systemd/system/fix-grub-link.service
[Unit]
Description=Create /boot/grub symlink if missing
ConditionPathExists=!/boot/grub

[Service]
Type=oneshot
ExecStart=/bin/ln -s /boot/grub2 /boot/grub

[Install]
WantedBy=multi-user.target
EOF
systemctl enable /usr/lib/systemd/system/fix-grub-link.service && \
\
# Flatpak preinstall example
echo -e "[Flatpak Preinstall io.github.kolunmi.Bazaar]\nBranch=stable\nIsRuntime=false" > /usr/share/flatpak/preinstall.d/Bazaar.preinstall && \
\
# Plymouth logo
mkdir -p /etc/plymouth && \
echo -e '[Daemon]\nTheme=spinner' | tee /etc/plymouth/plymouthd.conf && \
wget --tries=5 -O /usr/share/plymouth/themes/spinner/watermark.png https://raw.githubusercontent.com/ChuckTripwell/cachyos-bootc-template/refs/heads/main/Text_Logo.png && \
\
# Dracut/initramfs
printf "systemdsystemconfdir=/etc/systemd/system\nsystemdsystemunitdir=/usr/lib/systemd/system\n" | tee /usr/lib/dracut/dracut.conf.d/30-bootcrew-fix-bootc-module.conf && \
printf 'hostonly=no\nadd_dracutmodules+=" ostree bootc "' | tee /usr/lib/dracut/dracut.conf.d/30-bootcrew-bootc-modules.conf && \
sh -c 'export KERNEL_VERSION="$(basename "$(find /usr/lib/modules -maxdepth 1 -type d | grep -v -E "*.img" | tail -n 1)")" && dracut --force --no-hostonly --reproducible --zstd --verbose --kver "$KERNEL_VERSION" "/usr/lib/modules/$KERNEL_VERSION/initramfs.img"' && \
\
# Cleanup
rm -rf /home/build/.cache/* /tmp/* /var/cache/pacman/pkg/* && \
sed -i 's|^HOME=.*|HOME=/var/home|' "/etc/default/useradd" && \
rm -rf /boot /home /root /usr/local /srv /var /usr/lib/sysimage/log /usr/lib/sysimage/cache/pacman/pkg && \
mkdir -p /sysroot /boot /usr/lib/ostree /var && \
ln -s sysroot/ostree /ostree && ln -s var/roothome /root && ln -s var/srv /srv && ln -s var/opt /opt && ln -s var/mnt /mnt && ln -s var/home /home && \
echo "$(for dir in opt home srv mnt usrlocal ; do echo "d /var/$dir 0755 root root -" ; done)" | tee -a "/usr/lib/tmpfiles.d/bootc-base-dirs.conf" && \
printf "d /var/roothome 0700 root root -\nd /run/media 0755 root root -" | tee -a "/usr/lib/tmpfiles.d/bootc-base-dirs.conf" && \
printf '[composefs]\nenabled = yes\n[sysroot]\nreadonly = true\n' | tee "/usr/lib/ostree/prepare-root.conf" && \
\
bootc container lint
