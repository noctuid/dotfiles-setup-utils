#!/usr/bin/env bash
# Helper Utilities for OSX/WSL setup scripts
# requirements:
# - bash
# - coreutils
# - cargo (for cargo_install)
# - curl
# - jq
# for nix package installation
# - nix
# but if run nix install function to install these, they aren't needed beforehand:
# - git
# - yarn

rdotfiles=https://raw.githubusercontent.com/noctuid/dotfiles/master
USE_NIX=${USE_NIX:-false}

_message() {
	echo
	echo "setup.sh: $*"
}

_errm() {
	echo
	echo "setup.sh: $*" >&2
}

_is_linux() {
	[[ $(uname -s) =~ ^Linux ]]
}

_take() {
	mkdir -p "$1" && cd "$1"
}

_curl() {
	# curl --silent "$@"
	curl --progress-bar "$@"

}

_download_github_dir() (
	if ! hash jq 2> /dev/null; then
		_errm "Jq must be installed to download github directory"
	fi

	local repo path destdir item
	repo=$1
	path=$2
	destdir=$3
	_take "$destdir" || return 1
	_curl "https://api.github.com/repos/$repo/contents/$path" \
		| jq --compact-output '.[]' | while read -r item; do
		local file_type name
		file_type=$(echo "$item" | jq --raw-output '.type')
		name=$(echo "$item" | jq --raw-output '.name')
		case $file_type in
			file)
				local download_url
				download_url=$(echo "$item" | jq --raw-output '.download_url')
				echo "Downloading $name to $PWD"
				_curl "$download_url" > "$name" 2> /dev/null
				;;
			dir)
				local new_repo_path
				new_repo_path=$(echo "$item" | jq --raw-output '.path')
				_download_github_dir "$repo" "$new_repo_path" "$name"
				;;
		esac
	done
)

_download_dotfiles_dir() {  # <path> <dest>
	_download_github_dir noctuid/dotfiles "$1" "$2"
}

# * Package Installation
# ** Nix/Home Manager
# shellcheck disable=SC2120
nix_pull() {  # <optional lock file to use instead of stored one>
	lock=~/nix/flake.lock
	if [[ -f $1 ]]; then
		cp "$1" "$lock"
	fi

	tmp_lock=~/nix-tmp/flake.lock
	if [[ -f $lock ]]; then
	    _message "Backup up existing flake.lock"
		mkdir -p ~/nix-tmp
		cp "$lock" "$tmp_lock"
	fi

	_message "Downloading latest nix config"
	_download_dotfiles_dir nix ~/nix
    # enable flakes and nix command
	mkdir -p ~/.config/nix
	ln -sf ~/nix/.config/nix/nix.conf ~/.config/nix/nix.conf
	if ! _is_linux; then
		# TODO add function to remove zscaler cert in case zscaler stops working
		zscaler_cert="$HOME/Documents/zscaler.pem"
		if [[ -f $zscaler_cert ]] \
		   && ! grep --quiet "ssl-cert-file" ~/.config/nix/nix.conf; then
			_message "Configuring nix to work with Zscaler cert"
			echo "ssl-cert-file = $zscaler_cert" >> ~/.config/nix/nix.conf

		fi
		if [[ $(uname -m) != arm64 ]]; then
			# this sed syntax is not gnu sed
			sed -i "" 's/aarch64-darwin/x86_64-darwin/g' ~/nix/flake.nix
		fi
	fi

	if [[ -f $tmp_lock ]]; then
		_message "Replacing pulled flake.lock (which is inevitably out-of-date
for this machine) with backed up version"
		cp "$tmp_lock" "$lock"
	fi
}

nix_channel_setup() {
	_message "Updating nix channels"
	nix-channel \
		--add http://nixos.org/channels/nixpkgs-unstable nixpkgs
	# TODO probably remove this since only using through home-manager flake
	nix-channel \
		--add https://github.com/nix-community/home-manager/archive/master.tar.gz \
		home-manager
	nix-channel --update
}

nix_flake_update() (
	_message "Updating nix flake"
	cd ~/nix || return 1
	if [[ -n $1 ]]; then
		nix flake lock --update-input "$1"
	else
		nix flake update
	fi
)

nix_darwin_switch() {
	cd ~/nix || return 1
	./result/sw/bin/darwin-rebuild switch --flake .#default --impure \
								   --show-trace
}

