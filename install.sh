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

# Get list of disks (NAME only)
mapfile -t DISKS < <(lsblk -d -o NAME,SIZE,MODEL | tail -n +2)

# Print menu
for i in "${!DISKS[@]}"; do
    echo "$((i+1))) ${DISKS[i]}"
done

# Prompt user
while true; do
    read -rp "Select a disk by number: " DISK_NUM
    if [[ "$DISK_NUM" =~ ^[0-9]+$ ]] && (( DISK_NUM >= 1 && DISK_NUM <= ${#DISKS[@]} )); then
        DISK_NAME=$(echo "${DISKS[DISK_NUM-1]}" | awk '{print $1}')
        echo "You selected: $DISK_NAME"
        break
    else
        echo "Invalid selection. Please enter a number between 1 and ${#DISKS[@]}."
    fi
done

DISK="/dev/$DISK_NAME"

log "Partitioning time yayyyyyyyyyyyyyyyyyyyyyyyyyyyyyy!!!"

# 2. Show total disk and RAM for reference
DISK_SIZE=$(lsblk -dn -o SIZE "$DISK")
# Detect RAM
RAM_MIB=$(free -m | awk '/Mem:/ {print $2}')
echo "Swap size: ${RAM_MIB} MiB (matches RAM)"

# Partition math
EFI_START=1
EFI_END=2049
SWAP_START=$EFI_END
SWAP_END=$((SWAP_START + RAM_MIB))
ROOT_START=$SWAP_END

# Partitioning
parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart primary fat32 ${EFI_START}MiB ${EFI_END}MiB
parted -s "$DISK" set 1 boot on
parted -s "$DISK" mkpart primary linux-swap ${SWAP_START}MiB ${SWAP_END}MiB
parted -s "$DISK" mkpart primary ext4 ${ROOT_START}MiB 100%

# Detect NVMe vs SATA
if [[ "$DISK" == nvme* ]]; then
    BOOT_PART="${DISK}p1"
    SWAP_PART="${DISK}p2"
    ROOT_PART="${DISK}p3"
else
    BOOT_PART="${DISK}1"
    SWAP_PART="${DISK}2"
    ROOT_PART="${DISK}3"
fi

# Format
mkfs.fat -F32 "$BOOT_PART"
mkswap "$SWAP_PART"
swapon "$SWAP_PART"
mkfs.ext4 "$ROOT_PART"

log "Partitioning and formatting complete"
echo "Boot: $BOOT_PART, Swap: $SWAP_PART, Root: $ROOT_PART"



# 6. Mount Shit
log "now we mount ts shi"
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
# 1. Ask for root password first
read -rsp "Enter root password: " ROOT_PASS
echo
read -rsp "Confirm root password: " ROOT_PASS_CONFIRM
echo

if [[ "$ROOT_PASS" != "$ROOT_PASS_CONFIRM" ]]; then
  echo "Passwords do not match"
  exit 1
fi

# 2. Set root password
echo "root:$ROOT_PASS" | arch-chroot /mnt chpasswd

# 3. Create user "logan"
arch-chroot /mnt useradd -m -G wheel -s /bin/bash logan

# 4. Set logan’s password same as root
echo "logan:$ROOT_PASS" | arch-chroot /mnt chpasswd

# 5. Allow sudo for wheel group
arch-chroot /mnt sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers





while true; do
  read -rp "Gimme that hostname: " HOSTNAME
  if [[ "$HOSTNAME" =~ ^[a-zA-Z0-9-]+$ ]]; then
    break
  else
    echo "Invalid hostname. Only letters, numbers, and dash allowed."
  fi
done

echo "$HOSTNAME" > /mnt/etc/hostname

cat > /mnt/etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOF




log "Me when the AUR is chaotic :O"
arch-chroot /mnt pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
arch-chroot /mnt pacman-key --lsign-key 3056513887B78AEB
arch-chroot /mnt pacman -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' --noconfirm
arch-chroot /mnt pacman -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst' --noconfirm
cat >> /mnt/etc/pacman.conf <<EOF
[chaotic-aur]
Include = /etc/pacman.d/chaotic-mirrorlist
EOF
arch-chroot /mnt pacman -Syu
arch-chroot /mnt pacman -S yay


log "Bye Bye in T minus 3 seconds"
sleep 1
log "Bye Bye in T minus 2 seconds"
sleep 1
log "Bye Bye in T minus 1 second"
sleep 1
log "Byyyyyye Byyyyyyyyyyyyyuyyuyyyyyyyyyyyyyyyyuyyyyyyyyyyyyyeeeeeeeeeeeeeeeeeeee!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D:D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D :D"

reboot