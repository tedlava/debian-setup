#!/bin/bash

# The purpose of this script is to automate the post-installation configuration
# to achieve my personal ideal setup.  Since I have several computers, I often
# find myself repeating these steps many times, since I have a tendency to
# experiment a little too much and have a bad habit of distro-hopping! However,
# I always have a tendency to come back to Debian, so there's also a chance
# that I might make this awesome script and then never end up using it all!  Of
# course, this might make it even easier to experiment with all the distros
# since I now have an easy way of restoring my Debian back to it's ideal state.


function confirm_cmd {
	local cmd="$*"
	if [ -n "$interactive" ]; then
		echo -e "About to execute command...\n    # $cmd"
		read -p 'Proceed? [Y/n] '
	fi
	if [ -z "$interactive" ] || [ -z "$REPLY" ] || [ "${REPLY,}" == 'y' ]; then
		eval $cmd
	fi
}

stable_name='bullseye'
echo "Ted's Debian Setup Script"
echo '========================='
echo
echo "    Release: ${stable_name^} (stable)"
echo


if [ `id -u` -ne 0 ]; then
	echo
	echo 'Please run this shell script with sudo or as root.'
	echo
	exit
fi


while getopts ':hi' opt; do
	case $opt in
	h)
		echo
		echo 'Help!'
		echo
		exit
		;;
	i)
		echo
		echo 'Full interactive mode!  You will be prompted before running EVERY SINGLE'
		echo 'command!  This is primarily for debugging and not how this script is intended'
		echo 'to be run, but if you want to verify every step along the way before actually'
		echo 'executing it, then go for it!'
		echo
		interactive=1
		;;
	\?)
		echo
		echo 'You entered an incorrect option...'
		echo
		exit
		;;
	esac
done


