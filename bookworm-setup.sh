#!/bin/bash

# The purpose of this script is to automate the post-installation configuration
# to achieve my personal ideal setup.  Since I have several computers, I often
# find myself repeating these steps many times, since I have a tendency to
# experiment a little too much and have a bad habit of distro-hopping!  However,
# if I ever learn to kick the distro-hopping habit/hobby, there's a chance
# that I might make this awesome script and then never end up using it again!
# Of course, this might make it even easier to experiment with all the distros
# since I now have an easy way of restoring my Debian back to it's ideal state,
# so it also might make my distro-hopping even worse...  WTF...


# Change to script directory to use files as flag variables for saving the
# current state of the script
script_rel_dir=$(dirname "${BASH_SOURCE[0]}")
cd $script_rel_dir
script_dir=$(pwd)
delims="${0//[^\/]}"
len=$((${#delims}+1))
release_name=$(echo $0 | cut -d'/' -f$len | cut -d'-' -f1)


# Load variables from config file and paths for gsettings and dconf configs
if [ -f "$HOME/Setup/$release_name-config" ]; then
	settings_dir="$HOME/Setup"
else
	settings_dir="$script_dir"
fi
source $settings_dir/$release_name-config


function confirm_cmd {
	local cmd="$*"
	if [ -n "$interactive" ]; then
		echo -e "\nAbout to execute command...\n    $ $cmd"
		read -p 'Proceed? [Y/n] '
		if [ -z "$REPLY" ] || [ "${REPLY,}" == 'y' ]; then
			eval $cmd
		fi
	else
		echo -e "\nExecuting command...\n    $ $cmd\n"
		eval $cmd
	fi
}


function contains {
	local -n array=$1
	for i in "${array[@]}"; do
		if [ "$i" == "$2" ]; then
			echo $i
		fi
	done
}


echo
echo "Ted's Debian Setup Script"
echo '========================='
echo
echo "    Release: ${release_name^}"
echo


if [ "$(id -u)" -eq 0 ]; then
	echo
	echo 'Please run this shell script as a normal user (with sudo privileges).'
	echo "Some commands (such as gnome-extensions) need to connect to the user's"
	echo "Gnome environment and will not work if run as root."
	echo
	exit
fi


while getopts ':hif' opt; do
	case $opt in
	h)
		echo
		echo 'Help!'
		echo
		echo '        -i  Interactive mode'
		echo '        -f  Force (minimal interaction)'
		echo
		exit
		;;
	i)
		echo
		echo 'Interactive : You will be prompted for confirmation before'
		echo 'running EVERY SINGLE command!'
		echo
		interactive=1
		;;
	f)
		echo
		echo 'Force : Minimal interactive mode.  Some settings require using a GUI'
		echo 'and confirmation is still required before rebooting the computer.'
		echo
		force=1
		;;
	\?)
		echo
		echo 'You entered an incorrect option...'
		echo
		exit
		;;
	esac
done


# If -i or -f wasn't specified on the command line, ask user
if [ -z "$interactive" ] && [ -z "$force" ]; then
	echo
	echo 'Do you want to run the script in full interactive mode, which will ask for'
	read -p 'confirmation for every command that may alter your system? [y/N] '
	echo
	if [ "${REPLY,}" == 'y' ]; then
		interactive=1
	fi
fi


# Create status directory
if [ ! -d "$script_dir/status" ]; then
	echo
	echo "Create status directory to hold script's state between reboots..."
	confirm_cmd "mkdir $script_dir/status"
	echo
fi


# Create tmp directory to hold downloaded packages
if [ ! -d "$script_dir/tmp" ]; then
	errors=0
	echo
	echo 'Create temporary directory to hold downloaded packages...'
	confirm_cmd "mkdir $script_dir/tmp"
	((errors += $?))
	if [ "$errors" -ne 0 ]; then
		exit "$errors"
	fi
	echo
fi


