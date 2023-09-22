#!/bin/bash


# Stop at any error, show all commands
set -ex

source /opt/msvc/bin/x64/msvcenv.sh
export DISTUTILS_USE_SDK=1

REPRO_BUILD=${REPRO_BUILD:-yes}
if [[ "$REPRO_BUILD" == "yes" ]]; then
    export PYTHONHASHSEED=1
fi
export PYTHONDONTWRITEBYTECODE=1

PLATFORMS=${PLATFORMS:-win,linux,alpine}

WORKDIR=${SRCDIR:-/src}
pushd "$WORKDIR"

source /commons.sh

ORIGINAL_DISTPATH=$DISTPATH

# taken from https://github.com/cdrx/docker-pyinstaller/blob/master/linux/py3/entrypoint.sh
PYPI_URL=${PYPI_URL:-"https://pypi.python.org/"}
PYPI_INDEX_URL=${PYPI_INDEX_URL:-"https://pypi.python.org/simple"}
mkdir -p /root/pip
mkdir -p /wine/drive_c/users/root/pip
echo "[global]" > /root/pip/pip.conf
echo "index = $PYPI_URL" >> /root/pip/pip.conf
echo "index-url = $PYPI_INDEX_URL" >> /root/pip/pip.conf
echo "trusted-host = $(echo $PYPI_URL | perl -pe 's|^.*?://(.*?)(:.*?)?/.*$|$1|')" >> /root/pip/pip.conf
ln /root/pip/pip.conf /wine/drive_c/users/root/pip/pip.ini

# Run shell commands before installing requirements
PRE_SHELL_CMDS=${PRE_SHELL_CMDS:-}
if [[ $PLATFORMS == *"linux"* || $PLATFORMS == *"win"* ]]; then
    if [[ "$PRE_SHELL_CMDS" != "" ]]; then
        /bin/bash -c "$PRE_SHELL_CMDS"
    fi
fi

# Install requirements
if [ -f requirements.txt ]; then
    if [[ $PLATFORMS == *"linux"* ]]; then
        pip install -r requirements.txt
    fi
    if [[ $PLATFORMS == *"win"* ]]; then
        /usr/win64/bin/pip install -r requirements.txt
    fi
fi

# Run shell commands after installing the requirements
SHELL_CMDS=${SHELL_CMDS:-}
if [[ $PLATFORMS == *"linux"* || $PLATFORMS == *"win"* ]]; then
    if [[ "$SHELL_CMDS" != "" ]]; then
        /bin/bash -c "$SHELL_CMDS"
    fi
fi

# Run python commands after installing the requirements
PYTHON_CMDS=${PYTHON_CMDS:-}
if [[ $PLATFORMS == *"linux"* || $PLATFORMS == *"win"* ]]; then				  
    if [[ "$PYTHON_CMDS" != "" ]]; then
        if [[ $PLATFORMS == *"linux"* ]]; then
            python3 "$PYTHON_CMDS"
        elif [[ $PLATFORMS == *"win"* ]]; then
            /usr/win64/bin/python "$PYTHON_CMDS"
        fi
    fi
fi

echo "$@"

if check_for_spec_file "$@"; then
    HAS_SPEC_FILE=yes
else
    HAS_SPEC_FILE=no
fi

# Check DISABLE_DEFAULT_OPTIONS
DISABLE_DEFAULT_OPTIONS=${DISABLE_DEFAULT_OPTIONS:-no}
if [ "$DISABLE_DEFAULT_OPTIONS" == "no" ] && [ "$HAS_SPEC_FILE" == "no" ]; then
    DEFAULT_OPTIONS="--log-level=DEBUG --clean --noupx --noconfirm"
else
    DEFAULT_OPTIONS=""
fi

# Use the check_option function to get values for options
check_option WORKPATH_OPTION "--workpath" "/tmp" "no" "no" "$@"
check_option ADD_BINARY_OPTION "--add-binary" "/usr/local/lib/libcrypt.so.2:." "yes" "yes" "$@"
check_option ADDITIONAL_HOOKS_OPTION "--additional-hooks-dir" "/hooks" "yes" "yes" "$@"
check_option P_OPTION "-p" "." "no" "yes" "$@"

