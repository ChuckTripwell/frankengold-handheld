##################################################################################
##################################################################################
####                        this is just a template                            ###
###   please go down to the "Changes go here" section to add your stuff!       ###
##################################################################################
###             a complete image will be published every week.                 ###
##################################################################################
##################################################################################

FROM docker.io/cachyos/cachyos-v3:latest AS builder

ENV DRACUT_NO_XATTR=1

# Move everything from `/var` to `/usr/lib/sysimage` so behavior around pacman remains the same on `bootc usroverlay`'d systems
RUN grep "= */var" /etc/pacman.conf | sed "/= *\/var/s/.*=// ; s/ //" | xargs -n1 sh -c 'mkdir -p "/usr/lib/sysimage/$(dirname $(echo $1 | sed "s@/var/@@"))" && \
mv -v "$1" "/usr/lib/sysimage/$(echo "$1" | sed "s@/var/@@")"' '' && \
    sed -i -e "/= *\/var/ s/^#//" -e "s@= */var@= /usr/lib/sysimage@g" -e "/DownloadUser/d" /etc/pacman.conf


RUN curl https://raw.githubusercontent.com/CachyOS/CachyOS-PKGBUILDS/master/cachyos-mirrorlist/cachyos-mirrorlist -o /etc/pacman.d/cachyos-mirrorlist
RUN pacman -Sy --needed --overwrite "*" --noconfirm cachyos-keyring cachyos-mirrorlist cachyos-v3-mirrorlist cachyos-v4-mirrorlist cachyos-hooks archlinux-keyring pacman-mirrorlist
RUN pacman -Syy --noconfirm

RUN pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
RUN pacman-key --init && pacman-key --lsign-key 3056513887B78AEB
RUN pacman -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' --noconfirm
RUN pacman -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst' --noconfirm
RUN echo -e '[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist' >> /etc/pacman.conf

RUN pacman -Syy --overwrite="*" --noconfirm --ask=4 base linux-cachyos-deckify linux-cachyos-deckify-headers jq dracut linux-firmware ostree systemd btrfs-progs e2fsprogs xfsprogs binutils \
    dosfstools skopeo dbus dbus-glib glib2 shadow udev wget crun librsvg libglvnd qt6-multimedia-ffmpeg rsync \
    plymouth acpid ddcutil dmidecode mesa-utils ntfs-3g vulkan-tools wayland-utils playerctl curl cosign distrobox \
    podman shim networkmanager firewalld gamescope scx-scheds scx-manager sudo bash bash-completion \
    fastfetch unzip steamos-manager steamos-powerbuttond \
    jupiter-fan-control steamdeck-dsp cachyos-handheld amd-ucode intel-ucode efibootmgr shim mesa lib32-mesa \
    libva-intel-driver libva-mesa-driver vpl-gpu-rt vulkan-icd-loader vulkan-intel vulkan-radeon apparmor \
    xf86-video-amdgpu lib32-vulkan-radeon polkit \
    opencl-mesa lib32-opencl-mesa rocm-opencl-runtime \
    plasma-desktop konsole plasma-nm plasma-pa sddm chaotic-aur/bootc chaotic-aur/flatpak-git


########################################################################################################################################
# end of changes
########################################################################################################################################

# finalize
RUN printf "systemdsystemconfdir=/etc/systemd/system\nsystemdsystemunitdir=/usr/lib/systemd/system\n" | tee /usr/lib/dracut/dracut.conf.d/30-bootcrew-fix-bootc-module.conf && \
      printf 'hostonly=no\nadd_dracutmodules+=" ostree bootc "' | tee /usr/lib/dracut/dracut.conf.d/30-bootcrew-bootc-modules.conf && \
      sh -c 'export KERNEL_VERSION="$(basename "$(find /usr/lib/modules -maxdepth 1 -type d | grep -v -E "*.img" | tail -n 1)")" && \
      dracut --force --no-hostonly --reproducible --zstd --verbose --kver "$KERNEL_VERSION"  "/usr/lib/modules/$KERNEL_VERSION/initramfs.img"'

RUN yes | pacman -Scc
RUN yes | pacman -Scc
RUN yes | paccache -ruk0

RUN rm -rf /home/build/.cache/* && \
    rm -rf \
        /tmp/* \
        /var/cache/pacman/pkg/* \
        /var/lib/pacman/sync/* \
        /var/log/* \
        /var/cache/* \
        /var/log/* \
        /var/db/* \
        /var/lib/*


# Necessary for general behavior expected by image-based systems
RUN sed -i 's|^HOME=.*|HOME=/var/home|' "/etc/default/useradd" && \
    rm -rf /boot /home /root /usr/local /srv /var /usr/lib/sysimage/log /usr/lib/sysimage/cache/pacman/pkg && \
    mkdir -p /sysroot /boot /usr/lib/ostree /var && \
    ln -s sysroot/ostree /ostree && ln -s var/roothome /root && ln -s var/srv /srv && ln -s var/opt /opt && ln -s var/mnt /mnt && ln -s var/home /home && \
    echo "$(for dir in opt home srv mnt usrlocal ; do echo "d /var/$dir 0755 root root -" ; done)" | tee -a "/usr/lib/tmpfiles.d/bootc-base-dirs.conf" && \
    printf "d /var/roothome 0700 root root -\nd /run/media 0755 root root -" | tee -a "/usr/lib/tmpfiles.d/bootc-base-dirs.conf" && \
    printf '[composefs]\nenabled = yes\n[sysroot]\nreadonly = true\n' | tee "/usr/lib/ostree/prepare-root.conf"

RUN bootc container lint
