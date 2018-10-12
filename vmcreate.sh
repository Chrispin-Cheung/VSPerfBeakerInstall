#!/bin/bash

#modified the beaker-tasks.repo to support more beaker tasks
rm -f /etc/yum.repos.d/beaker-tasks.repo
cat > /etc/yum.repos.d/beaker-tasks.repo << REPO
[beaker-tasks]
name=beaker-tasks
baseurl=http://beaker.engineering.redhat.com/rpms/
enabled=1
gpgcheck=0
skip_if_unavailable=1
REPO

# install the required package for use kvm
yum install -y virt-install libvirt
systemctl start libvirtd
yum install -y qemu-kvm

enforce_status=`getenforce`

setenforce permissive

SYS_ARCH=$(uname -m)
if hostname | grep "pek2.redhat.com" > /dev/null
then
	SERVER=download.eng.pek2.redhat.com
else
	SERVER=download-node-02.eng.bos.redhat.com
fi
ALT_FLAG=$(grep DISTRO /etc/motd | awk -F '=' '{print $2}' | awk -F '-' '{print $2}')
# we can only define the os-version in the same arch and kernel version.
OS_VERSION=${OS_VERSION:-"$(grep VERSION_ID /etc/os-release | awk -F '"' '{print $2}')"}
create_date=$(date +%Y%m%d)

CPUS=3
DEBUG="NO"
VIOMMU="NO"
DPDK_BUILD="NO"
SAVED="NO"
STOP="NO"
lflag="NO"
sflag="NO"
PEK="NO"
progname=$0

function usage () {
   cat <<EOF
Usage: $progname [-c cpus] [-d debug output to screen] [-l url to compose]
       [-s enable save the generated image] [-u enable use of upstream DPDK]
       [-p enable to designate the nfs_server to netqe-bj when enabled save]
       [-v enable viommu] [-S image_name] [-V OS_VERSION]

Example:  ./vmcreate.sh -c 3 -l http://example.redhat.com/compose -v -d
          ./vmcreate.sh -c 4 -V 7.6 -v -d
	  ./vmcreate.sh -c 4 -s  # create the host os_version image and save to nfs server
	  ./vmcreate.sh -c 4 -S RHEL7-VM # create the image and save as RHEL7-VM to nfs server
EOF
   exit 0
}

while getopts c:l:S:V:dhsuvp FLAG; do
   case $FLAG in

   c)  echo "Creating VM with $OPTARG cpus" 
       CPUS=$OPTARG
       ;;
   l)  echo "Using Location for VM install $OPTARG"
       DISTRO=$OPTARG
       lflag="YES"
       ;;
   s)  echo "To save the guest image is enabled"
       SAVED="YES";;
   v)  echo "VIOMMU is enabled"
       VIOMMU="YES";;
   u)  echo "Building upstream DPDK"
       DPDK_BUILD="YES";;
   d)  echo "debug enabled" 
       DEBUG="YES";;
   p)  echo "Designate the nfs_server is netqe-bj"
       PEK="YES";;
   S)  echo "About to save the guest with $OPTARG name"
       SAVED="YES"
       IMAGE_NAME=$OPTARG
       sflag="YES"
       ;;
   V)  echo "The OS Version for VM install $OPTARG"
       x=$(echo "$OPTARG $OS_VERSION" | awk '{if ($1 <= $2) print $1 ;else print 0}')
       case $x in
           0)   echo "The entered OS_VERSION is newer than the host's, can not Create this version guest"
                STOP="YES" ;;
           *)   OS_VERSION=$OPTARG ;;
       esac
       ;;
   h)  echo "found $opt" ; usage ;;
   \?)  usage ;;
   esac
done

if [ "$ALT_FLAG" = "ALT" ]; then
	release_branch=released/RHEL-ALT-7
	DIST_SPATH=/mnt/share/vms/RHEL/ALT
else
	release_branch=released/RHEL-7
	DIST_SPATH=/mnt/share/vms/RHEL
fi

if [ "$lflag" = "YES" ]; then
	OS_VERSION=" "
fi

