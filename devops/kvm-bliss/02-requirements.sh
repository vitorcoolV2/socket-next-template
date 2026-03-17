#!/bin/bash
# Filename: 00-requirements.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source $(realpath ./00-kvm-bliss_lib.sh)

require_binaries "qemu-img" "virt-install" && echo "tools installed" || os_package_setup
is_valid_iso || bliss_image_download
etc_qemu__allow_virbr0  ### make sure
etc_libvirt_qemu
bliss_create_storage 