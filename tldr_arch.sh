#!/usr/bin/bash

# System Configuration
BTRFS_MOUNT_OPTS="ssd,noatime,compress=zstd:1,space_cache=v2,discard=async"
HOSTNAME=desktop_0
KEY_MAP=en
LOCALE="en_AU.UTF-8"
TIMEZONE="Australia/Melbourne"

# Base Packages
BASE_PKGS="base base-devel linux linux-firmware man sudo nano git reflector btrfs-progs grub efibootmgr pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber"
UCODE_PKGS="amd-ucode"

# KDE Packages
KDE_PKGS="xorg-server plasma-desktop plasma-wayland-session plasma-pa plasma-nm plasma-systemmonitor kscreen bluedevil powerdevil kdeplasma-addons discover dolphin konsole flatpak sddm sddm-kcm"

# Hyprland Packages
HYPR_PKGS="hyprland"

# GPU Packages
GPU_PKGS="mesa xf86-video-amdgpu vulkan-radeon libva-mesa-driver mesa-vdpau"

###############################
# Logo
###############################

     ███        ▄█        ████████▄     ▄████████  
▀▜██████████   ███        ███   ▀███   ███    ███  
    ▀███▀▀██   ███        ███    ███   ███    ███  
     ███   ▀   ███        ███    ███  ▄███▄▄▄▄██▀  
     ███       ███        ███    ███ ▀▀███▀▀▀▀▀    
     ███       ███        ███    ███ ▀███████████  
     ███       ███▌     ▄ ███   ▄███   ███    ███  
    ▄████▀     █████▙▄▄██ ████████▀    ███    ███  
               ▀                       ███    ███  
                                                   
   ▄████████    ▄████████  ▄████████    ▄█    █▄   
  ███    ███   ███    ███ ███    ███   ███    ███  
  ███    ███   ███    ███ ███    █▀    ███    ███  
  ███    ███  ▄███▄▄▄▄██▀ ███         ▄███▄▄▄▄███▄▄
▀███████████ ▀▀███▀▀▀▀▀   ███        ▀▀███▀▀▀▀███▀ 
  ███    ███ ▀███████████ ███    █▄    ███    ███  
  ███    ███   ███    ███ ███    ███   ███    ███  
  ███    █▀    ███    ███ ████████▀    ███    █▀   
               ███    ███                          

###############################
# Preparing for Installation
###############################

echo "Configuring keyboard..."
loadkeys $KEY_MAP

echo "Verifying internet connectivity.."
ping -c 1 archlinux.org > /dev/null
if [[ $? -ne 0 ]]; then
    echo "No internet detected. Please check your internet connection."
    exit 1
fi

###############################
# Installation of Arch
###############################

echo "Installing Arch..."
pacstrap -K /mnt $BASE_PKGS $UCODE_PKGS

echo "Configuring timezone..."
arch-chroot /mnt ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime

echo "Configuring clock..."
arch-chroot /mnt hwclock --systohc
timedatectl set-ntp true

echo "Configuring locale..."
arch-chroot /mnt sed -i "s/^#$LOCALE UTF-8/$LOCALE UTF-8/" /etc/locale.gen
arch-chroot /mnt locale-gen
echo "LANG=$LOCALE" > /mnt/etc/locale.conf

echo "Configuring keyboard..."
echo "KEYMAP=us" > /mnt/etc/vconsole.conf

echo "Configuring filesystem table..."
genfstab -U /mnt >> /mnt/etc/fstab
sed -i 's/subvolid=[0-9]*,//g' /mnt/etc/fstab

echo "Configuring network..."
pacstrap /mnt networkmanager
echo "$HOSTNAME" > /mnt/etc/hostname
arch-chroot /mnt bash -c 'cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   '"$HOSTNAME"'.localdomain   '"$HOSTNAME"'
EOF'
arch-chroot /mnt systemctl enable NetworkManager

echo "Configuring package management..."
arch-chroot /mnt sed -Ei 's/^#(Color)$/\1\nILoveCandy/;s/^#(ParallelDownloads).*/\1 = 10/' /etc/pacman.conf
arch-chroot /mnt systemctl enable reflector
arch-chroot /mnt systemctl enable reflector.timer

