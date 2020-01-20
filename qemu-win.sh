#Target memory size
# 16Gb if empty
targetmem="$1"
if [ "_$targetmem" = "_" ]; then
    targetmem=$(( 16 * 1024 ))
else
    targetmem=$(( $targetmem * 1024 ))
fi
echo $targetmem

#Unload nvidia drivers
sudo modprobe -r nvidia_modeset ||:
sudo modprobe -r nvidia_drm ||:
sudo modprobe -r nvidia_uvm ||:
sudo modprobe -r nvidia ||:
#Load vfio for ids
sudo modprobe vfio-pci ids=10de:1b80,10de:10f0 ||:

#Cleanup ram for dynamic hugepages
echo 1 | sudo tee /proc/sys/vm/drop_caches
echo 1 | sudo tee /proc/sys/vm/compact_memory

#Path to pulseaudio socket
PULSE_SERVER="/run/user/1000/pulse/native"
echo -n "Starting virtual machine..."

set +x

#Empty cmd
cmd=""

#Different priority settings
if [ "z$(uname -r | grep ck)" != "z" ]; then
    # -I available only for -ck kernel
    cmd="$cmd schedtool -I -n -1 -e"
else
    cmd="$cmd schedtool -n -5 -e"
fi

#use jemalloc
cmd="$cmd /usr/bin/jemalloc.sh "

cmd="$cmd /usr/bin/qemu-system-x86_64 "
cmd="$cmd -no-user-config"
cmd="$cmd -nodefaults"
cmd="$cmd -enable-kvm"

#set memory size
cmd="$cmd -m $targetmem"

#Cpu optimizations
#Some are set automatically, if kvm=on ... but - NVIDIA ERROR 43
cmd="$cmd -cpu max,check,l3-cache=on,"
cmd="${cmd}-hypervisor"

#NVIDIA ERROR 43 - workaround 1
cmd="${cmd},kvm=off"
#NVIDIA ERROR 43 - workaround 2
cmd="${cmd},hv_vendor_id=1234567890ab"
cmd="${cmd},+kvm_pv_unhalt"
cmd="${cmd},+kvm_pv_eoi"
cmd="${cmd},+invtsc"
cmd="${cmd},+topoext"
cmd="${cmd},kvmclock=on"
cmd="${cmd},kvm-nopiodelay=on"
cmd="${cmd},kvm-asyncpf=on"
cmd="${cmd},kvm-steal-time=on"
cmd="${cmd},kvmclock-stable-bit=on"
cmd="${cmd},x2apic=on"
cmd="${cmd},acpi=off"
cmd="${cmd},monitor=off"
cmd="${cmd},svm=off"
cmd="${cmd},hv_spinlocks=0x1fff"
cmd="${cmd},hv_vapic"
cmd="${cmd},hv_time"
cmd="${cmd},hv_reset"
cmd="${cmd},hv_vpindex"
cmd="${cmd},hv_runtime"
cmd="${cmd},hv_relaxed"
cmd="${cmd},hv_synic"
cmd="${cmd},hv_stimer"
cmd="${cmd},migratable=no"

#possibly another optimizaons
#kvm-shadow-mem could be unneeded
cmd="$cmd -machine mem-merge=off,type=q35,accel=kvm,kernel_irqchip=on,dump-guest-core=off,graphics=off,kvm-shadow-mem=256000000"
#machine name
#debug-threads REQUIRED for python cpu affinity script
cmd="$cmd -name winqemu,debug-threads=on"

#Hugepages
cmd="$cmd -mem-path /dev/hugepages"
cmd="$cmd -mem-prealloc"

#mem-lock is wantes
#cpu-pm is optional cause it looks like full cores usage. But only looks.
cmd="$cmd -overcommit mem-lock=on,cpu-pm=on"

#audio
cmd="$cmd -audiodev driver=pa,id=pa1,server=$PULSE_SERVER"
cmd="$cmd -device ich9-intel-hda,id=sound0,msi=on"
cmd="$cmd -device hda-micro,id=sound0-codec0,bus=sound0.0,cad=0"

#cpu configuration
cmd="$cmd -smp cores=8,threads=1,sockets=1"

cmd="$cmd -boot menu=on,strict=on"

