#!/bin/bash
set -e

BLUE='\e[0;34m'
GREEN='\e[0;32m'
NC='\e[0m' # No Color (reset)


log() {
  echo -e "\n[${BLUE}SuperCoolArchInstall${NC}]${GREEN} $1${NC}"
}
setfont ter-132b

# --- 1. Ask user for target disk ---
echo "Available disks:"
lsblk -d -o NAME,SIZE,MODEL
echo
read -rp "Enter the disk to format: " DISK

# --- Confirm ---
echo "WARNING: ALL DATA ON $DISK WILL BE LOST!"
read -rp "Are you sure? (yes/no): " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
    echo "Aborting."
    exit 1
fi
log "Partitioning time yayyyyyyyyyyyyyyyyyyyyyyyyyyyyyy!!!"

# 2. Show total disk and RAM for reference 
DISK_SIZE=$(lsblk -dn -o SIZE "$DISK")
RAM_SIZE=$(free -h | awk '/Mem:/ {print $2}')
echo "Disk size: $DISK_SIZE"
echo "RAM size: $RAM_SIZE"

# 3. Ask for swap size 
read -rp "Enter swap size (e.g., 4G): " SWAP_SIZE

# 4. Partitioning 
# We'll use parted in GPT mode
parted -s "$DISK" mklabel gpt

# EFI /boot partition 2GiB
parted -s "$DISK" mkpart primary fat32 1MiB 2049MiB
parted -s "$DISK" set 1 boot on

# Swap partition
parted -s "$DISK" mkpart primary linux-swap 2049MiB "$((2049 + ${SWAP_SIZE%G} * 1024))MiB"

# Root partition (rest of disk)
parted -s "$DISK" mkpart primary ext4 "$((2049 + ${SWAP_SIZE%G} * 1024))MiB" 100%

# 5. Format partitions 
BOOT_PART="${DISK}1"
SWAP_PART="${DISK}2"
ROOT_PART="${DISK}3"

mkfs.fat -F32 "$BOOT_PART"
mkswap "$SWAP_PART"
swapon "$SWAP_PART"
mkfs.ext4 "$ROOT_PART"

log "Partitioning and formatting complete"
echo "Boot: $BOOT_PART, Swap: $SWAP_PART, Root: $ROOT_PART"

# 6. Mount Shit
log "now we mount this shit"
mount $ROOT_PART /mnt
mount --mkdir $BOOT_PART /mnt/boot

# 7. Mirrors
log "Fetching Mirrorlist.......   hell yeah"
curl https://raw.githubusercontent.com/Logboy2000/MY-ARCHINSTALL/refs/heads/main/mirrorlist -o /etc/pacman.d/mirrorlist


cat /etc/pacman.d/mirrorlist

# 8. pacstrap
log "pacstrap is love. pacstrap is life."
pacstrap -K /mnt \
  base \
  linux \
  linux-firmware \
  linux-headers \
  amd-ucode \
  networkmanager \
  vim \
  nano \
  sudo \
  man-db \
  man-pages \
  texinfo \
  git \
  base-devel

# 9. arch-chroot
log "Look mum! i chrooted into my Arch ISO slash mnt directory!"

genfstab -U /mnt >> /mnt/etc/fstab

arch-chroot /mnt /bin/bash <<'EOF'
set -e

echo "Setting timezone"
ln -sf /usr/share/zoneinfo/America/Edmonton /etc/localtime
hwclock --systohc

echo "Configuring locale"
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen

cat > /etc/locale.conf <<LOCALE
LANG=en_US.UTF-8
LOCALE

echo "Configuring hostname"
read -rp "Gimme dat hostname: " HOSTNAME
echo "$HOSTNAME" > /etc/hostname

cat > /etc/hosts <<HOSTS
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
HOSTS

echo "Enabling NetworkManager"
systemctl enable NetworkManager

echo "Building initramfs"
echo "KEYMAP=us" > /etc/vconsole.conf
mkinitcpio -P

echo "Installing systemd-boot"
bootctl install

echo "Creating loader config"
cat > /boot/loader/loader.conf <<LOADER
default arch
timeout 3
editor no
LOADER

echo "Creating Arch boot entry"
ROOT_UUID=$(blkid -s UUID -o value $(findmnt -no SOURCE /))

cat > /boot/loader/entries/arch.conf <<ENTRY
title   Arch Linux
linux   /vmlinuz-linux
initrd  /amd-ucode.img
initrd  /initramfs-linux.img
options root=UUID=$ROOT_UUID rw
ENTRY

echo "systemd-boot installation complete"
EOF
log "root password pretty please"
arch-chroot /mnt passwd

log "Bye Bye in T minus 3 seconds"
sleep 1
log "Bye Bye in T minus 2 seconds"
sleep 1
log "Bye Bye in T minus 1 second"
sleep 1
log "Byyyyyye Byyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyve!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"

reboot