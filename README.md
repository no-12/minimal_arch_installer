# Minimal Arch Installer

self contained installer written in bash

boot the Arch Linux ISO and run the wizard with:
```bash
curl -o mai.sh https://raw.githubusercontent.com/no-12/minimal_arch_installer/main/mai.sh && bash mai.sh
```

## Test Minimal Arch Installer in VirtualBox
### Dependencies
* Installed VirtualBox
* DownloadedArch Linux ISO
* A webserver to serve mai.sh (e.g. python HTTP server)

Run the following commands on your local machine
```bash
python -m http.server
./start_vm.sh path/to/archlinux.iso
```
Run the following command on the vm
```bash
curl -o mai.sh 10.0.2.2:8000/mai.sh && bash mai.sh
```
