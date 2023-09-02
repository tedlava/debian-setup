# debian-setup
This is a script that I use to setup computers running Debian Stable, currently Bookworm.


## USAGE
It is recommended (but not required) to copy any setup files you want customized into the ``~/Setup`` directory.  This will make it easier when installing/upgrading to newer versions of Debian Stable in the future.  At a minimum, the file ending with -config, as in ``bookworm-config``, should be copied to ``~/Setup`` and may include specific apt packages, flatpaks, Gnome extensions, and hardware parameters (to be loaded in grub during boot) for that specific machine.  If any config file is not found in ``~/Setup``, then the default config (from wherever you git-cloned this repository into) will be loaded instead.

### Requirements
1. Install Debian Stable (bookworm), with separate btrfs partitions for / and /home.  For newer computers, a separate /boot/efi partition is required.  I prefer to add a Linux swap partition of 4 GiB to the end of the hard drive instead of using a swap file.
2. Have patched fonts saved and unzipped in ~/fonts directory (default: Hack, https://github.com/ryanoasis/nerd-fonts/releases/download/v2.1.0/Hack.zip)
3. Have a stable Internet connection to download packages'

### Install git (git is not installed by default on Debian Stable)
    $ sudo apt install git

### Clone the repo onto your system
    $ git clone https://github.com/tedlava/debian-setup.git

### Copy config files and customize for this specific computer
    $ mkdir ~/Setup
    $ cp ./debian-setup/bookworm-config ~/Setup

*For further customization, repeat the above ``cp`` command but with different file names: ``bookworm-gsettings.txt``, ``bookworm-dconf.txt``, ``bash_aliases``, ``mimeapps.list``*

### Run the setup script
    $ ./debian-setup/bookworm-setup.sh

*There are a few options, ``-h`` to list them, ``-i`` is "interactive" mode, ``-f`` is "force" mode (but still has minimal interaction when rebooting or interacting with mandatory GUI elements)*


## SETUP FEATURES
Here is a summary of all the changes the script does to a Debian Stable installation, all of which are customizable/optional:
- Inhibit user suspend while plugged into AC power, so the computer doesn't suspend while the script is running
- Copy new ``GRUB_CMDLINE_LINUX_DEFAULT`` string into ``/etc/default/grub`` and ``update-grub``
- Move or rename btrfs subvolumes so they can be used with Timeshift.  ``@``, ``@home`` are the default subvolume names in Ubuntu, which is what Timeshift was configured to work with.
- Inhibit GDM's suspend while plugged into AC power, useful for SSHing into a server
- Purge unwanted packages
- SSD trim after deleting stuff to reclaim unused blocks
- Add ``contrib`` and ``non-free`` to sources.list (this still works with or without non-free-firmware at the end of the repository list) 
- Add i386 (32-bit) libraries if playing Windows games on wine, needed before apt installs
- Install git, curl, and timeshift
- Create initial timeshift snapshot
- Install all apt packages listed in ``-config`` file
- Install DVD libraries
- Add Flathub repository
- Download, compile, and install NeovimGtk from latest github source release
- Download and install Google Chrome and Windscribe VPN .deb packages from their respective websites
- Add private window to context menu for Firefox-ESR launcher
- Configure Firefox-ESR to use Wayland, if available
- Create launcher to switch between light/dark color color schemes in Gnome with Super+c
- Remove old configuration in .dotfiles
- Set up bash with .bash_aliases and a modified bash prompt (shows ISO 8601 datetime stamp and git repo)
- Set up Neovim (using https://github.com/tedlava/neovim-config.git)
- Load default applications mime types (double-click in Nautilus opens with your preferred apps); my default uses NeovimGtk to open all text files and VLC for videos
- Install and enable Gnome extensions from ``-config`` file
- Set up fonts that are saved in ~/fonts directory
- Load gsettings and dconf settings from their corresponding config files
- Create statup application to ignore suspend on closing lid (normally installed through Tweaks)
- Create startup application to move system-monitor indicator to my preferred position (far right)
- Create startup application to move workspace-indicator (on left, between Places and AppMenu indicators)
- Open display settings GUI to possibly change scaling
- Install flatpaks listed in ``-config`` file
- Configure Remote Touchpad to have a stable port so it will work through the firewall
- Create timeshift snapshot after setup script is complete
