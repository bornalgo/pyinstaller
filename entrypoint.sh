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


check_option() {
    local option_name=$1
    local option_name_no_dash=${option_name#-}  # Remove any leading dashes
    local default_value=$2
    local combine_with_default=${3:-true}

    # Skip environment variable check for short options (e.g., -p)
    if [[ ${#option_name_no_dash} -gt 2 ]]; then
        local env_var=${option_name_no_dash^^} # Convert option_name to uppercase for env variable name
        env_var=${env_var//-/_}  # Replace dashes with underscores

        # Check if the environment variable is set
        if [[ -n "${!env_var}" ]]; then
            echo "$option_name ${!env_var}"
            return
        fi
    fi

    local output=""

    # Check if the option exists in the argument list and has a value
    for (( i = 0; i < $#; i++ )); do
        if [[ "${args[i]}" == "$option_name" ]]; then
            if [[ "$combine_with_default" == "false" ]]; then
                return
            fi
            
        fi
    done

    # Split the default value using whitespace as the delimiter
    local IFS=' '
    local default_values=($default_value)

    # Build the output with multiple default values
    local output=""
    for val in "${default_values[@]}"; do
        output+="$option_name $val "
    done
    echo "$output"
}



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

# Handy if you need to install libraries before running pyinstaller
SHELL_CMDS=${SHELL_CMDS:-}
if [[ "$SHELL_CMDS" != "" ]]; then
    /bin/bash -c "$SHELL_CMDS"
fi

if [ -f requirements.txt ]; then
    if [[ $PLATFORMS == *"linux"* ]]; then
        pip install -r requirements.txt
    fi
    if [[ $PLATFORMS == *"win"* ]]; then
        /usr/win64/bin/pip install -r requirements.txt
    fi
fi

echo "$@"

# Check if ENABLE_DEFAULT_OPTIONS is set
if [[ -n "${ENABLE_DEFAULT_OPTIONS}" ]]; then
    DEFAULT_OPTIONS="--log-level=DEBUG --clean --noupx --noconfirm"
else
    DEFAULT_OPTIONS=""
fi
# Use the check_option function to get values for options
WORKPATH_OPTION=$(check_option "--workpath" "/tmp" "false")
ADD_BINARY_OPTION=$(check_option "add-binary" "'/usr/local/lib/libcrypt.so.2:.'")
ADDITIONAL_HOOKS_OPTION=$(check_option "--additional-hooks-dir" "/hooks")
HIDDEN_IMPORT_OPTION=$(check_option "--hidden-import" "pkg_resources.py2_warn")
P_OPTION=$(check_option "-p" "." "false")

ret=0
if [[ $PLATFORMS == *"linux"* ]]; then
    DIST_PATH_OPTION=$(check_option "--distpath" "dist/linux")
    HIDDEN_IMPORT_OPTION=$(check_option "--hidden-import" "pkg_resources.py2_warn")

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
fi

if [[ $PLATFORMS == *"win"* && $ret == 0 ]]; then
    DIST_PATH_OPTION=$(check_option "--distpath" "dist/windows")
    HIDDEN_IMPORT_OPTION=$(check_option "--hidden-import" "win32timezone pkg_resources.py2_warn")

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

        for exefile in dist/windows/*.exe; do
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
fi

chown -R --reference=. dist
chown -R --reference=. *.spec
popd

if [[ $ret == 0 && $PLATFORMS == *"alpine"* ]]; then
    /switch_to_alpine.sh $@
fi