#UEFI
cmd="$cmd -bios /usr/share/ovmf/x64/OVMF_CODE.fd"
cmd="$cmd -drive if=pflash,format=raw,readonly,file=/usr/share/ovmf/x64/OVMF_CODE.fd"
cmd="$cmd -drive if=pflash,format=raw,file=/home/laenco/bin/OVMF_VARS.fd"

#usb
cmd="$cmd -usb"
cmd="$cmd -device nec-usb-xhci,id=xhci"

#hardware 4port usb switch configuration
#we are forwarding only for one cable
switchhostbus=$(lsusb | gawk 'match($0, /^Bus 00([0-9]) .+1a40:0101/, a) { print a[1] }')
if [ "z$switchhostbus" == "z" ]; then echo "usb switch host bus not found, exiting"; exit 1; fi
cmd="$cmd -device usb-host,bus=xhci.0,hostbus=$switchhostbus,hostport=4.1"
cmd="$cmd -device usb-host,bus=xhci.0,hostbus=$switchhostbus,hostport=4.2"
cmd="$cmd -device usb-host,bus=xhci.0,hostbus=$switchhostbus,hostport=4.3"
cmd="$cmd -device usb-host,bus=xhci.0,hostbus=$switchhostbus,hostport=4.4"

#gamepad forwarding.
#Don't forget to blacklist or unload its linux kernel modules
xboxgamepad=$(lsusb | gawk 'match($0, /^Bus 00([0-9]) .+045e:02ea/, a) { print a[1] }')
if [ "z$xboxgamepad" != "z" ]; 
then
cmd="$cmd -device usb-host,bus=xhci.0,hostbus=$xboxgamepad,hostport=1"
fi

#forward urandom from host
cmd="$cmd -object rng-random,filename=/dev/urandom,id=rng0"
cmd="$cmd -device virtio-rng-pci,rng=rng0,disable-legacy=on,disable-modern=off"

#virtual disk
cmd="$cmd -object iothread,id=iothread0"
cmd="$cmd -device pcie-root-port,id=pcie.6,chassis=11"
cmd="$cmd -drive if=none,aio=threads,cache=unsafe,format=raw,id=drive0,index=0,file=/home/laenco/vmdisk/winprime.raw"
cmd="$cmd -device virtio-scsi-pci,ioeventfd=on,iothread=iothread0,id=scsi0,disable-modern=off,disable-legacy=on,bus=pcie.6"
cmd="$cmd -device scsi-hd,drive=drive0"

#cdrom with windows and drivers
cmd="$cmd -drive file=/home/laenco/Downloads/Win10_1909_Russian_x64.iso,index=1,media=cdrom"
cmd="$cmd -drive file=/home/laenco/Downloads/virtio-win-0.1.171.iso,index=2,media=cdrom"

#network - via bridge
cmd="$cmd -device pcie-root-port,id=pcie.2,chassis=10"
cmd="$cmd -device virtio-net-pci,ioeventfd=on,bus=pcie.2,disable-legacy=on,disable-modern=off,netdev=net0,mac=52:54:00:DF:54:02"
cmd="$cmd -netdev bridge,br=br0,id=net0"

#time
cmd="$cmd -rtc base=localtime,clock=rt,driftfix=none"

#gpu
cmd="$cmd -device pcie-root-port,id=pcie.7,chassis=7"
cmd="$cmd -device vfio-pci,bus=pcie.7,host=09:00.0,multifunction=on"
cmd="$cmd -device vfio-pci,bus=pcie.7,host=09:00.1"

#disable all other things
cmd="$cmd -serial null -parallel null"
cmd="$cmd -vga none"
cmd="$cmd -display none"

#daemonize, but start socket
cmd="$cmd -daemonize"
cmd="$cmd -monitor unix:/tmp/qemuwin.sock,server,nowait"
set -x

#run VM
sudo -P bash -c "$cmd"

#get its pid
sleep 2
pidproc=$(pidof qemu-system-x86_64)
if [ "z$pidproc" = "z" ]; then 
    exit 1
fi

#set cpu affinities
sudo python /home/laenco/bin/_qemu_affinity.py $pidproc -v -p 8-15,24-31 -i '*:8-15,24-31' -q 8-15,24-31 -w '*:8-15,24-31' -k 0 1 2 3 4 5 6 7

#attach to socket
sudo nc -U /tmp/qemuwin.sock
echo
echo "done"
