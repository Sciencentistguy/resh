#!/usr/bin/env bash

set -euo pipefail

echo
echo "Checking your system ..."

# /usr/bin/zsh -> zsh
login_shell=$(echo "$SHELL" | rev | cut -d'/' -f1 | rev)

if [ "$login_shell" != bash ] && [ "$login_shell" != zsh ]; then
    echo "ERROR: Unsupported/unknown login shell: $login_shell"
    exit 1
fi
echo " * Login shell: $login_shell - OK"


# check like we are not running bash
bash_version=$(bash -c 'echo ${BASH_VERSION}')
bash_version_major=$(bash -c 'echo ${BASH_VERSINFO[0]}')
bash_version_minor=$(bash -c 'echo ${BASH_VERSINFO[1]}')
bash_too_old=""
if [ "$bash_version_major" -le 3 ]; then 
    bash_too_old=true
elif [ "$bash_version_major" -eq 4 ] && [ "$bash_version_minor" -lt 3 ]; then 
    bash_too_old=true
fi

if [ "$bash_too_old" = true ]; then
    echo " * Bash version: $bash_version - WARNING!"
    if [ "$login_shell" = bash ]; then
        echo "   > Your bash version is old."
        echo "   > Bash is also your login shell."
        echo "   > Updating to bash 4.3+ is strongly RECOMMENDED!"
    else
        echo "   > Your bash version is old"
        echo "   > Bash is not your login shell so it should not be an issue."
        echo "   > Updating to bash 4.3+ is recommended."
    fi
else
    echo " * Bash version: $bash_version - OK"
fi


if ! zsh --version >/dev/null 2>&1; then
    echo " * Zsh version: ? - not installed!"
else
    zsh_version=$(zsh -c 'echo ${ZSH_VERSION}')
    zsh_version_major=$(echo "$zsh_version" | cut -d'.' -f1)
    if [ "$zsh_version_major" -lt 5 ]; then 
        echo " * Zsh version: $zsh_version - UNSUPPORTED!"
        if [ "$login_shell" = zsh ]; then
            echo "   > Your zsh version is old."
            echo "   > Zsh is also your login shell."
            echo "   > Updating to Zsh 5.0+ is strongly RECOMMENDED!"
        else
            echo "   > Your zsh version is old"
            echo "   > Zsh is not your login shell so it should not be an issue."
            echo "   > Updating to zsh 5.0+ is recommended."
        fi
    else
        echo " * Zsh version: $zsh_version - OK"
    fi
fi


if [ "$(uname)" = Darwin ]; then
    if gnohup --version >/dev/null 2>&1; then
        echo " * Nohup installed: OK"
    else
        echo " * Nohup installed: NOT INSTALLED!"
        echo "   > You don't have nohup"
        echo "   > Please install GNU coreutils"
        echo
        echo "   $ brew install coreutils"
        echo
        exit 1
    fi
else
    if setsid --version >/dev/null 2>&1; then
        echo " * Setsid installed: OK"
    else
        echo " * Setsid installed: NOT INSTALLED!"
        echo "   > You don't have setsid"
        echo "   > Please install unix-util"
        echo
        exit 1
    fi
fi

# echo 
# echo "Continue with installation? (Any key to CONTINUE / Ctrl+C to ABORT)"
# # shellcheck disable=2034
# read -r x

echo 
echo "Creating directories ..."

mkdir_if_not_exists() {
    if [ ! -d "$1" ]; then
        mkdir "$1" 
    fi
}

mkdir_if_not_exists ~/.resh
mkdir_if_not_exists ~/.resh/bin
mkdir_if_not_exists ~/.resh/bash_completion.d
mkdir_if_not_exists ~/.resh/zsh_completion.d
mkdir_if_not_exists ~/.config

echo "Copying files ..."
cp -f submodules/bash-preexec/bash-preexec.sh ~/.bash-preexec.sh
cp -f submodules/bash-zsh-compat-widgets/bindfunc.sh ~/.resh/bindfunc.sh

cp -f conf/config.toml ~/.config/resh.toml

cp -f scripts/shellrc.sh ~/.resh/shellrc
cp -f scripts/reshctl.sh scripts/widgets.sh scripts/hooks.sh scripts/util.sh ~/.resh/

echo "Generating completions ..."
bin/resh-control completion bash > ~/.resh/bash_completion.d/_reshctl
bin/resh-control completion zsh > ~/.resh/zsh_completion.d/_reshctl