# Setting the Loction of the compose
while [ "$lflag" != "YES" ]
do
	case $OS_VERSION in
		7.2)	DISTRO=${DISTRO:-"http://$SERVER/$release_branch/$OS_VERSION/Server/$SYS_ARCH/os"}
				;;
		7.3)    DISTRO=${DISTRO:-"http://$SERVER/$release_branch/$OS_VERSION/Server/$SYS_ARCH/os"}
				;;
		7.4)	DISTRO=${DISTRO:-"http://$SERVER/$release_branch/$OS_VERSION/Server/$SYS_ARCH/os"}
				;;
		7.5)	DISTRO=${DISTRO:-"http://$SERVER/$release_branch/$OS_VERSION/Server/$SYS_ARCH/os"}
				;;
		7.6)	if [ "$ALT_FLAG" = "ALT" ]; then
				release_branch=rel-eng/latest-RHEL-ALT
				DISTRO=${DISTRO:-"http://$SERVER/$release_branch-$OS_VERSION/compose/Server/$SYS_ARCH/os"}
			else
				release_branch=rel-eng/latest-RHEL
				DISTRO=${DISTRO:-"http://$SERVER/$release_branch-$OS_VERSION/compose/Server/$SYS_ARCH/os"}
			fi
				;;
		*)      echo "Not a valid OS Release Version" ;;
	esac
        lflag="YES"
done

# Setting the Saved IMAGE_NAME
while [ "$sflag" != "YES" ]
do
	if [ "$OS_VERSION" = " " ]; then
		IMAGE_NAME=RHEL-VM-$SYS_ARCH-$create_date
	else
		if [ "$ALT_FLAG" = "ALT" ]; then
			IMAGE_NAME=${IMAGE_NAME:-"RHEL-$ALT_FLAG-$OS_VERSION-$SYS_ARCH-$create_date"}
		else
			IMAGE_NAME=${IMAGE_NAME:-"RHEL-$OS_VERSION-$SYS_ARCH-$create_date"}
		fi
	fi
	sflag="YES"
done
## debug
#echo $CPUS
#echo $DISTRO
#echo $VIOMMU
#echo $DPDK_BUILD
#echo $DEBUG
#echo $OS_VERSION
#echo $IMAGE_NAME
#echo $SAVED
## Config for vm location url
#echo $ALT_FLAG
#echo $release_branch
#echo $SYS_ARCH

shift $(($OPTIND - 1))

# vm config
vm=master
bridge=virbr0
master_image=master.qcow2
image_path=/var/lib/libvirt/images
if [ "$OS_VERSION" = " " ]; then
	dist=rhel
else
	if [ "$ALT_FLAG" = "ALT" ]; then
		dist=rhel-alt-$OS_VERSION
	else
		dist=rhel-$OS_VERSION
	fi
fi
location=$DISTRO

# removed the  redundant kernel parameters which cause can not install guest with RHEL-ALT-7 on power systems
#extra="ks=file:/$dist-vm.ks console=ttyS0,115200"
extra="ks=file:/$dist-vm.ks"

master_exists=`virsh list --all | awk '{print $2}' | grep master`
if [ -z $master_exists ]; then
    master_exists='None'
fi

if [ $master_exists == "master" ]; then
    virsh destroy $vm
    virsh undefine --managed-save --snapshots-metadata --remove-all-storage --nvram $vm
fi

if [ -e $image_path/$master_image ]; then
	echo deleting master image
	/bin/rm -f $image_path/$master_image
fi

cat << KS_CFG > $dist-vm.ks

# System authorization information
auth --enableshadow --passalgo=sha512

# install a fresh system rather than upgrade an existing system "the default mode"
install

# Use network installation
url --url=$location

# Use text mode install
text

# Run the Setup Agent on first boot
firstboot --enable

# Causes the installer to ignore the specified disks. This is useful if
#you use autopartition and want to be sure that some disks are ignored.
ignoredisk --only-use=vda

# Keyboard layouts
keyboard us --vckeymap=us --xlayouts='us'

# System language
lang en_US.UTF-8

# System timezone
timezone US/Eastern --isUtc --ntpservers=10.16.31.254,clock.util.phx2.redhat.com,clock02.util.phx2.redhat.com

# Network information
network  --onboot yes --bootproto=dhcp --device=eth0 --ipv6=auto --activate

# Root password and Security Policy
rootpw  redhat
selinux --enforcing
firewall --service=ssh

# Shut down and power off the system after the installation has successfully completed.
poweroff

# Do not configure the X Window System
skipx


