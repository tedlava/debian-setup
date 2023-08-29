# debian-setup
This is a script that I use to setup computers running Debian Stable, currently Bookworm.

## USAGE
It is recommended (but not required) to copy any setup files you want customized into the ~/Setup directory.  This will make it easier when installing/upgrading to newer versions of Debian Stable in the future.  At a minimum, the file ending with -config, as in "bookworm-config", should be copied to ~/Setup and may include specific apt packages, flatpaks, Gnome extensions, and hardware parameters (to be loaded in grub during boot) for that specific machine.  If any config file is not found in ~/Setup, then the default config (from wherever you git-cloned this repository into) will be loaded instead.

### Install git (git is not installed by default on Debian Stable)
$ sudo apt install git

### Clone the repo onto your system
$ git clone https://github.com/tedlava/debian-setup.git

### Copy config files and customize for this specific computer
$ mkdir ~/Setup
$ cp ./debian-setup/bookworm-config ~/Setup
*For further customization, repeat the above command but with different file names: bookworm-gsettings.txt, bookworm-dconf.txt, bash_aliases, mimeapps.list*

### Run the setup script
$ ./debian-setup/bookworm-setup.sh
*There are a few options, -h to list them, -i is "interactive" mode, -f is "force" mode (but still has minimal interaction when rebooting or interacting with mandatory GUI elements)*