echo "Copying more files ..."
cp -f scripts/uuid.sh ~/.resh/bin/resh-uuid
cp -f bin/* ~/.resh/bin/
cp -f scripts/resh-evaluate-plot.py ~/.resh/bin/
cp -fr data/sanitizer ~/.resh/sanitizer_data

# backward compatibility: We have a new location for resh history file 
[ ! -f ~/.resh/history.json ] || mv ~/.resh/history.json ~/.resh_history.json 

echo "Finishing up ..."
# Adding resh shellrc to .bashrc ...
if [ ! -f ~/.bashrc ]; then
    touch ~/.bashrc
fi
grep -q '[[ -f ~/.resh/shellrc ]] && source ~/.resh/shellrc' ~/.bashrc ||\
	echo -e '\n[[ -f ~/.resh/shellrc ]] && source ~/.resh/shellrc' >> ~/.bashrc
# Adding bash-preexec to .bashrc ...
grep -q '[[ -f ~/.bash-preexec.sh ]] && source ~/.bash-preexec.sh' ~/.bashrc ||\
	echo -e '\n[[ -f ~/.bash-preexec.sh ]] && source ~/.bash-preexec.sh' >> ~/.bashrc
# Adding resh shellrc to .zshrc ...
if [ -f ~/.zshrc ]; then
    grep -q '[ -f ~/.resh/shellrc ] && source ~/.resh/shellrc' ~/.zshrc ||\
        echo -e '\n[ -f ~/.resh/shellrc ] && source ~/.resh/shellrc' >> ~/.zshrc
fi

# Deleting zsh completion cache - for future use
# [ ! -e ~/.zcompdump ] || rm ~/.zcompdump

# Final touch
touch ~/.resh_history.json

# Generating resh-uuid ...
[ -e ~/.resh/resh-uuid ] \
	|| cat /proc/sys/kernel/random/uuid > ~/.resh/resh-uuid 2>/dev/null \
	|| scripts/uuid.sh > ~/.resh/resh-uuid 2>/dev/null 

# Source utils to get __resh_run_daemon function
# shellcheck source=util.sh
. ~/.resh/util.sh

# Restarting resh daemon ...
if [ -f ~/.resh/resh.pid ]; then
    kill -SIGTERM "$(cat ~/.resh/resh.pid)" || true
    rm ~/.resh/resh.pid
else
    pkill -SIGTERM "resh-daemon" || true
fi
__resh_run_daemon



echo " 
##########################################################
#                                                        #
#    SUCCESS - thank you for trying out this project!    #
#                                                        #
##########################################################

 WARNING 
    It's recommended to RESTART all open terminal windows
 
 HISTORY
    Your resh history will be recorded to '~/.resh_history.json'
    Look at it using e.g. following command (you might need to install jq)
     $ tail -f ~/.resh_history.json | jq

    Your default shell history will stay intact.

 SANITIZATION
    In sanitized history, all sensitive information is replaced with its SHA1 hashes
     $ reshctl sanitize

    If you would consider supporting my research/thesis by giving me a sanitized version of your history then
    please give me some contact info using this form: https://forms.gle/227SoyJ5c2iteKt98

 ARROW KEY BINDINGS
    Resh provides arrow key bindings.
    These bindings do regular stepping through history and prefix search.
    They allow resh to record bindings usage metadata.
    
     * Enabled by default in zsh
     * Disabled by default in bash

    Enable/disable for THIS shell session
     $ reshctl enable arrow_key_bindings
     $ reshctl disable arrow_key_bindings

    Enable/disable for FUTURE shell sessions
     $ reshctl enable arrow_key_bindings_global
     $ reshctl disable arrow_key_bindings_global

    See what your current setting is
     $ reshctl status

 COMPLETIONS
    Zsh and bash completions for 'reshctl' command were installed and should be working.

 GRAPHS
    You can get some graphs of your history by running 
     $ <coming soon> 

 CHECK FOR UPDATES
     $ reshctl update

 RESH CLI - SEARCH THE RECORDED HISTORY
     RESH CLI searches your history by commands and directories.

     Directories are not in regular shell history. Because of that RESH CLI will only search shell history recorded by this project.
     This means that you should keep this project and try out RESH CLI in a month or so.

     Please remember that RESH CLI is still an early prototype.

     RESH CLI tool can be bound to ctrl+R or executed directly.

      * RESH CLI is not bound to ctrl+R by default

     Enable/disable ctrl+R binding for THIS shell session:
      $ reshctl enable ctrl_r_binding
      $ reshctl disable ctrl_r_binding

     Enable/disable for FUTURE shell sessions:
      $ reshctl enable ctrl_r_binding_global
      $ reshctl disable ctrl_r_binding_global

     Run the RESH CLI tool as a one-off:
      $ resh
 
 ISSUES
    Please report issues to: https://github.com/curusarn/resh/issues

 UNINSTALL
    You can uninstall resh at any time by running 
     $ rm -rf ~/.resh/
"