echo "Configuring systemd-oomd..."
arch-chroot /mnt systemctl enable systemd-oomd

echo "Configuring ZRAM..."
pacstrap /mnt zram-generator
arch-chroot /mnt bash -c 'cat > /etc/systemd/zram-generator.conf <<EOF
[zram0]
zram-size = min(ram, 8192)
EOF'

###############################
# Installation of KDE
###############################

echo "Installing KDE..."
pacstrap /mnt $KDE_PKGS
echo "Configuring KDE..."
arch-chroot /mnt systemctl enable bluetooth
arch-chroot /mnt systemctl enable sddm

###############################
# Installation of Hyprland
###############################

echo "Installing Hyprland..."
pacstrap /mnt $HYPR_PKGS

###############################
# Installation of GPU Drivers
###############################

echo "Installing GPU drivers..."
pacstrap /mnt $GPU_PKGS

###############################
# Installing Timeshift
###############################

echo "Installing Timeshift..."
pacstrap /mnt grub-btrfs inotify-tools timeshift
echo "Configuring Timeshift..."
arch-chroot /mnt /bin/bash -c 'sed -i "s|^ExecStart=.*|ExecStart=/usr/bin/grub-btrfsd --syslog --timeshift-auto|" /etc/systemd/system/grub-btrfsd.service'
arch-chroot /mnt /bin/bash -c 'pacman -S --needed git base-devel && git clone https://aur.archlinux.org/yay.git && cd yay && makepkg -si'
arch-chroot /mnt /bin/bash -c 'yay -S timeshift-autosnap'
arch-chroot /mnt /bin/bash -c 'rm -rf /yay'
arch-chroot /mnt systemctl enable grub-btrfsd
arch-chroot /mnt systemctl enable cronie

###############################
# Configuring Users
###############################

sed -i '/^# %wheel ALL=(ALL:ALL) ALL/ s/# //' /mnt/etc/sudoers

read -p "Please choose a username: " USERNAME
arch-chroot /mnt useradd -m -G wheel "$USERNAME"
arch-chroot /mnt passwd "$USERNAME"

read -p "Do you want to disable the root account? [Y/n] " DISABLE_ROOT
DISABLE_ROOT="${DISABLE_ROOT:-n}"
DISABLE_ROOT="${DISABLE_ROOT,,}"
if [[ $DISABLE_ROOT == y ]] ; then
  echo "Disabling the root account..."
  arch-chroot /mnt passwd -d root
  arch-chroot /mnt passwd -l root
else
  echo "Please choose a password for root."
  arch-chroot /mnt passwd
fi

###############################
# Configuration of Secure Boot
###############################

grub-install --target=x86_64-efi --efi-directory=esp --bootloader-id=GRUB --modules="tpm" --disable-shim-lock
grub-mkconfig -o /boot/grub/grub.cfg
pacstrap /mnt sbctl
arch-chroot /mnt sbctl create-keys
arch-chroot /mnt sbctl enroll-keys -m
arch-chroot /mnt /bin/bash -c '
KEY_FILES=(/sys/firmware/efi/efivars/PK-* /sys/firmware/efi/efivars/db-* /sys/firmware/efi/efivars/KEK-*)
for KEY_FILE in "${KEY_FILES[@]}"; do
    if [[ $(lsattr "$KEY_FILE") == *i* ]]; then
        chattr -i "$KEY_FILE"
    fi
done
'
arch-chroot /mnt sbctl status
arch-chroot /mnt sbctl sign -s /efi/EFI/GRUB/grubx64.efi
arch-chroot /mnt sbctl sign -s /boot/vmlinuz-linux
arch-chroot /mnt sbctl verify

###############################
# Installation Complete
###############################

read -p "Installation is complete. Would you like to restart your computer? [Y/n] " -r RESTART
RESTART="${RESTART:-Y}"
RESTART="${RESTART,,}"
if [[ $RESTART == "y" ]]; then
    reboot
elif [[ $RESTART == "n" ]]; then
    :
fi