if [ ! -f "$script_dir/status/reqs_confirmed" ]; then
	echo 'This script automates some common settings that I use for'
	echo 'every Debian installation while still allowing for some changes'
	echo 'through interactive questions.  You will be asked to enter your'
	echo 'password to sudo.'
	echo
	echo 'The script may require a few reboots, you will be prompted each'
	echo 'time.  After the script reboots your system, please re-run the'
	echo 'same script again and it should resume automatically.'
	echo
	echo 'Requirements:'
	echo "    - Debian ${release_name^} installed, / and /home partitions set up as btrfs"
	echo '    - Have patched fonts saved and unzipped in ~/fonts directory (default: Hack)'
	echo '    - Have a stable Internet connection to download packages'
	echo "    - Copied the files \"$release_name-config\", \"$release_name-gsettings.txt\", \"$release_name-dconf.txt\""
	echo '          to a ~/Setup directory and customized them for this specific computer'
	echo
	read -p 'Have all of the above been completed? [y/N] '
	if [ "${REPLY,}" != 'y' ]; then
		echo
		echo 'Please do those first, then run this script again!'
		echo
		exit
	fi
	touch "$script_dir/status/reqs_confirmed"
	echo
fi


# Inhibit user suspend while plugged into AC power, so the computer doesn't suspend while the script is running
if [ -n "$user_inhibit_ac" ] && [ ! -f "$script_dir/status/inhibited_user_ac_suspend" ]; then
	errors=0
	echo
	echo "Disabling suspend while on AC power (so your system doesn't suspend while installing lots of packages)..."
	confirm_cmd "gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing'"
	((errors += $?))
	if [ "$errors" -eq 0 ]; then
		touch "$script_dir/status/inhibited_user_ac_suspend"
	fi
	echo
fi


# Run commands as root (with sudo)
sudo -i home="$HOME" interactive="$interactive" bash "$script_dir/$release_name-as-root"


exit_code="$?"
if [ "$exit_code" -eq 93 ]; then
	# -as-root script exited normally with reboot flag set to 1
	reboot=1
elif [ "$exit_code" -gt 0 ]; then
	exit "$exit_code"
fi


# Remove old configuration in .dotfiles
if [ -n "$rm_dotfiles" ] && [ ! -f "$script_dir/status/removed_dotfiles" ]; then
	errors=0
	echo
	echo 'Removing old .dotfiles (from prior Linux installation)...'
	confirm_cmd "rm -rf $HOME/.*"
	((errors += $?))
	confirm_cmd "cp -av /etc/skel/. $HOME/"
	((errors += $?))
	if [ "$errors" -eq 0 ]; then
		touch "$script_dir/status/removed_dotfiles"
	fi
	echo
fi


