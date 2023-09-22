#!/bin/sh

# Stop at any error, show all commands
set -ex

WORKDIR=${SRCDIR:-/src}
cd "$WORKDIR"

source /commons.sh

# taken from https://github.com/cdrx/docker-pyinstaller/blob/master/linux/py3/entrypoint.sh
PYPI_URL=${PYPI_URL:-"https://pypi.python.org/"}
PYPI_INDEX_URL=${PYPI_INDEX_URL:-"https://pypi.python.org/simple"}
mkdir -p /root/pip
echo "[global]" > /root/pip/pip.conf
echo "index = $PYPI_URL" >> /root/pip/pip.conf
echo "index-url = $PYPI_INDEX_URL" >> /root/pip/pip.conf
echo "trusted-host = $(echo $PYPI_URL | sed -Ee 's|^.*?:\/\/(.*?)(:.*?)?\/.*$|\1|')" >> /root/pip/pip.conf

# Run shell commands before installing requirements
ALPINE_PRE_SHELL_CMDS=${ALPINE_PRE_SHELL_CMDS:-}
if [[ "$ALPINE_PRE_SHELL_CMDS" != "" ]]; then
    /bin/sh -c "$ALPINE_PRE_SHELL_CMDS"
fi

if [ -f requirements.txt ]; then
    pip install -r requirements.txt
fi

# Run shell commands after installing the requirements
ALPINE_SHELL_CMDS=${ALPINE_SHELL_CMDS:-}
if [[ "$ALPINE_SHELL_CMDS" != "" ]]; then
    /bin/bash -c "$ALPINE_SHELL_CMDS"
fi

# Run python commands after installing the requirements
ALPINE_PYTHON_CMDS=${ALPINE_PYTHON_CMDS:-}
if [[ "$ALPINE_PYTHON_CMDS" != "" ]]; then
    python3 "$ALPINE_PYTHON_CMDS"
fi

check_option DIST_PATH_OPTION "--distpath" "dist/alpine" "no" "no" "$@"
check_option HIDDEN_IMPORT_OPTION "--hidden-import" "pkg_resources.py2_warn" "yes" "yes" "$@"

pyinstaller \
    $DEFAULT_OPTIONS \
    $DIST_PATH_OPTION \
    $WORKPATH_OPTION \
    $P_OPTION \
    $ADD_BINARY_OPTION \
    $ADDITIONAL_HOOKS_OPTION \
    $HIDDEN_IMPORT_OPTION \
    $@

chown -R $(stat -c %u:%g .) dist
chown -R $(stat -c %u:%g .) *.spec

# Run shell commands after building binaries
ALPINE_POST_SHELL_CMDS=${ALPINE_POST_SHELL_CMDS:-}
if [[ "$ALPINE_POST_SHELL_CMDS" != "" ]]; then
    /bin/bash -c "$ALPINE_POST_SHELL_CMDS"
fi
