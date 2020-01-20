# vfio-config

Hardware:
```
CPU: Ryzen 9 3950X
Motherboard: Asus ROG STRIX X470-F GAMING (BIOS/UEFI Version: 5406)
GPU1 (Guest): Palit GeForce GTX 1080 8GB @ Stock
GPU2 (Host): MSI RX 570 8GB @ Stock
RAM: 4 x 16GB (64GB) @ 3333 MHz
Guest OS: Windows 10 Pro
Kernel: 5.4.13-arch1-1-gc
```

Affinity script credits:

https://github.com/zegelin/qemu-affinity/


```
/etc/default/grub:

GRUB_CMDLINE_LINUX_DEFAULT="amd_iommu=on vfio-pci.ids=10de:1b80,10de:10f0 
pcie_aspm=off"
```

enable dynamic hugepages

```
/etc/sysctl.d/10-kvm.conf:

vm.nr_hugepages = 0
vm.nr_overcommit_hugepages = 17000  #34000 Mb max
```

tune hugepages

```
/etc/tmpfiles.d/20_hugepages.conf:

w /sys/kernel/mm/transparent_hugepage/enabled - - - - madvise
w /sys/kernel/mm/transparent_hugepage/defrag - - - - never
w /sys/kernel/mm/transparent_hugepage/shmem_enabled - - - - within_size
```

For preconfigured bridge
```
/etc/qemu/bridge.conf:
allow br0
```

X11:
```
/etc/X11/xorg.conf:

Section "Monitor"
Identifier     "HDMI-1"
EndSection
Section "Screen"
Identifier             "Screen1"
Device                 "amdrx570"
Monitor                "HDMI-1"
EndSection
Section "Device"
Identifier "amdrx570"
Driver "amdgpu"
Option "TearFree" "true"
BusID "PCI:8:0:0"
EndSection
Section "Device"
Identifier "nvidia1080"
#Driver "nvidia"
Driver "vfio"
BusID "PCI:9:0:0"
Option "AllowEmptyInitialConfiguration"
VendorName "NVIDIA Corporation"
BoardName "GeForce GTX 1080"
Option  "Coolbits" "13"
Option                "ConnectToAcpid"        "0"
Option                "NoLogo"                "1"
EndSection
Section "ServerLayout"
Identifier "Layout 1"
Screen "Screen1"
Option      "AutoAddGPU" "false"
EndSection
```

