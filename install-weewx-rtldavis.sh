#----------------------------------------------
#
# scripted install of weewx with rtldavis driver set to US units
#
# tested on debian-12 based Raspi OS
# with a rtl-sdr.com RTL2832U dongle
#
# last modified
#   2024-0323 - update to v5 weewx, pin golang version to 1.15
#   2022-0722 - original
#
#----------------------------------------------
# credits - thanks to another weewx user noticing that golang-1.15 still works
#           which was buried in their attachments in 
#            https://groups.google.com/g/weewx-user/c/bGiQPuOljqs/m/Mrvwe50UCQAJ
#            https://www.instructables.com/Davis-Van-ISS-Weather-Station-With-Raspbe/
#----------------------------------------------

# set these to 1 to run that block of code below

INSTALL_PREREQS=1          # package prerequisites to build the software
INSTALL_WEEWX=1            # weewx itself
INSTALL_LIBRTLSDR=1        # librtlsdr software
INSTALL_RTLDAVIS=1         # weewx rtldavis driver
RUN_WEEWX_AT_BOOT=0        # enable weewx in systemctl to startup at boot

#----------------------------------------------
#
# install required packages to enable building/running the software suite
# some of these might actually not be needed for v5 pip installations in a venv
# but I'll leave them here just in case
#

if [ "x${INSTALL_PREREQS}" = "x1" ]
then
    echo ".......installing prereqs..........."
    sudo apt-get update 
    sudo apt-get -y install python3-configobj python3-pil python3-serial python3-usb python3-pip python3-ephem python3-cheetah
fi

#-----------------------------------------------
#
# install weewx via the pip method
# and also nginx and hook them together
# then stop weewx (for now) so we can reconfigure it
#
# rather than duplicate the code here, this calls my other repo
# with the end-to-end script for this that can run standalone
#
# if piping wget to bash concerns you, please read the code there
# which hopefully is clear enough to put your mind at ease

if [ "x${INSTALL_WEEWX}" = "x1" ]
then
  wget -qO - https://raw.githubusercontent.com/vinceskahan/weewx-pipinstall/main/install-v5pip.sh | bash
  sudo systemctl stop weewx
fi

#-----------------------------------------------
#
# install rtldavis (ref:https://github.com/lheijst/rtldavis)
#
# changes - on debian-11 raspi we set the cmake option below to =OFF
#           rather than using the instructions in the older link above so that
#           we suppress librtlsdr writing a conflicting udev rules file into place
#
# you might need to edit the udev rule below if you have different tuner hardware
# so you might want to plug it in and run 'lsusb' and check the vendor and product values
# before proceeding
#

if [ "x${INSTALL_LIBRTLSDR}" = "x1" ]
then
    echo ".......installing librtlsdr........."
    sudo apt-get -y install golang-1.15 git cmake librtlsdr-dev

    # set up udev rules
    #
    # for my system with 'lsusb' output containing:
    #    Bus 001 Device 003: ID 0bda:2838 Realtek Semiconductor Corp. RTL2838 DVB-T

    echo 'SUBSYSTEM=="usb", ATTRS{idVendor}=="0bda", ATTRS{idProduct}=="2838", GROUP="adm", MODE="0666", SYMLINK+="rtl_sdr"' > /tmp/udevrules
    sudo mv /tmp/udevrules /etc/udev/rules.d/20.rtsdr.rules

    # get librtlsdr
    cd /home/pi
    if [ -d librtlsdr ]
    then
      rm -rf librtlsdr
    fi
    git clone https://github.com/steve-m/librtlsdr.git librtlsdr
    cd librtlsdr
    mkdir build
    cd build
    cmake ../ -DINSTALL_UDEV_RULES=OFF -DDETACH_KERNEL_DRIVER=ON
    make
    sudo make install
    sudo ldconfig

    # add to .profile for future
    #    'source ~/.profile' to catch up interactively
    GO_INFO_FOUND=`grep CONFIGURE_GO_SETTINGS ~/.profile | wc -l | awk '{print $1}'`
    if [ "x${GO_INFO_FOUND}" = "x0"  ]
    then
        echo ''                                                   >> ~/.profile
        echo '### CONFIGURE_GO_SETTINGS for rtdavis installation' >> ~/.profile
        echo 'export GOROOT=/usr/lib/go'                          >> ~/.profile
        echo 'export GOPATH=$HOME/work'                           >> ~/.profile
        echo 'export PATH=$PATH:$GOROOT/bin:$GOPATH/bin'          >> ~/.profile
    fi

    # for running here
    export GOROOT=/usr/lib/go
    export GOPATH=$HOME/work
    export PATH=$PATH:$GOROOT/bin:$GOPATH/bin

    # we pin golang to < 1.16 so Luc's instructions still work ok for
    # grabbing his code and building the resulting rtldavis binary
    # from source the old way.  Note however that this does not link that
    # version into the normal $PATH, so you need to call it with its full path

    cd /home/pi
    go env -w GO111MODULE=off
    /usr/lib/go/bin/go get -v github.com/lheijst/rtldavis
    cd $GOPATH/src/github.com/lheijst/rtldavis
    git submodule init
    git submodule update
    /usr/lib/go/bin/go install -v .

    # for EU users, to test rtldavis, run:
    #    $GOPATH/bin/rtldavis -tf EU
    #
    # if you get device busy errors, add to the modprobe blacklisted modules
    # (doing this requires a reboot for the blacklist to take effect)

    sudo apt install rtl-sdr
    echo 'blacklist dvb_usb_rtl28xxu' | sudo tee – append /etc/modprobe.d/blacklist-dvb_usb_rtl28xxu.confblacklist-8192cu.conf
    echo 'blacklist dvb_usb_rtl28xxu' | sudo tee - append /etc/modprobe.d/blacklist-8192cu.conf
    
    # add content from file https://osmocom.org/projects/rtl-sdr/repository/rtl-sdr/revisions/master/entry/rtl-sdr.rules
    # to new file /etc/udev/rules.d/rtl-sdr.rules
    
    #
    # again, for lsb output containing:
    #   Bus 001 Device 003: ID 0bda:2838 Realtek Semiconductor Corp. RTL2838 DVB-T
    #
    echo "blacklist dvb_usb_rtl28xxu" > /tmp/blacklist
    sudo cp /tmp/blacklist /etc/modprobe.d/blacklist_dvd_usb_rtl28xxu
    #
    # then reboot and try 'rtldavis -tf EU' again
    #
    # ref: https://forums.raspberrypi.com/viewtopic.php?t=81731
    #

