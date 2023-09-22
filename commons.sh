check_for_spec_file() {
    for arg in "$@"; do
        if [ -f "$arg" ] && [ "${arg##*.}" = "spec" ]; then
            return 0  # Found a .spec file, return success (0).
        fi
    done
    return 1  # No .spec file found, return failure (1).
}

check_option() {
    local option_env=$1
    local option_name=$2
    local option_name_no_dash=${option_name##*-}  # Remove any leading dashes
    local default_value=$3
    local combine_with_default=$4
    local ignore_with_spec=$5
    local args=("${@:6}")

    if [ "$ignore_with_spec" == "yes" ] && [ "$HAS_SPEC_FILE" == "yes" ]; then
        return
    fi

    local env_var=""

    # Skip environment variable check for short options (e.g., -p)
    if [[ ${#option_name_no_dash} -gt 2 ]]; then
        env_var=${option_name_no_dash^^}  # Convert option_name to uppercase for env variable name
        env_var=${env_var//-/_}  # Replace dashes with underscores

        # Check if the environment variable is set
        if [[ -n "${!env_var}" ]]; then
            # Update the specified environment variable with the value of the environment variable
            eval "$option_env=\"$option_name ${!env_var}\""
            return
        fi
    fi

    # Check if the option exists in the argument list and has a value
    for ((i = 0; i < ${#args[@]}; i++)); do
        if [[ "${args[i]}" == "$option_name" ]]; then
            if [[ "$combine_with_default" == "no" ]]; then
                if [[ -n "$env_var" && $((i + 1)) -lt ${#args[@]} ]]; then
                    # Update the specified environment variable with the value from the argument list
                    eval "$env_var=\"${args[i + 1]}\""
                fi
                return
            fi
        fi
    done

    if [ -n "$default_value" ]; then
        # Split the default value using whitespace as the delimiter
        local default_values=($default_value)

        # Build the output with multiple default values
        local output=""
        for val in "${default_values[@]}"; do
            if [[ -n "$env_var" && -z "${!env_var}" ]]; then
                # Update the specified environment variable with the default value
                eval "$env_var=\"$val\""
            fi
            if [ -n "$output" ]; then
                output+=" $option_name $val"
            else
                output+="$option_name $val"
            fi
        done
        eval "$option_env=\"$output\""
    else
        eval "$option_env=\"$option_name\""
    fi
}
