#!/usr/bin/env bash

# Read literal iOS settings without executing .env.local as shell code.
# Explicit environment variables take precedence, including empty values.
ios_load_local_env() {
    local file="${IOS_LOCAL_ENV_FILE:-$IOS_ROOT_DIR/.env.local}"
    local line key value
    [[ -f "$file" ]] || return 0
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line#"${line%%[![:space:]]*}"}"
        [[ -n "$line" && "$line" != \#* && "$line" == *=* ]] || continue
        key="${line%%=*}"
        key="${key%"${key##*[![:space:]]}"}"
        [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
        case "$key" in APPLE_TEAM_ID|IOS_*|ASC_*) ;; *) continue ;; esac
        value="${line#*=}"
        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"
        if [[ ${#value} -ge 2 ]] && {
            [[ "${value:0:1}" == '"' && "${value: -1}" == '"' ]] ||
            [[ "${value:0:1}" == "'" && "${value: -1}" == "'" ]];
        }; then
            value="${value:1:${#value}-2}"
        fi
        if [[ -z "${!key+x}" ]]; then
            printf -v "$key" '%s' "$value"
            export "$key"
        fi
    done < "$file"
}

ios_load_local_env