# Set up bash with .bash_aliases and custom bash prompt (shows ISO 8601 datetime stamp and git repo)
if [ ! -f "$script_dir/status/bash_set_up" ]; then
	errors=0
	# This is SOOOOO ugly!  But part way through, it became more of a puzzle that I just wanted to solve, to see if it were possible to use a sed command to make this kind of modification...  Sorry!
	echo
	echo 'Copying any custom command line aliases from bash_aliases to ~/.bash_aliases...'
	if [ -f "$settings_dir/bash_aliases" ]; then
		bash_aliases_path="$settings_dir/bash_aliases"
	else
		bash_aliases_path="$script_dir/bash_aliases"
	fi
	confirm_cmd "cp -av $bash_aliases_path $HOME/.bash_aliases"
	((errors += $?))
	echo
	echo 'Setting up bash prompt to display git branch, if exists...'
	confirm_cmd "sed -i \"s~\(if \[ \\\"\\\$color_prompt\\\" = yes \]; then\)~function parse_git_branch {\\\\n\ \ \ \ git branch --no-color 2> /dev/null | sed -e '/^[^*]/d' -e 's/* \\\\\\\\(.*\\\\\\\\)/(\\\\\\\\1)/'\\\\n}\\\\n\1~\" $HOME/.bashrc"
	((errors += $?))
	confirm_cmd "sed -i \"s/PS1='\\\${debian_chroot:+(\\\$debian_chroot)}.*033.*/PS1=\\\"\\\${debian_chroot:+(\\\$debian_chroot)}\\\\\\\\[\\\\\\\\033[01;32m\\\\\\\\]\\\\\\\\u@\\\\\\\\h\\\\\\\\[\\\\\\\\033[00m\\\\\\\\]:\\\\\\\\[\\\\\\\\033[01;34m\\\\\\\\]\\\\\\\\w\\\\\\\\n\\\\\\\\[\\\\\\\\033[00;34m\\\\\\\\]\\\\\\\\D{%Y-%m-%d}\\\\\\\\[\\\\\\\\033[00m\\\\\\\\]T\\\\\\\\[\\\\\\\\033[00;34m\\\\\\\\]\\\\\\\\D{%H:%M} \\\\\\\\[\\\\\\\\033[0;32m\\\\\\\\]\\\\\\\\\\\$(parse_git_branch)\\\\\\\\[\\\\\\\\033[00m\\\\\\\\]\\\\\\\\$ \\\"/\" $HOME/.bashrc"
	((errors += $?))
	confirm_cmd "sed -i \"s/PS1='\\\${debian_chroot:+(\\\$debian_chroot)}.*h:.*/PS1=\\\"\\\${debian_chroot:+(\\\$debian_chroot)}\\\\\\\\u@\\\\\\\\h:\\\\\\\\w\\\\\\\\n\\\\\\\\D{%Y-%m-%dT%H:%M} \\\\\\\\\\\$(parse_git_branch)\\\\\\\\$ \\\"/\" $HOME/.bashrc"
	((errors += $?))
	if [ "$errors" -eq 0 ]; then
		touch "$script_dir/status/bash_set_up"
	fi
	echo
fi


# Set up Neovim
if [ -n "$(contains apt_installs neovim)" ] && [ ! -f "$script_dir/status/neovim_installed" ]; then
	errors=0
	# Clone neovim-config from GitHub
	echo
	echo 'Setting up Neovim config (init.vim)...'
	if [ ! -d "$HOME/dotfiles" ]; then
		confirm_cmd "mkdir $HOME/dotfiles"
		((errors += $?))
	fi
	if [ -d "$HOME/dotfiles/neovim-config" ]; then
		echo 'Found old neovim-config directory, moving to make room for new neovim-config...'
		confirm_cmd "mv $HOME/dotfiles/neovim-config $HOME/dotfiles/neovim-config-old"
		((errors += $?))
	fi
	confirm_cmd "git -C $HOME/dotfiles/ clone https://github.com/tedlava/neovim-config.git"
	((errors += $?))
	if [ ! -d "$HOME/.config/nvim" ]; then
		confirm_cmd "mkdir $HOME/.config/nvim"
		((errors += $?))
	fi
	if [ -L "$HOME/.config/nvim/init.vim" ]; then
		confirm_cmd "rm $HOME/.config/nvim/init.vim"
		((errors += $?))
	elif [ -f "$HOME/.config/nvim/init.vim" ]; then
		confirm_cmd "mv $HOME/.config/nvim/init.vim $HOME/.config/nvim/init-old.vim"
		((errors += $?))
	fi
	confirm_cmd "ln -s $HOME/dotfiles/neovim-config/init.vim $HOME/.config/nvim/"
	((errors += $?))
	confirm_cmd "sed -i 's/\(default_fontsize =\).*/\1 $patched_font_size/' $HOME/dotfiles/neovim-config/ginit.vim"
	((errors += $?))
	confirm_cmd "sed -i 's/\(font =\).*/\1 \"$patched_font\"/' $HOME/dotfiles/neovim-config/ginit.vim"
	((errors += $?))
	if [ -L "$HOME/.config/nvim/ginit.vim" ]; then
		confirm_cmd "rm $HOME/.config/nvim/ginit.vim"
		((errors += $?))
	elif [ -f "$HOME/.config/nvim/ginit.vim" ]; then
		confirm_cmd "mv $HOME/.config/nvim/ginit.vim $HOME/.config/nvim/ginit-old.vim"
		((errors += $?))
	fi
	confirm_cmd "ln -s $HOME/dotfiles/neovim-config/ginit.vim $HOME/.config/nvim/"
	((errors += $?))
	echo
	echo 'Installing vim-plug into Neovim...'
	confirm_cmd "sh -c 'curl -fLo \"${XDG_DATA_HOME:-$HOME/.local/share}\"/nvim/site/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'"
	((errors += $?))
	echo
	echo 'About to install Neovim plugins.  When Neovim is finished, please exit'
	echo 'Neovim by typing ":qa" and pressing ENTER.'
	echo
	echo '    *** Do NOT close the terminal window! ***'
	echo
	read -p 'Press ENTER to proceed with Neovim plugin installation. '
	confirm_cmd "nvim -c PlugInstall"
	((errors += $?))
	if [ "$errors" -eq 0 ]; then
		touch "$script_dir/status/neovim_installed"
	fi
	echo
