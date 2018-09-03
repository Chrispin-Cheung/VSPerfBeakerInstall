# vmscripts

VM Installer script for use within beaker or other automated tasks.

Allows for creating of a fully tuned VM based on the kernel compose 
provided.

For beaker tests simply grab your compose location and then apply it 
to the execution of the script.

```
MYCOMPOSE=`cat /etc/yum.repos.d/beaker-Server.repo | grep baseurl | cut -c9-`

vmcreate.sh -c 3 -l $MYCOMPOSE
```

The -c is important to specify how the VM will be tuned. This option 
sets the tuned-adm cpu-partitioning profile how many CPUs to add
into its config file.  In the above example the VM will be tuned
for 3 VCPUs. This means Vcpu 1 and 2 will be isolated.

The -l option specifies the compose location. It can be set to
any valid compose location for VM installation. Even public compose
locations.

New feature:

1.Added the -V option to specify the os version of what image do you want
create.

However, the os_version must lower the host's os_version. 

if the os_version is newer than the host's os_version, the script will stop and output error message.

if you want to create the newer os_version guest image, you can use the -l option to specify the url to compose.

2.Added support for power8 and power9 systems, and it support both RHEL and RHEL-ALT well.

3.Added -s option to enable save the generated image to the nfs server automatedly

4.Added -S image_name  option to enable save the generate image as image_name with qcow2 format
           to the nfs server automatedly.

Example:

when your system is a RHEL-7.5,and you host is a x86_64 machine

	vmcreate.sh -c 3 
will automatedly create a RHEL-7.5 guest.

if you want to use the RHEL-7.4 guest,
just use -V option,like this

	vmcreate.sh -V 7.4


if you want to save the created guest image,
you can use -s option to enable it.like this
	
	vmcreate.sh -s
after the script ran, will create a image file on the 
http://netqe-infra01.knqe.lab.eng.bos.redhat.com/share/vms/

   if the release is RHEL, will save to http://netqe-infra01.knqe.lab.eng.bos.redhat.com/share/vms/RHEL/
   
   if the release is RHEL-ALT , will save to http://netqe-infra01.knqe.lab.eng.bos.redhat.com/share/vms/RHEL/ALT/
   
   the default naming rule of image name is that : RHEL-$ALT_FLAG-$OS_VERSION-$SYSTEM_ARCH-$create_date
   
   the default format of the image is qcow2.
   
   As above, the system is RHEL-7.5, so the ALT_FLAG is null, OS_VERSION is 7.5, SYSTEM_ARCH is x86_64, create_date is 20180724
   so the image_name is RHEL-7.5-x86_64-20180724.qcow2 and you can find it on http://netqe-infra01.knqe.lab.eng.bos.redhat.com/share/vms/RHEL/
   
if you want to save the created guest image with you specified name, you can use the -S option with your specfied name.	

	vmcreate.sh -S RHEL-7.5-GA
   then after finished, you can find the image on http://netqe-infra01.knqe.lab.eng.bos.redhat.com/share/vms/RHEL/
Note: 
the default released os version is supported well, just from 7.2 to 7.5.

Can not use the -l and -V option at the same time.



The script does disable selinux temporarily during it execution.

The script by default runs in silent mode with no output. If needed
a -d option can be added to get the full output. This is handy since
failures will not be shown on the screen. This logic will be added
later to better indicate a possible failure in installing the VM.

As part of the installation it will clone 
https://github.com/ctrautma/vmscripts.git inside of the VM and run
the setup_rpms.sh script which is responsible for pulling down
different DPDK versions as well as different useful scripts. Feel
free to request changes or submit a pull request to this repo to
update the VM filse that are installed.
