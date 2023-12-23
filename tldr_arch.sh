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

echo "Checking secure boot status..."
setup_mode=$(bootctl status | grep -E "Secure Boot.*setup" | wc -l)
if [[ $setup_mode -ne 1 ]]; then
    echo "Secure boot setup mode is disabled, setup mode must be enabled before continuing with the installation."
    exit 1
fi

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

echo "Please choose a hostname: "
read -r HOSTNAME
while [[ -z "$HOSTNAME" || ! "$HOSTNAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]$ ]]; do
    echo "Invalid hostname detected, please try again: "
    read -r HOSTNAME
done

echo "Please choose your locale in xx_XX format, for example en_US: "
read -r LOCALE_INPUT
if [ -z "$LOCALE_INPUT" ]; then
    echo "No locale detected, please try again."
else
    MATCHED_LOCALE=$(locale -a | grep -E "^${LOCALE_INPUT}\b" | head -n 1)
    if [ -n "$MATCHED_LOCALE" ]; then
        LOCALE="$MATCHED_LOCALE"
    else
        echo "Invalid locale detected, please try again."
    fi
fi

echo "Please choose a name for your user account: "
read -r USERNAME
while [[ -z "$USERNAME" ]]; do
    echo "No user name detected, please try again: "
    read -r USERNAME
done

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

while true; do
    echo "Please choose an encryption password: "
    read -r -s CRYPT_PASS
    if [[ -z "$CRYPT_PASS" ]]; then
        echo
        echo "No encryption password was detected, please try again."
    else
        echo
        echo "Please confirm your encryption password: "
        read -r -s CRYPT_PASS2
        echo
        if [[ "$CRYPT_PASS" != "$CRYPT_PASS2" ]]; then
            echo "The passwords don't match, please try again."
        else
            break
        fi
    fi
done

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

echo "If you would like to include any additional packages in the installation please add them here, separated by spaces, or leave empty to skip: "
read -r OPT_PKGS_INPUT
if [[ -n "$OPT_PKGS_INPUT" ]]; then
    IFS=' ' read -r -a OPT_PKGS <<< "$OPT_PKGS_INPUT"
    INSTALL_OPT_PKGS=true
else
    INSTALL_OPT_PKGS=false
fi

echo "Would you like AMD GPU drivers to be included in the installation (y/n)? "
read -r INSTALL_AMD_GPU_PKGS
if [[ "${INSTALL_AMD_GPU_PKGS,,}" == "y" ]]; then
    AMD_GPU_PKGS="mesa xf86-video-amdgpu vulkan-radeon libva-mesa-driver mesa-vdpau"
fi

####################################################
# PARTITION CONFIGURATION
####################################################

echo "Configuring console keyboard layout..."
loadkeys "$KEY_MAP"

echo "Preparing disk..."
wipefs -af "$DISK"
sgdisk -Zo "$DISK"

echo "Creating partitions..."
parted -s "$DISK" \
    mklabel gpt \
    mkpart ESP fat32 1MiB 513MiB \
    set 1 esp on \
    mkpart CRYPTROOT 513MiB 100% \
EFI="/dev/disk/by-partlabel/EFI"
CRYPTROOT="/dev/disk/by-partlabel/CRYPTROOT"
partprobe "$DISK"

echo "Formatting EFI partition..."
mkfs.fat -F 32 "$EFI"

echo "Encrypting root partition..."
echo -n "$CRYPT_PASS" | cryptsetup luksFormat "$CRYPTROOT" -d -
echo -n "$CRYPT_PASS" | cryptsetup open "$CRYPTROOT" cryptroot -d - 
BTRFS="/dev/mapper/cryptroot"

echo "Formatting root partition..."
mkfs.btrfs "$BTRFS"
mount "$BTRFS" /mnt

echo "Creating BTRFS subvolumes..."
BTRFS_OPTS="ssd,noatime,compress=zstd:1,space_cache=v2,discard=async"
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home

echo "Mounting partitions..."
umount /mnt
mount -o "$BTRFS_OPTS",subvol=@ "$BTRFS" /mnt
mkdir -p /mnt/home
mount -o "$BTRFS_OPTS",subvol=@home "$BTRFS" /mnt/home
mkdir -p /mnt/efi
mount "$EFI" /mnt/efi


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

echo "Installing Arch..."
BASE_PKGS="base base-devel linux linux-firmware linux-headers man nano sudo git reflector btrfs-progs grub efibootmgr pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber"
pacstrap -K /mnt $BASE_PKGS $MICROCODE

####################################################
# SYSTEM CONFIGURATION
####################################################

echo "Configuring hostname..."
echo "$HOSTNAME" > /mnt/etc/hostname

echo "Generating filesystem table..."
genfstab -U /mnt >> /mnt/etc/fstab

echo "Configuring keyboard layout..."
echo "KEYMAP=$KEY_MAP" > /mnt/etc/vconsole.conf

echo "Configuring locale..."
arch-chroot /mnt sed -i "/^#$LOCALE/s/^#//" /mnt/etc/locale.gen
echo "LANG=$LOCALE" > /mnt/etc/locale.conf
arch-chroot /mnt locale-gen

echo "Configuring hosts file..."
arch-chroot /mnt bash -c 'cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   '"$HOSTNAME"'.localdomain   '"$HOSTNAME"'
EOF'

echo "Configuring network..."
pacstrap /mnt networkmanager
arch-chroot /mnt systemctl enable NetworkManager

echo "Configuring mkinitcpio..."
cat > /mnt/etc/mkinitcpio.conf <<EOF
HOOKS=(systemd autodetect keyboard sd-vconsole modconf block sd-encrypt filesystems)
EOF
arch-chroot /mnt mkinitcpio -P

echo "Adding encrypted root partition to filesystem table..."
UUID=$(blkid -s UUID -o value $CRYPTROOT)
sed -i "\,^GRUB_CMDLINE_LINUX=\"\",s,\",&rd.luks.name=$UUID=cryptroot root=$BTRFS," /mnt/etc/default/grub

echo "Configuring timezone..."
arch-chroot /mnt ln -sf /usr/share/zoneinfo/$(curl -s http://ip-api.com/line?fields=timezone) /etc/localtime

echo "Configuring clock..."
arch-chroot /mnt hwclock --systohc
arch-chroot /mnt timedatectl set-ntp true

echo "Configuring package management..."
arch-chroot /mnt sed -Ei 's/^#(Color)$/\1\nILoveCandy/;s/^#(ParallelDownloads).*/\1 = 10/' /etc/pacman.conf
arch-chroot /mnt systemctl enable reflector
arch-chroot /mnt systemctl enable reflector.timer

echo "Configuring systemd-oomd..."
arch-chroot /mnt systemctl enable systemd-oomd

####################################################
# DESKTOP ENVIRONMENT
####################################################

echo "Installing KDE Plasma..."
KDE_PKGS="xorg-server plasma-desktop plasma-wayland-session plasma-pa plasma-nm plasma-systemmonitor kscreen bluedevil powerdevil kdeplasma-addons discover dolphin konsole flatpak"
pacstrap /mnt $KDE_PKGS
echo "Configuring KDE Plasma..."
arch-chroot /mnt systemctl enable bluetooth

echo "Installing SDDM..."
DM_PKGS="sddm sddm-kcm"
pacstrap /mnt $DM_PKGS
echo "Configuring SDDM..."
arch-chroot /mnt systemctl enable sddm

####################################################
# AMD GPU Drivers
####################################################

echo "Installing GPU drivers..."
pacstrap /mnt $AMD_GPU_PKGS

####################################################
# ADDITIONAL PACKAGES
####################################################

if [[ "$INSTALL_OPT_PKGS" == true ]]; then
    echo "Installing optional packages..."
    pacstrap /mnt "${OPT_PKGS[@]}"
fi

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

####################################################
# USERS
####################################################

echo "Configuring user account..."
echo "%wheel ALL=(ALL:ALL) ALL" > /mnt/etc/sudoers.d/wheel
arch-chroot /mnt useradd -m -G wheel -s /bin/bash "$USERNAME"
echo "$USERNAME:$USER_PASS" | arch-chroot /mnt chpasswd

echo "Disabling root account..."
arch-chroot /mnt passwd -d root
arch-chroot /mnt passwd -l root

####################################################
# ZRAM
####################################################

echo "Configuring ZRAM..."
pacstrap /mnt zram-generator
arch-chroot /mnt bash -c 'cat > /etc/systemd/zram-generator.conf <<EOF
[zram0]
zram-size = min(ram, 8192)
EOF'

####################################################
# SECURE BOOT
####################################################

echo "Configuring boot loader..."
grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=GRUB --modules="tpm" --disable-shim-lock
grub-mkconfig -o /boot/grub/grub.cfg

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

####################################################
# FINISHED
####################################################

read -p "Installation is complete. Would you like to restart your computer? [Y/n] " -r RESTART
RESTART="${RESTART:-Y}"
RESTART="${RESTART,,}"
if [[ $RESTART == "y" ]]; then
    reboot
elif [[ $RESTART == "n" ]]; then
    :
fi
