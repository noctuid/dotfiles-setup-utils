#!/usr/bin/env bash
# Helper Utilities for OSX/WSL setup scripts
# requirements:
# - bash
# - coreutils
# for nix package installation
# - nix
# if run nix_package_setup to install these, they aren't needed beforehand:
# - curl
# - git
# - gh
# - svn
# - yarn

rdotfiles=https://raw.githubusercontent.com/noctuid/dotfiles/master
svn_dotfiles=https://github.com/noctuid/dotfiles/trunk

_message() {
	echo
	echo "setup.sh: $*"
}

_errm() {
	echo
	echo "setup.sh: $*" >&2
}

# * Package Installation
# ** Nix/Home Manager
nix_pull() {
	lock=~/nix/flake.lock
	if [[ -f $1 ]]; then
		cp "$1" "$lock"
	fi

	tmp_lock=~/nix-tmp/flake.lock
	if [[ -f $lock ]]; then
		echo "Backup up existing flake.lock"
		mkdir -p ~/nix-tmp
		cp "$lock" "$tmp_lock"
	fi

	echo "Pulling nix config"
	svn checkout "$svn_dotfiles"/nix ~/nix
    # enable flakes and nix command
	mkdir -p ~/.config/nix
	ln -sf ~/nix/.config/nix/nix.conf ~/.config/nix/nix.conf
	if [[ $(uname -m) != arm64 ]]; then
		sed -i "" 's/aarch64-darwin/x86_64-darwin/g' ~/nix/flake.nix
	fi

	if [[ -f $tmp_lock ]]; then
		echo "Replacing pulled flake.lock with backed up version"
		cp "$tmp_lock" "$lock"
	fi
}

nix_channel_setup() {
	nix-channel \
		--add http://nixos.org/channels/nixpkgs-unstable nixpkgs
	# TODO probably remove this since only using through home-manager flake
	nix-channel \
		--add https://github.com/nix-community/home-manager/archive/master.tar.gz \
		home-manager
	nix-channel --update
}

nix_flake_update() (
	cd ~/nix || return 1
	nix flake update
)

nix_setup() (
	cd ~/nix || return 1
	if [[ $(uname -s) =~ ^Linux ]]; then
		# --impure needed for nixGL
		nix run "path:.#homeConfigurations.wsl.activationPackages" --impure \
			--show-trace
	else
		whoami | tr -d '\n' > ~/nix/darwin/username
		# --impure needed to look up <home-manager/nix-darwin>, for example
		nix build "path:.#darwinConfigurations.default.system" --impure \
			--show-trace
		if ! grep --quiet 'run\tprivate/var/run' /etc/synthetic.conf; then
			# macOS doesn't allow software to write to /, can put
			# directories/symlinks in /etc/synthetic.conf instead
			printf 'run\tprivate/var/run\n' | sudo tee -a /etc/synthetic.conf
			# create now instead of on reboot
			/System/Library/Filesystems/apfs.fs/Contents/Resources/apfs.util -t
		fi
		./result/sw/bin/darwin-rebuild switch --flake .#default --impure \
									   --show-trace
		# if home-manager's useUserPackages is enabled
		# source "/etc/profiles/per-user/$USER/etc/profile.d/hm-session-vars.sh"
		# failed
		# source "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"
	fi
)

# ** Yarn
yarn_global_install() {
	# TODO verify this works through yarn then remove
	# if ! hash yarn; then
	# 	_message "Installing yarn"
	# 	sudo npm install --global yarn
	# fi
	_message "Installing packages with yarn"
	# TODO verify these work through nix and then remove
	# sudo yarn global add pyright
	# sudo yarn global add typescript
	# sudo yarn global add typescript-language-server
	# TODO do I still need this?
	sudo yarn global add indium

	# should be installed for local project
	# sudo yarn global add prettier
}

# ** Pipx
# does not currently need to be shared

# * Emacs Setup
emacs_setup() (
	_message "Setting up Emacs with latest configuration."

	# useful here (but see http://mywiki.wooledge.org/BashFAQ/105)
	set -e

	mkdir -p ~/.emacs.d/lisp ~/.emacs.d/straight/versions
	curl "$rdotfiles"/emacs/.emacs.d/early-init.el > ~/.emacs.d/early-init.el
	curl "$rdotfiles"/emacs/.emacs.d/init.el > ~/.emacs.d/init.el
	curl "$rdotfiles"/emacs/.emacs.d/awaken.org > ~/.emacs.d/awaken.org
	curl "$rdotfiles"/emacs/.emacs.d/lisp/noct-util.el \
		 > ~/.emacs.d/lisp/noct-util.el
	curl "$rdotfiles"/emacs/.emacs.d/straight/versions/default.el \
		 > ~/.emacs.d/straight/versions/default.el

	mkdir -p ~/.emacs.d/yasnippet/{snippets,templates}
	# github doesn't support git-archive
	# however, it will convert to svn repo in backend
	# this can be used to get a specific folder
	svn checkout "$svn_dotfiles"/emacs/.emacs.d/etc/yasnippet/snippets \
		~/.emacs.d/yasnippet/snippets
	svn checkout "$svn_dotfiles"/emacs/.emacs.d/etc/yasnippet/templates \
		~/.emacs.d/yasnippet/templates
)

# * Shell Setup
shell_config_setup() {
	_message "Downloading shell config files"
	curl "$rdotfiles"/terminal/.zshrc > ~/.zshrc
	mkdir -p ~/.config/{kitty,tmux}
	curl "$rdotfiles"/terminal/.config/tmux/tmux.conf > ~/.config/tmux/tmux.conf
	curl "$rdotfiles"/terminal/.config/kitty/kitty.conf \
		 > ~/.config/kitty/kitty.conf
}

# * Git
# ** Git Config Setup
gitconfig_setup() {
	if [[ ! -f ~/.gitconfig ]] || ! grep --quiet email ~/.gitconfig; then
		echo "Enter the email address to normally use for git:"
		read -r email
		echo "[user]
	name = Fox Kiester
	email = $email
# probably won't use any of these besides dotfiles
# [includeIf \"gitdir:~/school/**\"]
#	path = .gitconfig-school
[includeIf \"gitdir:~/src/emacs/**\"]
	path = .gitconfig-personal
[includeIf \"gitdir:~/src/forks/**\"]
	path = .gitconfig-personal
[includeIf \"gitdir:~/src/mine/**\"]
	path = .gitconfig-personal
[includeIf \"gitdir:~/dotfiles/**\"]
	path = .gitconfig-personal
[includeIf \"gitdir:~/windots/**\"]
	path = .gitconfig-personal
" >> ~/.gitconfig
	fi

	if ! grep --quiet "[pull]" ~/.gitconfig 2> /dev/null; then
		echo "[pull]
	# require manual selection of rebase or merge if ff pull won't work
	ff = only
" >> ~/.gitconfig
	fi

	if [[ ! -f ~/.gitconfig-personal ]]; then
		echo "Enter the email address to use for committing the dotfiles repo:"
		read -r email
		echo "[user]
	email = $email
" >> ~/.gitconfig-personal
	fi
}

# ** Github Setup
# to be able to push this repo
github_auth_setup() {
	if gh auth status 2>&1 | grep --quiet "not logged in" 2> /dev/null; then
		gh auth login || _errm "Failed to set up github access token."
	fi
}
