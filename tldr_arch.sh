#!/usr/bin/bash

####################################################
# LOGO
####################################################

echo "
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
                                                    
  █ BTRFS █ Encryption █ Secure Boot █ Timeshift █  
"

####################################################
# PREPARATION
####################################################

#echo "Checking secure boot status..."
#setup_mode=$(bootctl status | grep -E "Secure Boot.*setup" | wc -l)
#if [[ $setup_mode -ne 1 ]]; then
#    echo "Secure boot setup mode is disabled, setup mode must be enabled before continuing with the installation."
#    exit 1
#fi

echo "Verifying internet connectivity..."
ping -c 1 archlinux.org > /dev/null
if [[ $? -ne 0 ]]; then
    echo "No internet detected, internet must be connected before continuing with the installation."
    exit 1
fi

####################################################
# USER INPUT
####################################################

echo "Please choose a keyboard layout: "
read -r KEY_MAP
if [[ -z "$KEY_MAP" ]]; then
    echo "No keyboard layout detected, please try again."
elif ! localectl list-keymaps | grep -Fxq "$KEY_MAP"; then
    echo "Invalid keyboard layout detected, please try again."
else
    loadkeys "$KEY_MAP"
fi

echo "Press Enter to continue..."
read -r

echo "Please choose a hostname: "
read -r HOSTNAME
while [[ -z "$HOSTNAME" || ! "$HOSTNAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]$ ]]; do
    echo "Invalid hostname detected, please try again: "
    read -r HOSTNAME
done

echo "Press Enter to continue..."
read -r

echo "Please choose your locale, for example en_US.UTF-8: "
read -r LOCALE_INPUT
if [ -z "$LOCALE_INPUT" ]; then
    echo "No locale detected, please try again."
else
    if locale -a | grep -q "^$LOCALE_INPUT$"; then
        LOCALE="$LOCALE_INPUT"
    else
        echo "Invalid locale detected, please try again."
    fi
fi

echo "Press Enter to continue..."
read -r

echo "Please choose a name for your user account: "
read -r USERNAME
while [[ -z "$USERNAME" ]]; do
    echo "No user name detected, please try again: "
    read -r USERNAME
done

echo "Press Enter to continue..."
read -r

while true; do
    echo "Please choose a password for $USERNAME: "
    read -r -s USER_PASS
    if [[ -z "$USER_PASS" ]]; then
        echo
        echo "No password detected, please try again."
    else
        echo
        echo "Please confirm your user password: "
        read -r -s USER_PASS2
        echo
        if [[ "$USER_PASS" != "$USER_PASS2" ]]; then
            echo "The passwords don't match, please try again."
        else
            break
        fi
    fi
done

echo "Press Enter to continue..."
read -r

while true; do
    echo "Please choose a disk encryption passphrase: "
    read -r -s CRYPT_PASS
    if [[ -z "$CRYPT_PASS" ]]; then
        echo
        echo "No encryption passphrase was detected, please try again."
    else
        echo
        echo "Please confirm your passphrase password: "
        read -r -s CRYPT_PASS2
        echo
        if [[ "$CRYPT_PASS" != "$CRYPT_PASS2" ]]; then
            echo "The passphrases don't match, please try again."
        else
            break
        fi
    fi
done

echo "Press Enter to continue..."
read -r

while true; do
    echo "List of available disks:"
    DISK_LIST=($(lsblk -dpnoNAME | grep -P "/dev/sd|nvme|vd"))
    DISK_COUNT=${#DISK_LIST[@]}
    PS3="Please select which disk you would like to use for the installation (1-$DISK_COUNT): "
    select ENTRY in "${DISK_LIST[@]}";
    do
        DISK="$ENTRY"
        read -p "The installation will be completed using $DISK. All data on this disk will be erased, please type yes in capital letters to confirm your choice: " CONFIRM
        if [[ "$CONFIRM" == "YES" ]]; then
            break 2
        fi
    done
done

echo "Press Enter to continue..."
read -r

echo "If you would like to include any additional packages in the installation please add them here, separated by spaces, or leave empty to skip: "
read -r OPT_PKGS_INPUT
if [[ -n "$OPT_PKGS_INPUT" ]]; then
    IFS=' ' read -r -a OPT_PKGS <<< "$OPT_PKGS_INPUT"
    INSTALL_OPT_PKGS=true
else
    INSTALL_OPT_PKGS=false
fi

echo "Press Enter to continue..."
read -r

echo "Would you like AMD GPU drivers to be included in the installation (y/n)? "
read -r INSTALL_AMD_GPU_PKGS
if [[ "${INSTALL_AMD_GPU_PKGS,,}" == "y" ]]; then
    AMD_GPU_PKGS="mesa xf86-video-amdgpu vulkan-radeon libva-mesa-driver mesa-vdpau"
fi

echo "Press Enter to continue..."
read -r

####################################################
# PARTITION CONFIGURATION
####################################################

echo "Configuring console keyboard layout..."
loadkeys "$KEY_MAP"

echo "Press Enter to continue..."
read -r

echo "Preparing disk..."
wipefs -af "$DISK"
sgdisk -Zo "$DISK"

echo "Press Enter to continue..."
read -r

echo "Creating partitions..."
parted -s "$DISK" \
    mklabel gpt \
    mkpart ESP fat32 1MiB 513MiB \
    set 1 esp on \
    mkpart CRYPTROOT 513MiB 100% \
EFI="/dev/disk/by-partlabel/EFI"
CRYPTROOT="/dev/disk/by-partlabel/CRYPTROOT"
partprobe "$DISK"

echo "Press Enter to continue..."
read -r

echo "Formatting EFI partition..."
mkfs.fat -F 32 "$EFI"

echo "Press Enter to continue..."
read -r

echo "Encrypting root partition..."
echo -n "$CRYPT_PASS" | cryptsetup luksFormat "$CRYPTROOT" -d -
echo -n "$CRYPT_PASS" | cryptsetup open "$CRYPTROOT" cryptroot -d - 
BTRFS="/dev/mapper/cryptroot"

echo "Press Enter to continue..."
read -r

echo "Formatting root partition..."
mkfs.btrfs "$BTRFS"
mount "$BTRFS" /mnt

echo "Press Enter to continue..."
read -r

echo "Creating BTRFS subvolumes..."
BTRFS_OPTS="ssd,noatime,compress=zstd:1,space_cache=v2,discard=async"
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home

echo "Press Enter to continue..."
read -r

echo "Mounting partitions..."
umount /mnt
mount -o "$BTRFS_OPTS",subvol=@ "$BTRFS" /mnt
mkdir -p /mnt/home
mount -o "$BTRFS_OPTS",subvol=@home "$BTRFS" /mnt/home
mkdir -p /mnt/efi
mount "$EFI" /mnt/efi

echo "Press Enter to continue..."
read -r

####################################################
# SYSTEM INSTALLATION
####################################################

echo "Detecting CPU microcode.."
CPU=$(grep vendor_id /proc/cpuinfo)
if [[ "$CPU" == *"AuthenticAMD"* ]]; then
     MICROCODE="amd-ucode"
else
     MICROCODE="intel-ucode"
fi

echo "Press Enter to continue..."
read -r

echo "Installing Arch..."
BASE_PKGS="base base-devel linux linux-firmware linux-headers man nano sudo git reflector btrfs-progs grub efibootmgr pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber"
pacstrap -K /mnt $BASE_PKGS $MICROCODE

echo "Press Enter to continue..."
read -r

####################################################
# SYSTEM CONFIGURATION
####################################################

echo "Configuring hostname..."
echo "$HOSTNAME" > /mnt/etc/hostname

echo "Press Enter to continue..."
read -r

echo "Generating filesystem table..."
genfstab -U /mnt >> /mnt/etc/fstab

echo "Press Enter to continue..."
read -r

echo "Configuring keyboard layout..."
echo "KEYMAP=$KEY_MAP" > /mnt/etc/vconsole.conf

echo "Press Enter to continue..."
read -r

echo "Configuring locale..."
arch-chroot /mnt sed -i "/^#$LOCALE/s/^#//" /mnt/etc/locale.gen
echo "LANG=$LOCALE" > /mnt/etc/locale.conf
arch-chroot /mnt locale-gen

echo "Press Enter to continue..."
read -r

echo "Configuring hosts file..."
arch-chroot /mnt bash -c 'cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   '"$HOSTNAME"'.localdomain   '"$HOSTNAME"'
EOF'

echo "Press Enter to continue..."
read -r

echo "Configuring network..."
pacstrap /mnt networkmanager
arch-chroot /mnt systemctl enable NetworkManager

echo "Press Enter to continue..."
read -r

echo "Configuring mkinitcpio..."
cat > /mnt/etc/mkinitcpio.conf <<EOF
HOOKS=(systemd autodetect keyboard sd-vconsole modconf block sd-encrypt filesystems)
EOF
arch-chroot /mnt mkinitcpio -P

echo "Press Enter to continue..."
read -r

echo "Adding encrypted root partition to filesystem table..."
UUID=$(blkid -s UUID -o value $CRYPTROOT)
sed -i "\,^GRUB_CMDLINE_LINUX=\"\",s,\",&rd.luks.name=$UUID=cryptroot root=$BTRFS," /mnt/etc/default/grub

echo "Press Enter to continue..."
read -r

echo "Configuring timezone..."
arch-chroot /mnt ln -sf /usr/share/zoneinfo/$(curl -s http://ip-api.com/line?fields=timezone) /etc/localtime

echo "Press Enter to continue..."
read -r

echo "Configuring clock..."
arch-chroot /mnt hwclock --systohc
arch-chroot /mnt timedatectl set-ntp true

echo "Press Enter to continue..."
read -r

echo "Configuring package management..."
arch-chroot /mnt sed -Ei 's/^#(Color)$/\1\nILoveCandy/;s/^#(ParallelDownloads).*/\1 = 10/' /etc/pacman.conf
arch-chroot /mnt systemctl enable reflector
arch-chroot /mnt systemctl enable reflector.timer

echo "Press Enter to continue..."
read -r

echo "Configuring systemd-oomd..."
arch-chroot /mnt systemctl enable systemd-oomd

echo "Press Enter to continue..."
read -r

####################################################
# AMD GPU Drivers
####################################################

echo "Installing GPU drivers..."
pacstrap /mnt $AMD_GPU_PKGS

echo "Press Enter to continue..."
read -r

####################################################
# DESKTOP ENVIRONMENT
####################################################

echo "Installing KDE Plasma..."
KDE_PKGS="xorg-server plasma-desktop plasma-wayland-session plasma-pa plasma-nm plasma-systemmonitor kscreen bluedevil powerdevil kdeplasma-addons discover dolphin konsole flatpak"
pacstrap /mnt $KDE_PKGS
echo "Configuring KDE Plasma..."
arch-chroot /mnt systemctl enable bluetooth

echo "Press Enter to continue..."
read -r

echo "Installing SDDM..."
DM_PKGS="sddm sddm-kcm"
pacstrap /mnt $DM_PKGS
echo "Configuring SDDM..."
arch-chroot /mnt systemctl enable sddm

echo "Press Enter to continue..."
read -r

####################################################
# ADDITIONAL PACKAGES
####################################################

if [[ "$INSTALL_OPT_PKGS" == true ]]; then
    echo "Installing optional packages..."
    pacstrap /mnt "${OPT_PKGS[@]}"
fi

echo "Press Enter to continue..."
read -r

####################################################
# TIMESHIFT
####################################################

echo "Installing Timeshift..."
pacstrap /mnt grub-btrfs inotify-tools timeshift
echo "Configuring Timeshift..."
sed -i 's/subvolid=[0-9]*,//g' /mnt/etc/fstab
arch-chroot /mnt /bin/bash -c 'sed -i "s|^ExecStart=.*|ExecStart=/usr/bin/grub-btrfsd --syslog --timeshift-auto|" /etc/systemd/system/grub-btrfsd.service'
arch-chroot /mnt /bin/bash -c 'pacman -S --needed git base-devel && git clone https://aur.archlinux.org/yay.git && cd yay && makepkg -si'
arch-chroot /mnt /bin/bash -c 'yay -S timeshift-autosnap'
arch-chroot /mnt /bin/bash -c 'rm -rf /yay'
arch-chroot /mnt systemctl enable grub-btrfsd
arch-chroot /mnt systemctl enable cronie

echo "Press Enter to continue..."
read -r

####################################################
# USERS
####################################################

echo "Configuring user account..."
echo "%wheel ALL=(ALL:ALL) ALL" > /mnt/etc/sudoers.d/wheel
arch-chroot /mnt useradd -m -G wheel -s /bin/bash "$USERNAME"
echo "$USERNAME:$USER_PASS" | arch-chroot /mnt chpasswd

echo "Press Enter to continue..."
read -r

echo "Disabling root account..."
arch-chroot /mnt passwd -d root
arch-chroot /mnt passwd -l root

echo "Press Enter to continue..."
read -r

####################################################
# ZRAM
####################################################

echo "Configuring ZRAM..."
pacstrap /mnt zram-generator
arch-chroot /mnt bash -c 'cat > /etc/systemd/zram-generator.conf <<EOF
[zram0]
zram-size = min(ram, 8192)
EOF'

echo "Press Enter to continue..."
read -r

####################################################
# SECURE BOOT
####################################################

echo "Configuring boot loader..."
arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=GRUB --modules="tpm" --disable-shim-lock
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

echo "Press Enter to continue..."
read -r

echo "Configuring secure boot..."
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
arch-chroot /mnt sbctl sign -s /efi/EFI/GRUB/grubx64.efi
arch-chroot /mnt sbctl sign -s /boot/vmlinuz-linux

echo "Press Enter to continue..."
read -r

####################################################
# FINISHED
####################################################

echo "Unmounting partitions..."
umount -R /mnt

echo "Press Enter to continue..."
read -r

read -p "Installation is complete. Would you like to restart your computer? [Y/n] " -r RESTART
RESTART="${RESTART:-Y}"
RESTART="${RESTART,,}"
if [[ $RESTART == "y" ]]; then
    reboot
elif [[ $RESTART == "n" ]]; then
    :
fi