fi

#-----------------------------------------------
#
# install the rtldavis weewx driver
# this assumes you did a venv pip installation

if [ "x${INSTALL_RTLDAVIS}" = "x1" ]
then
    echo ".......installing rtldavis.........."
    source /home/pi/weewx-venv/bin/activate
    weectl extension install -y https://github.com/lheijst/weewx-rtldavis/archive/master.zip
    weectl station reconfigure --driver=user.rtldavis --no-prompt

    # remove the template instruction from the config file
    echo "editing options..."
    sudo sed -i -e s/\\[options\\]// /home/pi/weewx-data/weewx.conf

    # US frequencies and imperial units
    # echo "editing US settings..."
    # sed -i -e s/frequency\ =\ EU/frequency\ =\ US/             /home/pi/weewx-data/weewx.conf
    # sed -i -e s/rain_bucket_type\ =\ 1/rain_bucket_type\ =\ 0/ /home/pi/weewx-data/weewx.conf

    # for very verbose logging of readings
    echo "editing debug..."
    sed -i -e s/debug_rtld\ =\ 2/debug_rtld\ =\ 3/             /home/pi/weewx-data/weewx.conf

fi

# We're going to test the executable alone to see that everything's working fine. 
# Most importantly we NEED to find the right frequencies. The go package has some EU frequencies 
# hardcoded (868077250, 868197250, 868317250, 868437250, 868557250) but those will likely not work 
# for you out of the box because of some discrepancies.

# Go into /home/pi/bin/ and tun this command
# ./rtldavis -startfreq 868000000 -endfreq 868600000 -stepfreq 10000

# Anyway, after finding your offset you can re-rung rtldavis in receiving mode
# ./rtldavis -fc 50000 -tf EU -tr 1 -ppm 1

#-----------------------------------------------

if [ "x${RUN_WEEWX_AT_BOOT}" = "x1" ]
then
    # enable weewx for next reboot
    sudo systemctl enable weewx
fi

#-----------------------------------------------
#
# at this point you can run 'sudo systemctl start weewx' to start weewx using the installed driver
# be sure to 'sudo tail -f /var/log/syslog' to watch progress (^C to exit)
#
# patience is required - on a pi4 running a RTL-SDR.COM RTL2832U dongle,
#    it takes over a minute for it to acquire the signal
#
# you might want to set the various driver debug settings to 0
# after you get it working to quiet things down especially if
# you use debug=1 for other reasons in your weewx configuration
#
# if you want to run 'rtldavis' as a non-privileged user, you should reboot here
#
#-----------------------------------------------

