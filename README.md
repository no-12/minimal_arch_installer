# Minimal Arch Installer

self contained installer written in bash

boot the Arch Linux ISO and run the wizard with:
```bash
curl -s https://raw.githubusercontent.com/no-12/minimal_arch_installer/master/mai.sh | bash -s
```

the wizard will ask for the following parameters:
```bash
DISK
HOSTNAME
USERNAME
TIMEZONE
ADDITIONAL_PACKAGES
```

the paramaters can be set via environment variables prefixed with 'MAI_'. For example:
```bash
MAI_DISK=/dev/sda
curl -s https://raw.githubusercontent.com/no-12/minimal_arch_installer/master/mai.sh | bash -s
```

to skip the wizard set an environment variable MAI_SKIP_WIZARD=true

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
curl -s 10.0.2.2:8000/mai.sh | bash -s
```
