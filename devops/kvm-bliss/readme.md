

# 0. define VM proper environment 


## 0.1 development .env interface

VM_HOST_MOUNT_LOCATION="~/vms/Documents"
BLISS_ISO_BROWSE_URL="https://sourceforge.net/projects/blissos-x86/files/Official/BlissOS14/OpenGApps/Generic/Bliss-v14.10.3-x86_64-OFFICIAL-opengapps-20241012.iso/download"
VM_ISO_PATH="/var/lib/libvirt/images/Bliss-v14.10.3-x86_64-OFFICIAL-opengapps-20241012.iso"
VM_ISO_PATH="~/vms/Bliss-v14.10.3-x86_64-OFFICIAL-opengapps-20241012.iso"
VM_NAME="bliss-os-dev"
VM_OS_VARIANT="android-x86-9.0"
VM_HD_SIZE="32G"
VM_BOOT_LABEL="BlissOS"

# options default:tested ok, scrcpy:tested nok, nvidia:not tested
VM_GRAPH_MODE="default"
VM_RAM_MB=4096mb  
VM_CPU_CORES=4


## 0.1 vm environment tools && validation
source ./00-bliss_env.sh



## 1. CD Install. first time.

## 1.1 vm boot from live cd
. ./01-bliss_lib.sh 
bliss_boot_cd


## ...if and when UI with live cd comes up, select "** instalations"
## must complete Android instalation to sda1 partition


## 1.2 vm hd:sda:vda boot sequence. this step should be applied once, just before first vm run.
. ./01-bliss_lib.sh
_vm_initialize 
_vm_clean_kernel_boot_vga_safe
_vm_bridge_efi_to_vda2

## 1.n last resource. nuke current vm disk. Can use this option before refresh android install
. ./01-bliss_lib.sh
_vm_nuke_disk

## 2. vm run VM_NAME
. ./01-bliss_lib.sh
blish_run_flow



## 99. context documentation


You will find prepared VM_DISK0_FILE

###### format VM_DISK0_FILE="$VM_HOST_MOUNT_LOCATION/$VM_NAME.qcow2"

sda1 partition type EFI       # bridge|redirect boot from /EFI/BOOT/grub.cfg
---
search --no-floppy --set=root -f /android-2024-10-12/kernel
configfile /boot/grub/android.cfg


sda2 partition type ext4      # boot from "/boot/grub/android.cfg"
---
menuentry 'BlissOS 9.0 (Standard VGA)' {
    search --no-floppy --set=root -f /android-2024-10-12/kernel
    # vga=788 is 800x600@16, very stable for VESA
    # xforcevesa is an alternative to EXTMOD=vesa
    # Update the linux line in your script to this:
    # Adicione este parâmetro na linha linux do seu android.cfg: DATA=/data ou DATA=/android-2024-10-12/data
    linux /android-2024-10-12/kernel root=/dev/ram0 rw SRC=/android-2024-10-12 DATA=/data nomodeset xforcevesa HWACCEL=0 androidboot.selinux=permissive video=1024x768 androidboot.gui=ext    
    initrd /android-2024-10-12/initrd.img
}


