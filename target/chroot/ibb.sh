#!/bin/sh -e
#
# Copyright (c) 2015 Robert Budde <>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

export LC_ALL=C

u_boot_release="v2015.01"

#contains: rfs_username, release_date
if [ -f /etc/rcn-ee.conf ] ; then
	. /etc/rcn-ee.conf
fi

if [ -f /etc/oib.project ] ; then
	. /etc/oib.project
fi

export HOME=/home/${rfs_username}
export USER=${rfs_username}
export USERNAME=${rfs_username}

echo "env: [`env`]"

is_this_qemu () {
	unset warn_qemu_will_fail
	if [ -f /usr/bin/qemu-arm-static ] ; then
		warn_qemu_will_fail=1
	fi
}

qemu_warning () {
	if [ "${warn_qemu_will_fail}" ] ; then
		echo "Log: (chroot) Warning, qemu can fail here... (run on real armv7l hardware for production images)"
		echo "Log: (chroot): [${qemu_command}]"
	fi
}

git_clone_branch () {
	mkdir -p ${git_target_dir} || true
	qemu_command="git clone -b ${git_branch} ${git_repo} ${git_target_dir} --depth 1 || true"
	qemu_warning
	git clone -b ${git_branch} ${git_repo} ${git_target_dir} --depth 1 || true
	sync
#	echo "${git_target_dir} : ${git_repo}" >> /opt/source/list.txt
}

setup_system () {
	#For when sed/grep/etc just gets way to complex...
	cd /
	if [ -f /opt/scripts/mods/debian-add-sbin-usr-sbin-to-default-path.diff ] ; then
		if [ -f /usr/bin/patch ] ; then
			echo "Patching: /etc/profile"
			patch -p1 < /opt/scripts/mods/debian-add-sbin-usr-sbin-to-default-path.diff
		fi
	fi

	if [ -f /opt/scripts/boot/am335x_evm.sh ] ; then
		if [ -f /lib/systemd/system/serial-getty@.service ] ; then
			cp /lib/systemd/system/serial-getty@.service /etc/systemd/system/serial-getty@ttyGS0.service
			ln -s /etc/systemd/system/serial-getty@ttyGS0.service /etc/systemd/system/getty.target.wants/serial-getty@ttyGS0.service

			echo "" >> /etc/securetty
			echo "#USB Gadget Serial Port" >> /etc/securetty
			echo "ttyGS0" >> /etc/securetty
		fi
	fi

    cp /usr/share/zoneinfo/Europe/Berlin /etc/localtime
}

install_pip3_pkgs () {
	if [ -f /usr/bin/pip3 ] ; then
		echo "Installing pip3 packages"

		pip3 install ephem
		#pip3 install pyusb

        wget http://downloads.sourceforge.net/project/pyusb/PyUSB%201.0/1.0.0-beta-2/pyusb-1.0.0b2.tar.gz
        tar -xzvf pyusb-1.0.0b2.tar.gz 
        cd pyusb-1.0.0b2/
        sudo python3 setup.py install
        cd ..
        rm pyusb-1.0.0b2.tar.gz
        rm -r pyusb-1.0.0b2
	fi
}

install_eibd () {
    # should be a repo...
    echo "Installing eibd packages"
    url="http://www.ing-budde.de/downloads/eibd"
    eibd_debs="libpthsem20_2.0.8_armhf.deb eibd-server_0.0.5_armhf.deb \
 libeibclient0_0.0.5_armhf.deb eibd-clients_0.0.5_armhf.deb"
    for deb in ${eibd_debs}; do
        wget ${url}/${deb}
        dpkg -i ${deb}
        rm ${deb}
    done    

    echo "Installing eibd systemd service"
    mkdir -p /etc/systemd/system
cat > /etc/systemd/system/eibd.service <<'EOF'
[Unit]
Description=eibd KNX daemon
After=network.target network-online.target connman.service avahi-daemon.service

[Service]
ExecStart=/usr/bin/eibd --eibaddr 1.1.0 --GroupCache --Server --Tunnelling --Discovery --tpuarts-ack-all-group --listen-tcp --listen-local tpuarts:/dev/ttyS2
Restart=on-failure
RestartSec=5
User=smarthome
Group=smarthome

[Install]
WantedBy=multi-user.target
EOF
    systemctl enable eibd.service
}