fi


# Load default applications mime types (double-click in Nautilus opens with your preferred apps); my default uses NeovimGtk to open all text files and VLC for videos
if [ ! -f "$script_dir/status/changed_default_apps" ]; then
	errors=0
	echo
	echo 'Loading default applications mime types...'
	if [ -f "$settings_dir/mimeapps.list" ]; then
		mimeapps_path="$settings_dir/mimeapps.list"
	else
		mimeapps_path="$script_dir/mimeapps.list"
	fi
	confirm_cmd "cp -av $mimeapps_path $HOME/.config/"
	((errors += $?))
	if [ "$errors" -eq 0 ]; then
		touch "$script_dir/status/changed_default_apps"
	fi
	echo
fi


# Install Gnome extensions
if [ -n "${gnome_extensions[*]}" ] && [ ! -f "$script_dir/status/extensions_installed" ]; then
	errors=0
	echo
	echo 'Installing Gnome extensions...'
	gnome_ver=$(gnome-shell --version | cut -d' ' -f3)
	base_url='https://extensions.gnome.org'
	for extension in "${gnome_extensions[@]}"; do
		if [ -n "$(echo $extension | grep 'https://')" ]; then
			ext_uuid="$(curl -s $extension | grep -oP 'data-uuid="\K[^"]+')"
			info_url="$base_url/extension-info/?uuid=$ext_uuid&shell_version=$gnome_ver"
			download_url="$base_url$(curl -s "$info_url" | sed -e 's/.*"download_url": "\([^"]*\)".*/\1/')"
			confirm_cmd "curl -L '$download_url' > '$script_dir/tmp/$ext_uuid.zip'"
			((errors += $?))
			ext_dir="$HOME/.local/share/gnome-shell/extensions/$ext_uuid"
			confirm_cmd "gnome-extensions install $script_dir/tmp/$ext_uuid.zip"
			((errors += $?))
		fi
	done
	if [ "$errors" -eq 0 ]; then
		touch "$script_dir/status/extensions_installed"
		reboot=1
	fi
	echo
fi


# Set up fonts
if [ ! -f "$script_dir/status/fonts_installed" ]; then
	errors=0
	echo
	echo 'Setting up links to detect fonts...'
	confirm_cmd "ln -s $HOME/fonts $HOME/.local/share/fonts"
	((errors += $?))
	confirm_cmd 'fc-cache -fv'
	((errors += $?))
	if [ "$errors" -eq 0 ]; then
		touch "$script_dir/status/fonts_installed"
	fi
	echo
fi


# Load gsettings
if [ ! -f "$script_dir/status/gsettings_loaded" ]; then
	errors=0
	echo
	echo "Applying $release_name-gsettings.txt to Gnome..."
	# confirm_cmd in while loop won't work since it also uses 'read', so
	# confirmation must be asked beforehand if $interactive is true
	if [ -n "$interactive" ]; then
		echo -e "Load all settings from gsettings.txt using:\n    $ gsettings set \$schema \$key \"\$val\""
		read -p 'Proceed? [Y/n] '
	fi
	if [ -f  "$settings_dir/$release_name-gsettings.txt" ]; then
		gsettings_path="$settings_dir/$release_name-gsettings.txt"
	else
		gsettings_path="$script_dir/$release_name-gsettings.txt"
	fi
	if [ -z "$interactive" ] || [ -z "$REPLY" ] || [ "${REPLY,}" == 'y' ]; then
		while read -r schema key val; do
			echo -e "\nExecuting command...\n    $ gsettings set $schema $key \"$val\"\n"
			gsettings set $schema $key "$val"
			((errors += $?))
		done < "$gsettings_path"
	fi
	if [ "$errors" -eq 0 ]; then
		touch "$script_dir/status/gsettings_loaded"
	fi
	echo
fi


# Load dconf settings
if [ ! -f "$script_dir/status/dconf_loaded" ]; then
	errors=0
	echo
	echo "Applying $release_name-dconf.txt to Gnome..."
	if [ -f  "$settings_dir/$release_name-dconf.txt" ]; then
		dconf_path="$settings_dir/$release_name-dconf.txt"
	else
		dconf_path="$script_dir/$release_name-dconf.txt"
	fi
	confirm_cmd "dconf load / < $dconf_path"
	((errors += $?))
	if [ "$errors" -eq 0 ]; then
		touch "$script_dir/status/dconf_loaded"
	fi
	echo
fi


# Reboot
if [ "$reboot" -eq 1 ] || [ ! -f "$script_dir/status/patched_font_installed" ]; then
	echo
	echo 'The script needs to reboot your system.  When it is finished rebooting,'
	echo 'please re-run the same script and it will resume from where it left off.'
	echo
	read -p 'Press ENTER to reboot...'
	# Load patched monospace font immediately before reboot since it makes the terminal difficult to read
	if [ -n "$patched_font" ] && [ ! -f "$script_dir/status/patched_font_installed" ]; then
		errors=0
		echo
		echo 'Setting new system monospace font, terminal text will become distorted'
		echo 'then the reboot will happen immediately afterwards...'
		confirm_cmd "gsettings set org.gnome.desktop.interface monospace-font-name '$patched_font $patched_font_size'"
		((errors += $?))
		if [ "$errors" -eq 0 ]; then
			touch "$script_dir/status/patched_font_installed"
		fi
		echo
	fi
	systemctl reboot
	sleep 5
fi


# Enable Gnome extensions
if [ -n "${gnome_extensions[*]}" ] && [ ! -f "$script_dir/status/extensions_enabled" ]; then
	errors=0
	echo
	echo 'Enabling recently installed Gnome extensions...'
	for extension in "${gnome_extensions[@]}"; do
		if [ -n "$(echo $extension | grep 'https://')" ]; then
			ext_uuid="$(curl -s $extension | grep -oP 'data-uuid="\K[^"]+')"
		else
			ext_uuid="$extension"
		fi
		confirm_cmd "gnome-extensions enable ${ext_uuid}"
		((errors += $?))
	done
	if [ "$errors" -eq 0 ]; then
		touch "$script_dir/status/extensions_enabled"
	fi
	echo
fi


# Create statup application to ignore suspend on closing lid (normally installed through Tweaks)
if [ -n "$ignore_lid_switch" ] && [ ! -f "$script_dir/status/lid_tweak_installed" ]; then
	errors=0
	echo
	echo 'Applying tweak to ignore suspend on lid closing...'
	if [ ! -d "$HOME/.config/autostart" ]; then
		confirm_cmd "mkdir $HOME/.config/autostart"
		((errors += $?))
	fi
	confirm_cmd 'echo -e "[Desktop Entry]\\nType=Application\\nName=ignore-lid-switch-tweak\\nExec=/usr/libexec/gnome-tweak-tool-lid-inhibitor\\n" > $HOME/.config/autostart/ignore-lid-switch-tweak.desktop'
	((errors += $?))
	if [ "$errors" -eq 0 ]; then
		touch "$script_dir/status/lid_tweak_installed"
		reboot=1
	fi
	echo
fi


# Create startup application to move system-monitor indicator
if [ -n "$(echo "${gnome_extensions[@]}" | grep -o system-monitor)" ] && [ -n "$move_system_monitor" ] && [ ! -f "$script_dir/status/move_system_monitor_installed" ]; then
	errors=0
	echo
	echo 'Creating startup application to move Gnome extension system-monitor to the right of all indicators...'
	if [ ! -d "$HOME/.config/autostart" ]; then
		confirm_cmd "mkdir $HOME/.config/autostart"
		((errors += $?))
	fi
	confirm_cmd "echo -e \"[Desktop Entry]\\\\nType=Application\\\\nName=Move system-monitor indicator\\\\nComment=Moves user-installed Gnome extension system-monitor to the right of all indicators (updates periodically move it back to the middle)\\\\nExec=/usr/local/bin/move-system-monitor\\\\n\" > $HOME/.config/autostart/move-system-monitor.desktop"
	((errors += $?))
	confirm_cmd "move-system-monitor"
	((errors += $?))
	if [ "$errors" -eq 0 ]; then
		touch "$script_dir/status/move_system_monitor_installed"
		reboot=1
	fi
	echo
fi


# Create startup application to move workspace-indicator
if [ -n "$(echo "${gnome_extensions[@]}" | grep -o workspace-indicator)" ] && [ -n "$move_workspace_indicator" ] && [ ! -f "$script_dir/status/move_workspace_indicator_installed" ]; then
	errors=0
	echo
	echo 'Creating startup application to move Gnome extension workspace-indicator to the left panel box...'
	if [ ! -d "$HOME/.config/autostart" ]; then
		confirm_cmd "mkdir $HOME/.config/autostart"
		((errors += $?))
	fi
	confirm_cmd "echo -e \"[Desktop Entry]\\\\nType=Application\\\\nName=Move workspace-indicator\\\\nComment=Moves user-installed Gnome extension workspace-indicator to the left panel box (updates periodically move it back to the right)\\\\nExec=/usr/local/bin/move-workspace-indicator\\\\n\" > $HOME/.config/autostart/move-workspace-indicator.desktop"
	((errors += $?))
	confirm_cmd "move-workspace-indicator"
	((errors += $?))
	if [ "$errors" -eq 0 ]; then
		touch "$script_dir/status/move_workspace_indicator_installed"
		reboot=1
	fi
	echo
fi


# Open display settings to possibly change scaling
if [ ! -f "$script_dir/status/display_settings" ]; then
	errors=0
	echo
	echo 'Newer computers with HiDPI displays may need to adjust scaling settingshen'
	echo 'you are finished, close the window to continue with the setup script...'
	echo
	read -p 'Press ENTER to open Display Settings...'
	confirm_cmd 'gnome-control-center display'
	((errors += $?))
	if [ "$errors" -eq 0 ]; then
		touch "$script_dir/status/display_settings"
	fi
	echo
fi


# Install flatpaks, this step will take a while...
if [ -n "${flatpaks[*]}" ] && [ ! -f "$script_dir/status/flatpaks_installed" ]; then
	errors=0
	echo
	echo 'Installing Flatpak applications...'
	confirm_cmd "flatpak -y install ${flatpaks[@]}"
	((errors += $?))
	if [ "$errors" -eq 0 ]; then
		touch "$script_dir/status/flatpaks_installed"
	fi
	echo
fi


# Configure Remote Touchpad to have a stable port so it will work through the firewall
if [ -n "$(echo "${flatpaks[@]}" | grep -o RemoteTouchpad)" ] && [ -n "$remote_touchpad_port" ] && [ ! -f "$script_dir/status/remote_touchpad_set_up" ]; then
	errors=0
	echo
	echo "Configure Remote Touchpad Flatpak to always use port $remote_touchpad_set_up to work through the firewall..."
	desktop_file_path='/var/lib/flatpak/app/com.github.unrud.RemoteTouchpad/current/active/export/share/applications/com.github.unrud.RemoteTouchpad.desktop'
	confirm_cmd "sudo sed -i 's/\(Exec.*RemoteTouchpad.*\)/\1 --bind :$remote_touchpad_port/' $desktop_file_path"
	((errors += $?))
	if [ "$errors" -eq 0 ]; then
		touch "$script_dir/status/remote_touchpad_set_up"
		reboot=1
	else
		exit "$errors"
	fi
	echo
fi


# Remove tmp directory
if [ -d "$script_dir/tmp" ]; then
	errors=0
	echo
	echo 'Cleaning up tmp directory...'
	confirm_cmd "sudo rm -rfv $script_dir/tmp"
	((errors += $?))
	if [ "$errors" -ne 0 ]; then
		exit "$errors"
	fi
	echo
fi


# Final apt upgrade check (sometimes needed for nvidia)
if [ ! -f "$script_dir/status/final_apt_update" ]; then
	errors=0
	echo 'Final check for apt upgrades and clean up...'
	confirm_cmd 'sudo apt update && sudo apt -y upgrade && sudo apt -y autopurge && sudo apt -y autoclean'
	((errors += $?))
	if [ "$errors" -eq 0 ]; then
		touch "$script_dir/status/final_apt_update"
	else
		exit "$errors"
	fi
	echo
fi


# Reboot
if [ "$reboot" -eq 1 ]; then
	echo
	echo 'The script needs to reboot your system.  When it is finished rebooting,'
	echo 'please re-run the same script and it will resume from where it left off.'
	echo
	read -p 'Press ENTER to reboot...'
	systemctl reboot
	sleep 5
fi


# Create timeshift snapshot after setup script is complete
if [ ! -f "$script_dir/status/final_snapshot" ]; then
	errors=0
	echo
	echo 'Create a timeshift snapshot in case you screw up this awesome setup...'
	confirm_cmd "sudo timeshift --create --comments 'Debian ${release_name^} setup script completed' --yes"
	((errors += $?))
	if [ "$errors" -eq 0 ]; then
		touch "$script_dir/status/final_snapshot"
	else
		exit "$errors"
	fi
	echo
fi


# Settings to fix after this script...
echo
echo 'There are a few items that need to be setup through a GUI, or at least that'
echo "I haven't figured out how to do them through a bash script yet..."
echo
echo '    - Set user picture'
echo '    - Connect to online accounts'
echo '    - Run "sudo dmesg" and look for RED text, which may require more firmware'
echo '          than what was installed through this script'
echo '    - Set up Firefox:'
echo '          - Set up Firefox Sync, customize toolbar, restore synced tabs, etc.'
echo '          - Open Settings: DRM enabled, search with DuckDuckGo, remove Bing'
echo '    - Set up Google Chrome:'
echo '          - chrome://flags >> Preferred Ozone platform = Auto (uses Wayland, if present, X11 otherwise)'
if [ -n "$ssd" ]; then
	echo '          * For SSD:'
	echo '                - about:config >> browser.cache.disk.enable = false'
	echo '                - about:config >> browser.sessionstore.interval = 15000000'
	echo "          (add three 0's; this setting is how often Firefox saves sessions to"
	echo '          disk in case of a browser crash, not really needed with Firefox Sync)'
fi
echo
echo
echo "Ted's Debian Setup Script has finished.  If you want to run it again, please"
echo "delete the status directory at \"$script_dir/status/\", or even just specific"
echo 'sections that you want to set up again, and then re-run the script.'
echo