ret=0
if [[ $PLATFORMS == *"linux"* ]]; then
    check_option DIST_PATH_OPTION "--distpath" "dist/linux" "no" "no" "$@"
    check_option HIDDEN_IMPORT_OPTION "--hidden-import" "pkg_resources.py2_warn" "yes" "yes" "$@"
    # pip install --upgrade pyinstaller
    pyinstaller \
        $DEFAULT_OPTIONS \
        $DIST_PATH_OPTION \
        $WORKPATH_OPTION \
        $P_OPTION \
        $ADD_BINARY_OPTION \
        $ADDITIONAL_HOOKS_OPTION \
        $HIDDEN_IMPORT_OPTION \
        $@
    ret=$?
    if [[ -n "$DISTPATH" && -d "$DISTPATH" ]]; then
        chown -R --reference=. $DISTPATH
    fi
    DISTPATH=$ORIGINAL_DISTPATH
fi

if [[ $PLATFORMS == *"win"* && $ret == 0 ]]; then

    check_option DIST_PATH_OPTION "--distpath" "dist/windows" "no" "no" "$@"
    check_option HIDDEN_IMPORT_OPTION "--hidden-import" "win32timezone pkg_resources.py2_warn" "yes" "yes" "$@"
    # /usr/win64/bin/pip install --upgrade pyinstaller
    /usr/win64/bin/pyinstaller \
        $DEFAULT_OPTIONS \
        $DIST_PATH_OPTION \
        $WORKPATH_OPTION \
        $P_OPTION \
        $HIDDEN_IMPORT_OPTION \
        $@
    ret=$?

    if [[ $ret == 0 && $CODESIGN_KEYFILE != "" && $CODESIGN_PASS != "" ]]; then
        openssl pkcs12 -in $CODESIGN_KEYFILE -nocerts -nodes -password env:CODESIGN_PASS -out /dev/shm/key.pem
        openssl rsa -in /dev/shm/key.pem -outform PVK -pvk-none -out /dev/shm/authenticode.pvk
        openssl pkcs12 -in $CODESIGN_KEYFILE -nokeys -nodes  -password env:CODESIGN_PASS -out /dev/shm/cert.pem

        # if the user provides the certificateof the issuer, attach that one too
        if [[ $CODESIGN_EXTRACERT != "" ]]; then
            cat $CODESIGN_EXTRACERT >> /dev/shm/cert.pem
        fi

        openssl crl2pkcs7 -nocrl -certfile /dev/shm/cert.pem -outform DER -out /dev/shm/authenticode.spc

        for exefile in "$DISTPATH/*.exe"; do
            echo "Signing Windows binary $exefile"
            signcode \
                -spc /dev/shm/authenticode.spc \
                -v /dev/shm/authenticode.pvk \
                -a sha256 -$ commercial \
                -t http://timestamp.verisign.com/scripts/timstamp.dll \
                -tr 5 -tw 60 \
                "$exefile"
            mv "$exefile.bak" "$(dirname $exefile)/unsigned_$(basename $exefile)"
        done
    fi
    if [[ -n "$DISTPATH" && -d "$DISTPATH" ]]; then
        chown -R --reference=. $DISTPATH
    fi
    DISTPATH=$ORIGINAL_DISTPATH
fi

# Run shell commands after building binaries
POST_SHELL_CMDS=${POST_SHELL_CMDS:-}
if [[ $PLATFORMS == *"linux"* || $PLATFORMS == *"win"* ]]; then	
    if [[ "$POST_SHELL_CMDS" != "" ]]; then
        /bin/bash -c "$POST_SHELL_CMDS"
    fi
fi

popd

if [[ $ret == 0 && $PLATFORMS == *"alpine"* ]]; then
    source /switch_to_alpine.sh $@
fi