# System bootloader configuration --append= - Specifies additional kernel parameters. To specify multiple parameters, separate them with spaces.
bootloader --location=mbr --timeout=5 --append="crashkernel=auto rhgb quiet console=ttyS0,115200"

# Partition clearing information
autopart --type=plain
clearpart --all --initlabel --drives=vda
zerombr

%packages
@base
@core
@network-tools
%end

%post
cat >/etc/yum.repos.d/beaker-Server.repo <<REPO
[beaker-Server]
name=beaker-Server
baseurl=$location
enabled=1
gpgcheck=0
skip_if_unavailable=1
REPO

cat > /etc/yum.repos.d/beaker-tasks.repo << REPO
[beaker-tasks]
name=beaker-tasks
baseurl=http://beaker.engineering.redhat.com/rpms/
enabled=1
gpgcheck=0
skip_if_unavailable=1
REPO

yum install -y tuna git nano ftp wget sysstat 1>/root/post_install.log 2>&1
git clone https://github.com/Chrispin-Cheung/vmscripts.git /root/vmscripts 1>/root/post_install.log 2>&1
mv /root/vmscripts/* /root/. 1>/root/post_install.log 2>&1
rm -Rf /root/vmscripts 1>/root/post_install.log 2>&1

if [ "$VIOMMU" == "NO" ] && [ "$DPDK_BUILD" == "NO" ]; then
    /root/setup_rpms.sh 1>/root/post_install.log 2>&1
elif [ "$VIOMMU" == "YES" ] && [ "$DPDK_BUILD" == "NO" ]; then
    /root/setup_rpms.sh -v 1>/root/post_install.log 2>&1
elif [ "$VIOMMU" == "NO" ] && [ "$DPDK_BUILD" == "YES" ]; then
    /root/setup_rpms.sh -u 1>/root/post_install.log 2>&1
elif [ "$VIOMMU" == "YES" ] && [ "$DPDK_BUILD" == "YES" ]; then
    /root/setup_rpms.sh -u -v 1>/root/post_install.log 2>&1
fi

%end

shutdown

KS_CFG

if [ $STOP == "NO" ]; then
	echo creating new master image
	qemu-img create -f qcow2 $image_path/$master_image 40G
	echo undefining master xml
	virsh list --all | grep master && virsh undefine master
	echo calling virt-install

	if [ $DEBUG == "YES" ]; then
		virt-install --name=$vm \
		--virt-type=kvm \
		--disk path=$image_path/$master_image,format=qcow2,size=8,bus=virtio \
		--vcpus=$CPUS \
		--ram=4096 \
		--network bridge=$bridge \
		--graphics none \
		--extra-args="$extra" \
		--initrd-inject=$dist-vm.ks \
		--location=$location \
		--noreboot \
			--serial pty \
			--serial file,path=/tmp/$vm.console
	else
		virt-install --name=$vm \
			--virt-type=kvm \
			--disk path=$image_path/$master_image,format=qcow2,size=8,bus=virtio \
			--vcpus=$CPUS \
			--ram=4096 \
			--network bridge=$bridge \
			--graphics none \
			--extra-args="$extra" \
			--initrd-inject=$dist-vm.ks \
			--location=$location \
			--noreboot \
			--serial pty \
			--serial file,path=/tmp/$vm.console &> vminstaller.log
	fi
	if [ $PEK == "YES" ]; then
		nfs_server=netqe-bj.usersys.redhat.com
		shared_home=/home/share/
		DIST_SPATH=/mnt/share/tli/vsperf_img
	else
		nfs_server=netqe-infra01.knqe.lab.eng.bos.redhat.com
		shared_home=/home/www/html/share
	fi

	if [ $SAVED = "YES" ]; then
		qemu-img convert -O qcow2 $image_path/$master_image ${IMAGE_NAME}.qcow2
		#clean the vm and all spend storage
		virsh undefine --managed-save --snapshots-metadata --remove-all-storage --nvram $vm
		#automated upload the image file to the nfs server
		mkdir -p /mnt/share
		mount $nfs_server:$shared_home /mnt/share
		\cp ${IMAGE_NAME}.qcow2 $DIST_SPATH
		test -e $DIST_SPATH/${IMAGE_NAME}.qcow2 && echo "Uploaded the  image to NFS Server already."
		umount /mnt/share
		rm -f ${IMAGE_NAME}.qcow2
	fi

fi

rm $dist-vm.ks

setenforce $enforce_status