# Add BME280 Sensors for Pressure and Inside Temperature
# The ISS does not have sensors for pressure, nor it can measure inside temperature and humidity (obviously), 
# so to replicate the original Davis console we need to add these data manually. While Weewx can easily continue running 
# without inside temperature and humidity, pressure is such an important weather variable that it would be a pity not having
# it into the DB. Luckily you can use a cheap BME280 sensor to enhance the database with pressure, inside temperature and humidity.
#
# First of all we need to turn of the inside temperature and humidity captured by rtldavis
# sudo nano /usr/share/weewx/user/rtldavis.py
# look for DEFAULT_SENSOR_MAP and comment these two lines
# 'inTemp': 'temp_in', # temperature of optional BMP280 module
# 'inHumidity': 'humidity_in',
# Then connect the BME280 sensor with the right pins (see attached image) and make sure that I2C is enabled in raspi-config
# (https://www.raspberrypi-spy.co.uk/2014/11/enabling-the-i2c-interface-on-the-raspberry-pi/).
# Now you can install i2cdetect
# sudo apt install i2c-tools
# if everything went well you should be able to run the following command and see the output
# i2cdetect -y 1
# 0 1 2 3 4 5 6 7 8 9 a b c d e f
# 00:             -- -- -- -- -- -- -- --
# 10: -- -- -- -- -- -- -- -- -- -- 1a -- -- -- -- --
# 20: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
# 30: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
# 40: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
# 50: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
# 60: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
# 70: -- -- -- -- -- -- -- 77
# 77 is the address of our sensor, which we'll need later.
# Now that the sensor is working we need to (you say it) install a weewx driver that can parse this data. 
# Luckily there's already a driver ready to be downloaded: https://gitlab.com/mfraz74/bme280wx/ (note, I use a fork of the original project that reduces logging).
# Download and install the driver with
# sudo systemctl stop weewx
# wget https://gitlab.com/mfraz74/bme280wx/-/archive/master/bme280wx-master.zip
# source /home/pi/weewx-venv/bin/activate
# weectl extension install -y bme280wx-master.zip
# Then go into the configuration file /etc/weewx/weewx.conf and modify some lines
# [Bme280wx]
#  i2c_port = 1
#  i2c_address = 0x77
#  usUnits = US
#  temperatureKeys = inTemp
#  temperature_must_have = ""
#  pressureKeys = pressure
#  pressure_must_have = outTemp
#  humidityKeys = inHumidity
#  humidity_must_have = ""
# you'll notice we use the same address found with i2cdetect: in case you have a different address you of course need to change it. You can leave the rest as it is. 
# Just make sure that the Engine / Services part of the configuration file has data_services = user.bme280wx.Bme280wx (should be added automatically by the installation).
# Restart weewx and you should see the internal temperature and humidity, together with the pressure, being updated.

#  Where Is the Database/Modifying Values
# Unfortunately weewx does not give you the possibility to modify the data directly in the web interface.
# However, the data is stored into a simple database file that you can open, view and modify: it can be found in /var/lib/weewx/
# here is a sample Python script to read the data
# import sqlite3
# import pandas as pd
# con = sqlite3.connect('/var/lib/weewx/weewx.sdb')
# df = pd.read_sql_query("SELECT * from archive", con, index_col='dateTime')#.dropna(axis=1)
# df['datetime'] = pd.to_datetime(df.index, unit='s', utc=True)
# df['outTemp'] = df['outTemp'].apply(lambda x: (x-32.) * (5./9.) )
# df['inTemp'] = df['inTemp'].apply(lambda x: (x-32.) * (5./9.) )
# df['appTemp'] = df['outTemp'].apply(lambda x: (x-32.) * (5./9.) )
# df['heatindex'] = df['heatindex'].apply(lambda x: (x-32.) * (5./9.) )
# df['humidex'] = df['humidex'].apply(lambda x: (x-32.) * (5./9.) )
# df['barometer']=df['barometer'].apply(lambda x:  x * 33.86389 )
# df['pressure']=df['pressure'].apply(lambda x:  x * 33.86389 )
# df['altimeter']=df['altimeter'].apply(lambda x:  x * 33.86389 )
# df['dewpoint'] = df['dewpoint'].apply(lambda x: (x-32.) * (5./9.) )
# df['inDewpoint'] = df['dewpoint'].apply(lambda x: (x-32.) * (5./9.) )
# To modify the data see the article https://github.com/weewx/weewx/wiki/Cleaning-up-old-'bad'-data

# Upload Data Via FTP to a Server
# You can use the [[FTP]] skin to upload the data to your website so that you can access the data also on the go, not only in your local LAN.
# Just set the settings accordingly
#  [[FTP]]
#   skin = Ftp
#   enable = true
#   user = ...
#   password = ....
#   server = ....  # The ftp server name, e.g, www.myserver.org
#   path = ....  # The destination directory, e.g., /weather
#   secure_ftp = False
#   port = 21
#   passive = 1
#   ftp_encoding = latin-1
# Note that I used ftp_encoding = latin-1 because some servers only accept this encoding. if that's not the case for you just comment this line.
