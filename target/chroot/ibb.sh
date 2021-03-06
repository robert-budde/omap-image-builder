#!/bin/sh -e
#
# Copyright (c) 2015-2017 Robert Budde <robert.budde@ing-budde.de>
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

u_boot_release="v2017.03-rc3"

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

git_clone () {
	mkdir -p ${git_target_dir} || true
	qemu_command="git clone ${git_repo} ${git_target_dir} --depth 1 || true"
	qemu_warning
	git clone ${git_repo} ${git_target_dir} --depth 1 || true
	sync
	echo "${git_target_dir} : ${git_repo}" >> /opt/source/list.txt
}

git_clone_branch () {
	mkdir -p ${git_target_dir} || true
	qemu_command="git clone -b ${git_branch} ${git_repo} ${git_target_dir} --depth 1 || true"
	qemu_warning
	git clone -b ${git_branch} ${git_repo} ${git_target_dir} --depth 1 || true
	sync
	echo "${git_target_dir} : ${git_repo}" >> /opt/source/list.txt
}

git_clone_full () {
	mkdir -p ${git_target_dir} || true
	qemu_command="git clone ${git_repo} ${git_target_dir} || true"
	qemu_warning
	git clone ${git_repo} ${git_target_dir} || true
	sync
	echo "${git_target_dir} : ${git_repo}" >> /opt/source/list.txt
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

	echo "" >> /etc/securetty
	echo "#USB Gadget Serial Port" >> /etc/securetty
	echo "ttyGS0" >> /etc/securetty

	cp /usr/share/zoneinfo/Europe/Berlin /etc/localtime
}

install_git_repos () {
	git_repo="https://github.com/strahlex/BBIOConfig.git"
	git_target_dir="/opt/source/BBIOConfig"
	git_clone

	#am335x-pru-package
	if [ -f /usr/include/prussdrv.h ] ; then
		git_repo="https://github.com/biocode3D/prufh.git"
		git_target_dir="/opt/source/prufh"
		git_clone
		if [ -f ${git_target_dir}/.git/config ] ; then
			cd ${git_target_dir}/
			if [ -f /usr/bin/make ] ; then
				make LIBDIR_APP_LOADER=/usr/lib/ INCDIR_APP_LOADER=/usr/include
			fi
			cd /
		fi
	fi

	git_repo="https://github.com/RobertCNelson/dtb-rebuilder.git"
	git_target_dir="/opt/source/dtb-4.9-ti"
	git_branch="4.9-ti"
	git_clone_branch

	git_repo="https://github.com/beagleboard/bb.org-overlays"
	git_target_dir="/opt/source/bb.org-overlays"
	git_clone
	if [ -f ${git_target_dir}/.git/config ] ; then
		cd ${git_target_dir}/
		if [ ! "x${repo_rcnee_pkg_version}" = "x" ] ; then
			is_kernel=$(echo ${repo_rcnee_pkg_version} | grep 3.8.13 || true)
			if [ "x${is_kernel}" = "x" ] ; then
				if [ -f /usr/bin/make ] ; then
					if [ ! -f /lib/firmware/BB-ADC-00A0.dtbo ] ; then
						make
						make install
						make clean
					fi
					update-initramfs -u -k ${repo_rcnee_pkg_version}
				fi
			fi
		fi
	fi
}

install_pip3_pkgs () {
	if [ -f /usr/bin/pip3 ] ; then
		echo "Installing pip3 packages"

		pip3 install ephem
		pip3 install pyyaml
		pip3 install pyusb
	fi
}

install_knxd () {
	echo "Installing knxd"

	cd /
	# now build+install knxd itself
	git_repo="https://github.com/knxd/knxd.git"
	git_target_dir="knxd"
	git_branch="v0.12"
	git_clone_branch
	cd knxd
	dpkg-buildpackage -b -uc
	cd ..
	sudo dpkg -i knxd_*.deb knxd-tools_*.deb

	# clean-up
	rm -rf knxd* || true

	# customize systemd config
	sed -i -e 's;KNXD_OPTS=".*";KNXD_OPTS="-e 0.0.1 -E 0.0.2:8 --GroupCache -D -R -T -S --tpuarts-ack-all-group --tpuarts-ack-all-individual --layer2=tpuarts:/dev/ttyS2";g' /etc/knxd.conf

	# add knxd to dialout group to allow access to tty
	usermod -a -G dialout knxd
}

