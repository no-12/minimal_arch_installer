#!/usr/bin/env bash
set -eu -o pipefail

declare -r vm_name=arch_mai_test
declare archlinux_iso="$1"

log() {
    echo -e "\e[32m===> ${1}\e[0m"
}

if VBoxManage showvminfo "$vm_name"; then
    log "Delete existing vm: $vm_name"
    VBoxManage unregistervm --delete "$vm_name"
fi

log "Create new vm: $vm_name"
vbox_settings_file=$(VBoxManage createvm --name "$vm_name" --ostype "ArchLinux_64" --register | grep "Settings file:" | sed "s/^.*:\s*// ; s/'//g")
log "vbox_settings_file: $vbox_settings_file"

vbox_disk_image_file="${vbox_settings_file/vbox/vdi}"
log "Creat new disk: $vbox_disk_image_file"
VBoxManage createmedium disk --filename "$vbox_disk_image_file" --size 120000

log "Configure vm"
VBoxManage modifyvm "$vm_name" --firmware efi
VBoxManage modifyvm "$vm_name" --audio none
VBoxManage modifyvm "$vm_name" --graphicscontroller vmsvga
VBoxManage modifyvm "$vm_name" --memory 1024 --vram 128
VBoxManage setextradata "$vm_name" VBoxInternal2/EfiGraphicsResolution 1440x900
VBoxManage storagectl "$vm_name" --name "SATA" --add sata --controller IntelAhci
VBoxManage storageattach "$vm_name" --storagectl "SATA" --port 0 --device 0 --type hdd --medium "$vbox_disk_image_file"
VBoxManage storageattach "$vm_name" --storagectl "SATA" --port 1 --device 0 --type dvddrive --medium "$archlinux_iso"

log "Start vm"
VBoxManage startvm "$vm_name" --type gui