if [ ! -a deb_setup_part_1 ] && [ ! -a deb_setup_part_2 ]; then
	if [ ! -a fixed_btrfs ] ; then
		echo 'This script automates some common settings that I use for'
		echo 'every Debian installation while still allowing for some changes'
		echo 'through interactive questions.'
		echo
		echo 'The script may require a few reboots, you will be prompted each'
		echo 'time.  After the script reboots your system, please re-run the'
		echo 'same script again and it should resume automatically.'


		# Query user for requirements before proceeding
		echo
		echo 'Requirements:'
		echo "    - Debian ${stable_name^} is installed, / and /home partitions set up as btrfs"
		echo '    - Have patched fonts saved & unzipped in ~/fonts directory (default: Hack)'
		echo '    - Have a stable Internet connection to download packages'
		echo '    - Run "sudo dmesg" and look for RED text to know what firmware you need'
		echo
		read -p 'Have all of the above been completed? [y/N] '
		if [ "${REPLY,}" != 'y' ]; then
			echo
			echo 'Please do those first, then run this script again!'
			echo
			exit
		fi
		echo


		# Interactive mode?
		echo 'Do you want to run the script in full interactive mode, which will ask for'
		read -p 'confirmation for every command that may alter your system? [y/N] '
		if [ "${REPLY,}" != 'y' ]; then
			interactive=1
		fi


		# Move @rootfs btrfs subvolume to @ for timeshift
		if [ -n "$(grep @rootfs /etc/fstab)" ]; then
			read -p 'Rename the @rootfs btrfs subvolume to @ for timeshift? [Y/n] '
			if [ -z "$REPLY" ] || [ "${REPLY,}" == 'y' ]; then
				dev=$(grep '\s/\s' /etc/mtab | cut -d' ' -f1)
				echo "Detected your / partition is on device: $dev"
				confirm_cmd "mount $dev /mnt"
				confirm_cmd 'mv /mnt/@rootfs /mnt/@'
				old_root_fs=$(grep @rootfs /etc/fstab)
				new_root_fs=$(echo $old_root_fs | sed 's/@rootfs/@/')
				confirm_cmd "sed -i \"s|$old_root_fs|$new_root_fs|\" /etc/fstab"
				grub-install ${dev:0:$((${#dev}-1))}
				update-grub
				touch fixed_btrfs
				echo '@rootfs btrfs subvolume was renamed to @ for use with timeshift.'
				echo
			fi
		fi
		# Create @home subvolume if not present, and move all user directories to it
		if [ -z "$(grep @home /etc/fstab)" ]; then
			read -p 'Move /home directory into an @home btrfs subvolume for timeshift? [Y/n] '
			if [ -z "$REPLY" ] || [ "${REPLY,}" == 'y' ]; then
				dev=$(grep /home /etc/mtab | cut -d' ' -f1)
				echo "Detected your /home partition is on device: $dev"
				confirm_cmd "mount $dev /mnt"
				user_dirs=( $(ls /mnt) )
				confirm_cmd "btrfs subvolume create /mnt/@home"
				for dir in ${user_dirs[@]}; do
					confirm_cmd "mv /mnt/$dir /mnt/@home/"
				done
				old_home_fs=$(grep '/home.*btrfs' /etc/fstab)
				new_home_fs=$(grep '/home.*btrfs' /etc/fstab | sed 's/defaults/defaults,subvol=@home/')
				# sed -i "s|$old_home_fs|$new_home_fs|" /etc/fstab
				# confirm_cmd 'sed -i "s|'"$old_home_fs|$new_home_fs|"'" /etc/fstab'
				confirm_cmd "sed -i \"s|$old_home_fs|$new_home_fs|\" /etc/fstab"
				touch fixed_btrfs
				echo '@home btrfs subvolume was created and all user directories have'
				echo 'been moved to it.  '
			fi
		fi
		if [ -a fixed_btrfs ]; then
			echo 'Btrfs partitions have been modified.  The script needs to reboot your system.'
			echo 'When it is finished rebooting, please re-run this same script and it will'
			echo 'resume from where it left off.'
			echo
			read -p 'Press ENTER to reboot...'
			systemctl reboot
		fi
	fi


	# Remove old configuration in .dotfiles
	echo
	read -p 'Do you want to delete all old .dotfiles from your home directory? [Y/n] '
	if [ -z "$REPLY" ] || [ "${REPLY,}" == 'y' ]; then
		confirm_cmd "rm -rf $HOME/.*"
		confirm_cmd "rsync -avu /etc/skel/ $HOME/"
	fi
	echo


	# Add non-free and contrib to sources.list
	echo
	read -p 'Add non-free and contrib repositories to your /etc/apt/sources.list? [Y/n] '
	if [ -z "$REPLY" ] || [ "${REPLY,}" == 'y' ]; then
		confirm_cmd "sed -i 's/^\(deb.*$stable_name.*main\)$/\1 non-free contrib/' /etc/apt/sources.list"
	fi


	# Update/upgrade for base packages first
	echo
	echo 'Updating apt cache...'
	echo
	confirm_cmd 'apt-get update'
	echo
	read -p 'Upgrade packages? [Y/n] '
	if [ -z "$REPLY" ] || [ "${REPLY,}" == 'y' ]; then
		confirm_cmd 'apt-get -y upgrade'
	fi
	echo


	# Install basic utilities
	echo
	echo 'Installing rsync, git, curl, timeshift, and gufw...'
	echo
	confirm_cmd 'apt-get -y install rsync git curl timeshift gufw'
	echo


	# Inform user to take a snapshot with Timeshift, must use GUI
	echo
	echo 'Timeshift must be set up through the GUI before system snapshots can'
	echo 'be taken to rollback a bad update or configuration or installation'
	echo 'of a bad package.  Only use timeshift to snapshot the @ subvolume.'
	echo 'Check the boxes to add monthly and weekly snapshots as well.  All'
	echo 'other default settings should be sufficient.  Take an initial snapshot'
	echo "and give it a title like \"Debian ${stable_name^} installed\", just in case you"
	echo 'screw something up in the rest of the installation... ;)  After it is'
	echo 'done snapshotting the system, you may close the timeshift window.'
	echo
	read -p 'Press ENTER to open timeshift...'
	confirm_cmd 'timeshift-launcher'
	echo


	# Inform user to turn on firewall with Gufw, must use GUI
	echo
	echo 'Gufw (Graphical Uncomplicated Firewall) also needs to be set up through'
	echo 'its GUI.  In the Home profile, add a rule to allow all incoming requests'
	echo 'through SSH.  Make sure the firewall is turned on before closing the window.'
	echo
	read -p 'Press ENTER to open gufw...'
	confirm_cmd 'gufw'


	# SSD
	echo
	read -p 'Did you install Debian to an SSD? [Y/n] '
	if [ -z "$REPLY" ] || [ "${REPLY,}" == 'y' ]; then
		echo -e "\nTrimming to recover some disk space..."
		confirm_cmd 'fstrim -v /'
		confirm_cmd 'fstrim -v /home'
		echo 'Changing swappiness for SSD...'
		confirm_cmd 'echo -e "\\n#Swappiness\\nvm.swappiness=1\\n" >> /etc/sysctl.conf'
		echo 'It is also highly recommended that you modify your web browser settings'
		echo 'to prevent unnecessary writing to your SSD to extend its life.'
	fi
	echo


	# Purge unwanted packages
	echo
	echo 'Removing unwanted packages from the base installation...'
	confirm_cmd 'apt-get -y purge evolution'
	confirm_cmd 'apt-get -y autopurge'
	echo


	# Backports
	echo
	read -p 'Do you want to enable backports? [y/N] '
	if [ "${REPLY,}" == 'y' ]; then
		confirm_cmd "echo -e \"\\n# Backports\\ndeb http://deb.debian.org/debian ${stable_name}-backports main contrib non-free\" >> /etc/apt/sources.list"
		confirm_cmd 'apt-get update'
		echo
		read -p 'Do you want to install the latest kernel from backports? [y/N] '
		if [ "${REPLY,}" == 'y' ]; then
			backports=" -t ${stable_name}-backports "
			confirm_cmd "apt-get -y $backports install linux-image-amd64"
		else
			backports=''
		fi
	fi
	echo


	# Kernel headers
	echo
	read -p 'Do you want to install the Linux headers? (required for NVIDIA drivers) [y/N] '
	if [ "${REPLY,}" == 'y' ]; then
		confirm_cmd "apt-get -y $backports install linux-headers-amd64"
	fi
	echo


	# Firmware
	echo
	echo 'What firmware packages do you need?'
	echo
	firmware=''
	read -p 'firmware-misc-nonfree? [Y/n] '
	if [ "$REPLY" == '' ] || [ "${REPLY,}" == 'y' ]; then
		firmware="$firmware firmware-misc-nonfree"
	fi
	read -p 'intel-microcode? [Y/n] '
	if [ "$REPLY" == '' ] || [ "${REPLY,}" == 'y' ]; then
		firmware='$firmware intel-microcode'
	fi
	read -p 'amd64-microcode? [y/N] '
	if [ "${REPLY,}" == 'y' ]; then
		firmware="$firmware amd64-microcode"
	fi
	read -p 'firmware-realtek? [y/N] '
	if [ "${REPLY,}" == 'y' ]; then
		firmware="$firmware firmware-realtek"
	fi
	read -p 'firmware-atheros? [y/N] '
	if [ "${REPLY,}" == 'y' ]; then
		firmware="$firmware firmware-atheros"
	fi
	read -p 'firmware-iwlwifi? [y/N] '
	if [ "${REPLY,}" == 'y' ]; then
		firmware="$firmware firmware-iwlwifi"
	fi
	echo 'Please enter the package names (as they appear in the Debian repositories) of'
	echo 'any other firmware not listed above that you would like to install now'
	echo '(separated by spaces).'
	echo
	read -p 'Input extra firmware package names here, ENTER when finished: '
	if [ -n "$REPLY" ]; then
		firmware="$firmware $REPLY"
	fi

	if [ "$firmware" != '' ]; then
		confirm_cmd "apt-get -y $backports install $firmware"
	fi
	echo


	# GDM auto-suspend disabled
	# Can this be done more efficiently? I don't like the output of "No protocol specified"
	echo
	echo 'Setting up gdm to stay on when plugged in, but not logged in.'
	echo 'Will still auto-suspend if on battery power...'
	echo
	confirm_cmd "sudo -u Debian-gdm dbus-launch gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing'"
	echo


	# TLP for better battery life on laptops
	echo
	read -p 'Do you want to install TLP for better battery life on laptops? [Y/n] '
	if [ "$REPLY" == '' ] || [ "${REPLY,}" == 'y' ]; then
		confirm_cmd "apt-get -y $backports install tlp tlp-rdw"
	fi
	echo


	# Plymouth graphical boot up
	echo
	echo 'Installing Plymouth for graphical boot...'
	echo
	confirm_cmd 'apt-get -y install plymouth'
	echo
	echo 'Do you want to add any extra parameters to /etc/default/grub'
	echo 'GRUB_CMDLINE_LINUX_DEFAULT ? "splash" will already be added.'
	echo '   For example, pci=noaer'
	echo
	read -p 'Input your parameters here, ENTER when finished: '
	if [ "$REPLY" != '' ]; then
		grub=" $REPLY"
	fi
	# confirm_cmd "sed 's/GRUB_CMDLINE_LINUX_DEFAULT.*/GRUB_CMDLINE_LINUX_DEFAULT="'"'"quiet splash$grub"'"'"/' /etc/default/grub"
	confirm_cmd "sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT.*/GRUB_CMDLINE_LINUX_DEFAULT=\"quiet splash$grub\"/' /etc/default/grub"
	echo
	confirm_cmd 'update-grub'
	echo


	# Install Gnome extensions
	echo
	echo 'Installing Gnome extensions...'
	echo
	confirm_cmd 'apt-get -y install gir1.2-gtop-2.0'
	extensions=(
		https://extensions.gnome.org/extension/72/recent-items/
		https://extensions.gnome.org/extension/906/sound-output-device-chooser/
		https://extensions.gnome.org/extension/120/system-monitor/
	)
	for i in "${extensions[@]}"; do
		EXTENSION_ID=$(curl -s $i | grep -oP 'data-uuid="\K[^"]+')
		VERSION_TAG=$(curl -Lfs "https://extensions.gnome.org/extension-query/?search=$EXTENSION_ID" | jq '.extensions[0] | .shell_version_map | map(.pk) | max')
		confirm_cmd 'wget -O ${EXTENSION_ID}.zip "https://extensions.gnome.org/download-extension/${EXTENSION_ID}.shell-extension.zip?version_tag=$VERSION_TAG"'
		confirm_cmd "gnome-extensions install --force ${EXTENSION_ID}.zip"
		if ! gnome-extensions list | grep --quiet ${EXTENSION_ID}; then
			confirm_cmd "busctl --user call org.gnome.Shell.Extensions /org/gnome/Shell/Extensions org.gnome.Shell.Extensions InstallRemoteExtension s ${EXTENSION_ID}"
		fi
		confirm_cmd "gnome-extensions enable ${EXTENSION_ID}"
		confirm_cmd "rm ${EXTENSION_ID}.zip"
	done
	# Move system-monitor extension to the left of the status area
	confirm_cmd "sed -i \"s/Main.panel._addToPanelBox('system-monitor', tray, 1, panel);/Main.panel._addToPanelBox('system-monitor', tray, 0, panel);/\" $HOME/.local/share/gnome-shell/extensions/system-monitor@paradoxxx.zero.gmail.com/extension.js"
	echo


	# Install other system utilities
	echo
	echo 'Installing flatpak, vlc, and codecs...'
	echo
	confirm_cmd 'apt-get -y install flatpak gnome-software-plugin-flatpak vlc libavcodec-extra ipython3 catfish'
	confirm_cmd 'flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo'
	echo


	# DVD
	echo
	read -p 'Does this computer have a DVD drive, internal or external? [y/N] '
	if [ "$REPLY" == '' ] || [ "${REPLY,}" == 'y' ]; then
		confirm_cmd 'apt-get -y install libdvd-pkg'
		confirm_cmd 'dpkg-reconfigure libdvd-pkg'
	fi
	echo


	# Install DropBox
	echo
	read -p 'Install DropBox? (free account limits sync to 3 computers) [Y/n] '
	if [ "$REPLY" == '' ] || [ "${REPLY,}" == 'y' ]; then
		confirm_cmd 'apt-get -y install nautilus-dropbox'
	fi
	echo


	# Install Windscribe VPN
	echo
	read -p 'Install Windscribe? [Y/n] '
	if [ "$REPLY" == '' ] || [ "${REPLY,}" == 'y' ]; then
		confirm_cmd "curl -L https://windscribe.com/install/desktop/linux_deb_x64/beta -o $HOME/windscribe.deb"
		confirm_cmd "apt-get -y install $HOME/windscribe.deb"
		confirm_cmd "rm $HOME/windscribe.deb"
	fi
	echo


	# Set up fonts
	echo
	echo 'Setting up links to detect fonts...'
	echo
	confirm_cmd "sudo -u $USER ln -s $HOME/fonts $HOME/.local/share/fonts"
	confirm_cmd 'fc-cache -fv'
	echo


	# Install apps via apt
	echo
	echo 'Installing gimp, inkscape, gnucash, wine, and neovim dependencies...'
	echo
	confirm_cmd 'apt-get -y install python3-neovim xclip gimp gimp-data-extras inkscape inkscape-open-symbols gnucash python3-gnucash wine'
	echo


	# Load gsettings
	echo
	echo 'Applying gsettings.txt to Gnome...'
	echo
	file='gsettings.txt'
	while read -r schema key val; do
		confirm_cmd "gsettings set $schema $key \"$val\""
	done < "$file"
	echo
	

	# Load dconf settings
	echo
	echo 'Applying dconf_settings.txt to Gnome...'
	echo
	confirm_cmd 'dconf load / < dconf_settings.txt'
	echo


	# Install Neovim
	echo
	echo 'Installing Neovim...'
	echo
	# Clone neovim-config first
	confirm_cmd "sudo -u $USER mkdir $HOME/dotfiles"
	confirm_cmd "sudo -u $USER git -C $HOME/dotfiles/ clone https://github.com/tedlava/neovim-config.git"
	confirm_cmd "sudo -u $USER mkdir $HOME/.config/nvim"
	confirm_cmd "sudo -u $USER ln -s $HOME/dotfiles/neovim-config/init.vim $HOME/.config/nvim/"

	# Check all available versions in release, if greater than 0.4, install from apt, else download and install from github latest release!
	nvim_ver=$(apt list neovim -a 2>/dev/null | grep neovim | cut -d' ' -f2 | cut -c1-3 | sort | tail -n1)

	if [ $nvim_ver '>' '0.4' ]; then
		echo
		confirm_cmd 'apt-get -y install neovim'
		echo
	else
		echo
		echo 'Neovim version is too old in apt, downloading from github...'
		echo
		confirm_cmd "curl -L https://www.github.com$(curl -s -L https://github.com/neovim/neovim/releases/latest | grep 'href=\".*\.deb\"' | cut -d'\"' -f2) -o $HOME/nvim-github-latest-release.deb"
		confirm_cmd "apt-get -y install $HOME/nvim-github-latest-release.deb"
		confirm_cmd "rm $HOME/nvim-github-latest-release.deb"
	fi

	# Install vim-plug
	echo
	echo 'Installing vim-plug into Neovim...'
	echo
	confirm_cmd "sudo -u $USER sh -c 'curl -fLo \"${XDG_DATA_HOME:-$HOME/.local/share}\"/nvim/site/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'"
	echo
	echo 'About to install Neovim plugins.  When Neovim is finished, please exit'
	echo 'Neovim by typing ":qa" and then pressing ENTER.'
	echo '*** Do NOT close the terminal window! ***'
	echo
	read -p 'Press ENTER to proceed with Neovim plugin installation. '
	confirm_cmd "sudo -u $USER nvim -c PlugInstall"
	echo

	# Load Nautilus mime types for Neovim
	echo
	echo 'Loading Nautilus mime types (open all text files with Neovim)...'
	echo
	confirm_cmd "rsync -avu mimeapps.list $HOME/.config/"
	echo


	# NVIDIA drivers
	if [ "$(lspci | grep -i nvidia)" != '' ]; then
		echo
		echo 'Found nvidia graphics card...'
		echo
		confirm_cmd 'apt-get -y install nvidia-detect'
		echo
		echo 'Here is a list of possible nvidia drivers:'
		echo
		confirm_cmd 'apt list nvidia-*driver 2>/dev/null'
		echo
		echo 'Here is what nvidia-detect recommends:'
		confirm_cmd 'nvidia-detect'
		echo
		echo 'Please enter the name of the nvidia-driver package you'
		read -p 'want to install: '
		# dpkg --add-architecture i386
		confirm_cmd "apt-get -y install $REPLY"
		echo
	fi


	# Reboot
	echo
	echo 'Part 1 of the setup script is complete!  The system needs to reboot.  At the'
	echo 'login screen, please switch to "Gnome on Xorg" (bottom-right gear icon) then'
	echo 're-run this same script again and it will automatically start part 2.'
	echo
	touch deb_setup_part_1
	read -p 'Press ENTER to reboot...'
	systemctl reboot

elif [ -a deb_setup_part_1 ] && [ ! -a deb_setup_part_2 ]; then
	echo
	echo 'Proceeding with Part 2 of the setup script...'
	echo
	echo 'Do you want install the following apps via Flatpak?'
	flatpaks=''
	read -p '    - Google Chrome? [Y/n] '
	if [ -z "$REPLY" ] || [ "${REPLY,}" == 'y' ]; then
		flatpaks="$flatpaks com.google.Chrome"
	fi
	read -p '    - Xournalpp drawing app? [Y/n] '
	if [ -z "$REPLY" ] || [ "${REPLY,}" == 'y' ]; then
		flatpaks="$flatpaks com.github.xournalpp.xournalpp"
	fi
	read -p '    - Foliate ebook reader? [Y/n] '
	if [ -z "$REPLY" ] || [ "${REPLY,}" == 'y' ]; then
		flatpaks="$flatpaks com.github.johnfactotum.Foliate"
	fi
	read -p '    - Kdenlive video editor? [Y/n] '
	if [ -z "$REPLY" ] || [ "${REPLY,}" == 'y' ]; then
		flatpaks="$flatpaks org.kde.kdenlive"
	fi
	read -p '    - RetroArch game console emulator? [Y/n] '
	if [ -z "$REPLY" ] || [ "${REPLY,}" == 'y' ]; then
		flatpaks="$flatpaks org.libretro.RetroArch"
	fi
	read -p '    - StepMania dance step game? [Y/n] '
	if [ -z "$REPLY" ] || [ "${REPLY,}" == 'y' ]; then
		flatpaks="$flatpaks com.stepmania.StepMania"
	fi
	read -p '    - Jellyfin media player? [Y/n] '
	if [ -z "$REPLY" ] || [ "${REPLY,}" == 'y' ]; then
		flatpaks="$flatpaks com.github.iwalton3.jellyfin-media-player"
	fi

	if [ "$flatpaks" != '' ]; then
		confirm_cmd "flatpak -y install $flatpaks"
	fi
	echo

	confirm_cmd "sudo -u $USER mkdir -p $HOME/dotfiles/var"
	confirm_cmd "ln -s $HOME/dotfiles/var $HOME/.var"


	# Settings to fix after this script...
	echo
	echo 'There are a few items that need to be setup through a GUI, or at least that'
	echo "I haven't figured out how to do them through a bash script (often because I"
	echo "can't find the appropriate gsettings yet)..."
	echo
	echo '    - Set user picture'
	echo '    - Connect to online accounts'
	echo '    - Run "sudo dmesg" again and look for RED text, which may require more'
	echo '          firmware than what is installed through this script'
	echo '    - Set up Firefox:'
	echo '          - about:config >> media.webrtc.hw.h264.enabled = true'
	echo '                (for HW acceleration during video conferencing)'
	echo '          - Set up Firefox Sync, customize toolbar, restore synced tabs, etc.'
	echo '          - Open Settings: DRM enabled, DDG search and remove Bing'
	echo '          * For SSD:'
	echo '                - about:config >> browser.cache.disk.enable = false'
	echo "                - about:config >> browser.sessionstore.interval = 15000000 # add three 0's"
	echo '                      (this setting is for how often Firefox saves sessions to disk in case'
	echo "                      of a browser crash, which isn't really necessary with Firefox Sync)"
	echo
	touch deb_setup_part_2


elif [ -a deb_setup_part_1 ] && [ -a deb_setup_part_2 ]; then
	echo
	echo "Ted's Debian Setup Script has finished.  If you want to run it again,"
	echo 'please delete the temp files "fixed_btrfs", "deb_setup_part_1", and'
	echo '"deb_setup_part_2", and then re-run the script.'
	echo
fi