install_smarthomeNG_develop () {
	echo "Cloning smarthomeNG git repository (branch: develop)"
	mkdir -p /usr/local
	cd /usr/local
	sudo git clone --recursive -b release-1.3 git://github.com/smarthomeNG/smarthome.git

	echo "Configuring smarthomeNG"

	touch smarthome/etc/logic.conf

	cat > smarthome/etc/smarthome.conf <<- 'EOF'
		# smarthome.conf
		lat = 51.514167
		lon = 7.433889
		elev = 500
		tz = 'Europe/Berlin'
	EOF

	cat > smarthome/etc/plugin.conf <<- 'EOF'
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
		[ow]
		    class_name = OneWire
		    class_path = plugins.onewire
		    host = 127.0.0.1
		    port = 4304
		[visu]
		    class_name = WebSocket
		    class_path = plugins.visu_websocket
		[smartvisu]
		    class_name = SmartVisu
		    class_path = plugins.visu_smartvisu
		    smartvisu_dir = /var/www/html/smartVISU
		[cli]
		    class_name = CLI
		    class_path = plugins.cli
		    ip = 0.0.0.0
		    update = True
		[sql]
		    class_name = SQL
		    class_path = plugins.sqlite
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
	EOF

	echo "Setting ownership for smarthomeNG"
	chown -R smarthome:smarthome smarthome

	echo "Installing smarthomeNG systemd service"
	mkdir -p /etc/systemd/system
	cat > /etc/systemd/system/smarthome.service <<- 'EOF'
		[Unit]
		Description=smarthomeNG daemon
		After=network.target knxd.service owserver.service

		[Service]
		Type=forking
		ExecStart=/usr/bin/python3 /usr/local/smarthome/bin/smarthome.py
		User=smarthome
		PIDFile=/usr/local/smarthome/var/run/smarthome.pid
		Restart=on-abort

		[Install]
		WantedBy=default.target
	EOF
	systemctl enable smarthome.service
}

install_smartvisu () {
	mkdir -p /var/www/html
	cd /var/www/html
	rm -f index.html || true

	git_repo="https://github.com/Martin-Gleiss/smartvisu.git"
	git_target_dir="smartVISU"
	git_clone

	echo "Setting ownership for smartVISU"
	chown -R www-data:www-data smartVISU
	chmod -R 775 smartVISU

	echo "Setting ownership for smartVISU smarthome pages"
	cd smartVISU/pages/
	mkdir smarthome
	chown -R smarthome:smarthome smarthome
}

customize_owfs_systemd_services () {
	echo "Removing owserver init.d script"
	update-rc.d owserver remove
	rm /etc/init.d/owserver
	echo "Removing owhttpd init.d script"
	update-rc.d owhttpd remove
	rm /etc/init.d/owhttpd

	echo "Installing owserver systemd service"
	mkdir -p /etc/systemd/system
	cat > /etc/systemd/system/owserver.service <<- 'EOF'
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
	cat > /etc/systemd/system/owhttpd.service <<- 'EOF'
		[Unit]
		Description=Tiny webserver for 1-wire control
		Documentation=man:owhttpd(1)
		Requires=owserver.service
		After=owserver.service avahi-daemon.service

		[Service]
		ExecStart=/usr/bin/owhttpd --foreground --server=127.0.0.1:4304 --port=2121
		#User=ow
		#Group=ow

		[Install]
		WantedBy=multi-user.target
	EOF
	systemctl enable owhttpd.service
}

other_source_links () {
	rcn_https="https://rcn-ee.com/repos/git/u-boot-patches"

	mkdir -p /opt/source/u-boot_${u_boot_release}/
	wget --directory-prefix="/opt/source/u-boot_${u_boot_release}/" ${rcn_https}/${u_boot_release}/0001-omap3_beagle-uEnv.txt-bootz-n-fixes.patch
	wget --directory-prefix="/opt/source/u-boot_${u_boot_release}/" ${rcn_https}/${u_boot_release}/0001-am335x_evm-uEnv.txt-bootz-n-fixes.patch
	wget --directory-prefix="/opt/source/u-boot_${u_boot_release}/" ${rcn_https}/${u_boot_release}/0002-U-Boot-BeagleBone-Cape-Manager.patch

	echo "u-boot_${u_boot_release} : /opt/source/u-boot_${u_boot_release}" >> /opt/source/list.txt

	chown -R ${rfs_username}:${rfs_username} /opt/source/
}

unsecure_root () {
#	root_password=$(cat /etc/shadow | grep root | awk -F ':' '{print $2}')
#	sed -i -e 's:'$root_password'::g' /etc/shadow

#	if [ -f /etc/ssh/sshd_config ] ; then
#		#Make ssh root@beaglebone work..
#		sed -i -e 's:PermitEmptyPasswords no:PermitEmptyPasswords yes:g' /etc/ssh/sshd_config
#		sed -i -e 's:UsePAM yes:UsePAM no:g' /etc/ssh/sshd_config
#		#Starting with Jessie:
#		sed -i -e 's:PermitRootLogin without-password:PermitRootLogin yes:g' /etc/ssh/sshd_config
#	fi

	if [ -d /etc/sudoers.d/ ] ; then
		#Don't require password for sudo access
		echo "${rfs_username} ALL=NOPASSWD: ALL" >/etc/sudoers.d/${rfs_username}
		chmod 0440 /etc/sudoers.d/${rfs_username}
	fi
}

if [ -f /usr/bin/git ] ; then
	git config --global user.email "${rfs_username}@example.com"
	git config --global user.name "${rfs_username}"
	install_git_repos
	git config --global --unset-all user.email
	git config --global --unset-all user.name
fi

install_knxd

install_pip3_pkgs

install_smarthomeNG_develop

install_smartvisu

customize_owfs_systemd_services

other_source_links
#unsecure_root
#