nix_setup() (
	_message "Installing nix packages and performing home-manager setup"
	cd ~/nix || return 1
	if _is_linux; then
		# --impure needed for nixGL
		nix run "path:.#homeConfigurations.wsl.activationPackage" --impure \
			--show-trace
	else
		whoami | tr -d '\n' > ~/nix/darwin/username
		# --impure needed to look up <home-manager/nix-darwin>, for example
		nix build "path:.#darwinConfigurations.default.system" --impure \
			--show-trace || return 1
		if ! grep --quiet 'run\tprivate/var/run' /etc/synthetic.conf; then
			# macOS doesn't allow software to write to /, can put
			# directories/symlinks in /etc/synthetic.conf instead
			printf 'run\tprivate/var/run\n' | sudo tee -a /etc/synthetic.conf
			# create now instead of on reboot
			/System/Library/Filesystems/apfs.fs/Contents/Resources/apfs.util -t
		fi
		nix_darwin_switch
		# if home-manager's useUserPackages is enabled
		# source "/etc/profiles/per-user/$USER/etc/profile.d/hm-session-vars.sh"
		# failed
		# source "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"
	fi
)

# ** Yarn
# TODO probably remove
yarn_global_install() {
	# TODO verify this works through yarn then remove
	# if ! hash yarn; then
	# 	_message "Installing yarn"
	# 	sudo npm install --global yarn
	# fi
	_message "Installing packages with yarn (currently none)"
	# don't use yarn global for these
	# sudo yarn global add pyright
	# sudo yarn global add typescript
	# sudo yarn global add typescript-language-server
	# TODO do I still need this?
	# sudo yarn global add indium

	# needs to be installed through same node version using with nvm
	# npm install -g typescript @angular/language-server @angular/language-service

	# should be installed for local project
	# sudo yarn global add prettier
}

# ** Pipx
# does not currently need to be shared

# ** Cargo
cargo_install() {
	cargo install pyenv-python
	ln -s ~/.cargo/bin/python ~/.cargo/bin/python3
	cargo install taplo
}

# * Emacs Setup
emacs_pull() {
	_message "Downloading latest Emacs config files"
	_download_dotfiles_dir emacs/.emacs.d ~/.emacs.d
}

# * Shell Setup
shell_pull() {
	_message "Downloading latest shell config files"
	_curl "$rdotfiles"/terminal/.zshrc > ~/.zshrc
	mkdir -p ~/.config/{kitty,tmux,wezterm}
	_curl "$rdotfiles"/terminal/.config/tmux/tmux.conf > ~/.config/tmux/tmux.conf
	_curl "$rdotfiles"/terminal/.config/kitty/kitty.conf \
		 > ~/.config/kitty/kitty.conf
	_curl "$rdotfiles"/terminal/.config/wezterm/wezterm.lua \
		 > ~/.config/wezterm/wezterm.lua
}

# * Browser Setup
# NOTE this is only going to be cross platform if running browser through WSL
# don't include quickmarks; use own;maybe split into generic and nont
browser_pull() {
	_message "Downloading latest tridactyl/browser config files"
	target=~/.config/tridactyl
	_message "Downloading latest tridactyl config files"
	_download_dotfiles_dir browsing/.config/tridactyl "$target"
	# remove unneeded searchengines/quickmarks
	rm -f "$target"/other*
}

# * Pywal Setup
pywal_pull() {
	_message "Downloading latest pywal config files"
	_download_dotfiles_dir aesthetics/.config/wal ~/.config/wal
}

# * Git
# ** Git Config Setup
# TODO optionally add
# [http]
# sslCAInfo = ...zscaler cert full path
gitconfig_setup() {
	if [[ ! -f ~/.gitconfig ]] || ! grep --quiet email ~/.gitconfig; then
		_message "Enter the email address to normally use for git:"
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

# [http]
# 	sslCAInfo = ~/Documents/zscaler.pem
" >> ~/.gitconfig
	fi

	if ! grep --quiet "[pull]" ~/.gitconfig 2> /dev/null; then
		echo "[pull]
	# require manual selection of rebase or merge if ff pull won't work
	ff = only
" >> ~/.gitconfig
	fi

	if [[ ! -f ~/.gitconfig-personal ]]; then
		_message "Enter the email address to use for committing the dotfiles repo:"
		read -r email
		echo "[user]
	email = $email
" >> ~/.gitconfig-personal
	fi
}

# * Python Setup
python_pull() {
	_message "Downloading python config files"
	if _is_linux; then
		conf_dir=~/.config
	else
		conf_dir=~/"Library/Application Support"
	fi
	mkdir -p "$conf_dir"/{pypoetry,ruff}
	_curl "$rdotfiles"/common/.config/pypoetry/config.toml \
			> "$conf_dir"/pypoetry/config.toml
	_curl "$rdotfiles"/common/.config/ruff/ruff.toml \
			> "$conf_dir"/ruff/ruff.toml
}

# * Direnv Setup
direnv_pull() {
	mkdir -p ~/.config/direnv
	_curl "$rdotfiles"/common/.config/direnv/direnv.toml \
		 > ~/.config/direnv/direnv.toml
}

# * Pull All Config
all_config_pull() {
	if $USE_NIX; then
		nix_pull
	fi
	emacs_pull
	shell_pull
	browser_pull
	pywal_pull
	python_pull
	direnv_pull
}