install_smarthome_py_develop () {
    echo "Cloning smarthome.py git repository (branch: develop)"
    mkdir -p /usr/local
    cd /usr/local
	git_repo="http://github.com/mknx/smarthome.git"
	git_branch="develop"
	git_target_dir="smarthome"
	git_clone_branch

    #wget https://github.com/mknx/smarthome/archive/develop.zip
    #unzip develop.zip -d .
    #mv smarthome-develop smarthome 

    echo "Setting ownership for smarthome.py"
    chown -R smarthome:smarthome smarthome

    echo "Configuring smarthome.py"
    cd smarthome/etc
    touch logic.conf
cat >smarthome.conf <<EOF
# smarthome.conf
lat = 51.514167
lon = 7.433889
elev = 500
tz = 'Europe/Berlin'
item_change_log = yes
EOF

cat >plugin.conf <<EOF
# plugin.conf
[knx]
    class_name = KNX
    class_path = plugins.knx
    host = 127.0.0.1
    port = 6720
#    send_time = 600 # update date/time every 600 seconds, default none
#    time_ga = 1/1/1 # default none
#    date_ga = 1/1/2 # default none
    busmonitor = yes
[visu]
    class_name = WebSocket
    class_path = plugins.visu
    smartvisu_dir = /var/www/html/smartVISU
    acl = rw
[sql]
    class_name = SQL
    class_path = plugins.sqlite
[ow]
    class_name = OneWire
    class_path = plugins.onewire
    host = 127.0.0.1
    port = 4304
[enocean]
    class_name = EnOcean
    class_path = plugins.enocean
    serialport = /dev/ttyS4
#[dlms]
#    class_name = DLMS
#    class_path = plugins.dlms
#    serialport = /dev/ttyS1
#    update_cycle = 20
#    use_checksum = True
#    reset_baudrate = False
#    no_waiting = True
[cli]
    class_name = CLI
    class_path = plugins.cli
    ip = 0.0.0.0
    update = True
EOF

    echo "Installing smarthome.py systemd service"
    mkdir -p /etc/systemd/system
cat > /etc/systemd/system/smarthome.service <<'EOF'
[Unit]
Description=SmartHome.py
After=eibd.service
After=owserver.service

[Service]
ExecStart=/usr/bin/python3 /usr/local/smarthome/bin/smarthome.py --foreground
User=smarthome
Group=smarthome

[Install]
WantedBy=multi-user.target
EOF
    systemctl enable smarthome.service
}

install_smartvisu () {
    mkdir -p /var/www/html
    cd /var/www/html
    rm -f index.html || true

	svn checkout http://smartvisu.googlecode.com/svn/trunk/ smartVISU

    #wget https://github.com/mknx/smarthome/archive/develop.zip
    #unzip develop.zip -d /usr/local
    #mv /usr/local/smarthome-develop /usr/local/smarthome 

#    chown -R smarthome:smarthome /usr/local/smarthome

#    echo "Installing smartvisu release 2.7"
#    wget http://smartvisu.de/download/smartVISU_2.7.zip
#    unzip smartVISU_2.7.zip
#    rm smartVISU_2.7.zip

    echo "Setting ownership for smartVISU"
    chown -R www-data:www-data smartVISU
    chmod -R 775 smartVISU

    echo "Setting ownership for smartVISU smarthome pages"
    cd smartVISU/pages/
    mkdir smarthome
    chown -R smarthome:smarthome smarthome
}

install_owfs_systemd_services () {
    echo "Removing owserver init.d script"
    update-rc.d owserver remove
    rm /etc/init.d/owserver
    echo "Removing owhttpd init.d script"
    update-rc.d owhttpd remove
    rm /etc/init.d/owhttpd

    echo "Installing owserver systemd service"
    mkdir -p /etc/systemd/system
cat > /etc/systemd/system/owserver.service <<'EOF'
[Unit]
Description=Backend server for 1-wire control
Documentation=man:owserver(1)

[Service]
ExecStart=/usr/bin/owserver --foreground --i2c=/dev/i2c-3 --i2c=/dev/i2c-4 --i2c=/dev/i2c-5 --i2c=/dev/i2c-6 --port=0.0.0.0:4304
Restart=on-failure
#User=ow
#Group=ow

[Install]
WantedBy=multi-user.target
EOF
    systemctl enable owserver.service

    echo "Installing owhttpd systemd service"
    mkdir -p /etc/systemd/system
cat > /etc/systemd/system/owhttpd.service <<'EOF'
[Unit]
Description=Tiny webserver for 1-wire control
Documentation=man:owhttpd(1)
Requires=owserver.service
After=owserver.service
After=avahi-daemon.service

[Service]
ExecStart=/usr/bin/owhttpd --foreground --server=127.0.0.1:4304 --port=2121
#User=ow
#Group=ow

[Install]
WantedBy=multi-user.target
EOF
    systemctl enable owhttpd.service
}

unsecure_root () {
	root_password=$(cat /etc/shadow | grep root | awk -F ':' '{print $2}')
	sed -i -e 's:'$root_password'::g' /etc/shadow

	if [ -f /etc/ssh/sshd_config ] ; then
		#Make ssh root@beaglebone work..
		sed -i -e 's:PermitEmptyPasswords no:PermitEmptyPasswords yes:g' /etc/ssh/sshd_config
		sed -i -e 's:UsePAM yes:UsePAM no:g' /etc/ssh/sshd_config
	fi

	if [ -f /etc/sudoers ] ; then
		#Don't require password for sudo access
		echo "${rfs_username}  ALL=NOPASSWD: ALL" >>/etc/sudoers
	fi
}

is_this_qemu

setup_system

install_eibd

install_pip3_pkgs

install_smarthome_py_develop

install_smartvisu

install_owfs_systemd_services

#unsecure_root

#
