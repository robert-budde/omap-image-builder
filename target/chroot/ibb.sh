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

    echo "Installing eibd autostart script"
    mkdir -p /etc/init.d
cat > /etc/init.d/eibd <<'EOF'
#!/bin/sh
### BEGIN INIT INFO
# Provides:          eibd
# Required-Start:    $local_fs $remote_fs $network
# Required-Stop:     $local_fs $remote_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: eibd initscript
# Description:       based on init-script from knx-user-forum.de and setup-eibd.sh from KNXlive-project
#                    Pending: check tpuarts, check KNXnet/IP-Response
### END INIT INFO

PATH=/sbin:/usr/sbin:/bin:/usr/bin
DESC="EIB/KNX daemon"
NAME=eibd
DAEMON=/usr/bin/$NAME
PIDFILE=/var/run/$NAME.pid
DAEMON_ARGS="-e 1.1.0 -c -S -D -i -T --tpuarts-disch-reset --tpuarts-ack-all-group -d -u --pid-file=$PIDFILE tpuarts:/dev/ttyO2"
SCRIPTNAME=/etc/init.d/$NAME

# Exit if the package is not installed
[ -x "$DAEMON" ] || exit 0

# Load the VERBOSE setting and other rcS variables
. /lib/init/vars.sh

# Define LSB log_* functions.
# Depend on lsb-base (>= 3.0-6) to ensure that this file is present.
. /lib/lsb/init-functions

#
# Function that starts the daemon/service
#
do_start()
{
	#echo "DEBUG args: $DAEMON_ARGS eibdi: $EIBD_I eibdt: $EIBD_T eibdr: $EIBD_R backend: $EIBD_BACKEND url: $EIBD_URL port: $EIBD_PORT addrtab: $EIBD_BCUADDRTAB"
	# Return
        #   0 if daemon has been started
        #   1 if daemon was already running
        #   2 if daemon could not be started
        start-stop-daemon --start --quiet --pidfile $PIDFILE --exec $DAEMON --test > /dev/null \
                || return 1
	echo "*** Starting $DESC: $NAME using $EIBD_URL" 
        start-stop-daemon --start --quiet --pidfile $PIDFILE --exec $DAEMON -- \
                $DAEMON_ARGS \
                || return 2
        # Add code here, if necessary, that waits for the process to be ready
        # to handle requests from services started subsequently which depend
        # on this one.  As a last resort, sleep for some time.
	sleep 1
	chmod a+rw /tmp/eib
}
#
# Function that stops the daemon/service
#
do_stop()
{
        # Return
        #   0 if daemon has been stopped
        #   1 if daemon was already stopped
        #   2 if daemon could not be stopped
        #   other if a failure occurred
        start-stop-daemon --stop --quiet --retry=TERM/30/KILL/5 --pidfile $PIDFILE --name $NAME
        RETVAL="$?"
        [ "$RETVAL" = 2 ] && return 2
        # Wait for children to finish too if this is a daemon that forks
        # and if the daemon is only ever run from this initscript.
        # If the above conditions are not satisfied then add some other code
        # that waits for the process to drop all resources that could be
        # needed by services started subsequently.  A last resort is to
        # sleep for some time.
        start-stop-daemon --stop --quiet --oknodo --retry=0/30/KILL/5 --exec $DAEMON
	[ "$?" = 2 ] && return 2
        # Many daemons don't delete their pidfiles when they exit.
        rm -f $PIDFILE
        return "$RETVAL"
}

#
# Function that sends a SIGHUP to the daemon/service
#
do_reload() {
        #
        # If the daemon can reload its configuration without
        # restarting (for example, when it is sent a SIGHUP),
        # then implement that here.
        #
        start-stop-daemon --stop --signal 1 --quiet --pidfile $PIDFILE --name $NAME
        return 0
}

case "$1" in
  start)
        [ "$VERBOSE" != no ] && log_daemon_msg "Starting $DESC using $EIBD_URL" "$NAME"
        do_start
        case "$?" in
                0|1) log_end_msg 0 ;;
                2) [ log_end_msg 1 ;;
        esac
        ;;
  stop)
        [ "$VERBOSE" != no ] && log_daemon_msg "Stopping $DESC" "$NAME"
	echo "*** Stopping $DESC" "$NAME"
        do_stop
        case "$?" in
                0|1) log_end_msg 0 ;;
                2) [ log_end_msg 1 ;;
        esac
        ;;
  #reload|force-reload)
        #
        # If do_reload() is not implemented then leave this commented out
        # and leave 'force-reload' as an alias for 'restart'.
        #
        #log_daemon_msg "Reloading $DESC" "$NAME"
        #do_reload
        #log_end_msg $?
        #;;
  restart|force-reload)
        #
        # If the "reload" option is implemented then remove the
        # 'force-reload' alias
        #
        echo "*** Restarting $DESC" "$NAME"
        do_stop
        case "$?" in
          0|1)
		sleep 2
                do_start
                case "$?" in
                        0) log_end_msg 0 ;;
                        1) log_end_msg 1 ;; # Old process is still running
                        *) log_end_msg 1 ;; # Failed to start
                esac
                ;;
          *)

                # Failed to stop
                log_end_msg 1
                ;;
        esac
        ;;
  *)
        #echo "Usage: $SCRIPTNAME {start|stop|restart|reload|force-reload}" >&2
        echo "Usage: $SCRIPTNAME {start|stop|restart|force-reload}" >&2
        exit 3
        ;;
esac
EOF
    chmod +x /etc/init.d/eibd
    update-rc.d eibd defaults
}

install_smarthome_py_develop () {
    echo "Cloning smarthome.py git repository (branch: develop)"
    #mkdir -p /usr/local
    #cd /usr/local
    #git clone git://github.com/mknx/smarthome.git --branch develop
    #cd /usr/local/smarthome  
    #git pull

	#git_repo="http://github.com/mknx/smarthome.git"
	#git_branch="develop"
	#git_target_dir="/usr/local/smarthome"
	#git_clone_branch

    wget https://github.com/mknx/smarthome/archive/develop.zip
    unzip develop.zip -d /usr/local
    mv /usr/local/smarthome-develop /usr/local/smarthome
    

    echo "Setting ownership for smarthome.py"
    #usermod -G smarthome -a smarthome
    chown -R smarthome:smarthome /usr/local/smarthome

    echo "Configuring smarthome.py"
    cd /usr/local/smarthome/etc
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
#   send_time = 600 # update date/time every 600 seconds, default none
#   time_ga = 1/1/1 # default none
#   date_ga = 1/1/2 # default none
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
    serialport = /dev/ttyO4
[cli]
    class_name = CLI
    class_path = plugins.cli
    ip = 0.0.0.0
    update = True
EOF

    echo "Installing smarthome.py autostart script"
    mkdir -p /etc/init.d
cat > /etc/init.d/smarthome <<'EOF'
#!/bin/sh
### BEGIN INIT INFO
# Provides: smarthome
# Required-Start: $syslog $network
# Required-Stop: $syslog $network
# Should-Start: eibd owserver
# Should-Stop: eibd owserver
# Default-Start: 2 3 4 5
# Default-Stop: 0 1 6
# Short-Description: Start SmartHome.py
### END INIT INFO

DESC="SmartHome.py"
NAME=smarthome.py
SH_ARGS=""
SH_UID='smarthome'

PATH=/sbin:/usr/sbin:/bin:/usr/bin:/usr/local/bin
DAEMON=/usr/local/smarthome/bin/$NAME
PIDFILE=/usr/local/smarthome/var/run/smarthome.pid
SCRIPTNAME=/etc/init.d/$NAME

[ -x "$DAEMON" ] || exit 0

[ -r /etc/default/$NAME ] && . /etc/default/$NAME

DAEMON_ARGS="$SH_ARGS"

do_start()
{
    #touch $PIDFILE
    #chown $SH_UID $PIDFILE
    #start-stop-daemon --start --quiet --chuid $SH_UID --pidfile $PIDFILE --exec $DAEMON --test > /dev/null || return 1
    #start-stop-daemon --start --quiet --chuid $SH_UID --pidfile $PIDFILE --exec $DAEMON -- $DAEMON_ARGS || return 2
    sudo -u $SH_UID $DAEMON --start
}

do_stop()
{
    sudo -u $SH_UID $DAEMON --stop
    #start-stop-daemon --stop --quiet --retry=TERM/30/KILL/5 --pidfile $PIDFILE --name $NAME
    #RETVAL="$?"
    #[ "$RETVAL" = 2 ] && return 2
    #start-stop-daemon --stop --quiet --oknodo --retry=0/30/KILL/5 --exec $DAEMON
    #[ "$?" = 2 ] && return 2
    #rm -f $PIDFILE
    #return "$RETVAL"
}

do_reload() {
    start-stop-daemon --stop --signal 1 --quiet --pidfile $PIDFILE --name $NAME
    return 0
}

case "$1" in
    start)
        do_start
        ;;
    stop)
        do_stop
        ;;
    #reload|force-reload)
        #echo "Reloading $DESC" "$NAME"
        #do_reload
        #log_end_msg $?
        #;;
    restart)
        #
        # If the "reload" option is implemented then remove the
        # 'force-reload' alias
        #
        echo "Restarting $DESC" "$NAME"
        do_stop
        sleep 1
        do_start
        ;;
    *)
        echo "Usage: $SCRIPTNAME {start|stop|restart}" >&2
        exit 3
        ;;
esac
EOF
    chmod +x /etc/init.d/smarthome
    update-rc.d smarthome defaults
}

install_smartvisu_release_2_7 () {
    echo "Installing smartvisu release 2.7"
    mkdir -p /var/www/html
    cd /var/www/html
    rm -f index.html || true
    wget http://smartvisu.de/download/smartVISU_2.7.zip
    unzip smartVISU_2.7.zip
    rm smartVISU_2.7.zip
    chown -R www-data:www-data smartVISU
    chmod -R 775 smartVISU
    cd smartVISU/pages/
    mkdir smarthome
    chown -R smarthome:smarthome smarthome
}

install_owfs_config_file () {
cat > /etc/owfs.conf <<'EOF'
######################## SOURCES ########################
#
# With this setup, any client (but owserver) uses owserver on the
# local machine...
! server: server = localhost:4304
#
# ...and owserver uses the real hardware, by default fake devices
# This part must be changed on real installation
server: i2c = dev/i2c-3:0
server: i2c = dev/i2c-4:0
server: i2c = dev/i2c-5:0
server: i2c = dev/i2c-6:0
####################### OWHTTPD #########################

http: port = 2121

####################### OWSERVER ########################

server: port = 0.0.0.0:4304
EOF
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

install_smartvisu_release_2_7

install_owfs_config_file

cp /usr/share/zoneinfo/Europe/Berlin /etc/localtime

#unsecure_root

#
