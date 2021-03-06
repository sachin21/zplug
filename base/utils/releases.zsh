__zplug::utils::releases::get_latest()
{
    local repo="$1"
    local cmd url

    if (( $# < 1 )); then
        __zplug::io::log::error \
            "too few arguments"
        return 1
    fi

    url="https://github.com/$repo/releases/latest"
    if (( $+commands[curl] )); then
        cmd="curl -fsSL"
    elif (( $+commands[wget] )); then
        cmd="wget -qO -"
    fi

    eval "$cmd $url" \
        2> >(__zplug::io::log::capture) \
        | grep -o '/'"$repo"'/releases/download/[^"]*' \
        | awk -F/ '{print $6}' \
        | sort \
        | uniq
}

__zplug::utils::releases::get_state()
{
    local state name="$1" dir="$2"
    local url="https://github.com/$name/releases"

    if (( $# < 2 )); then
        __zplug::io::log::error \
            "too few arguments"
        return 1
    fi

    if [[ "$(__zplug::utils::releases::get_latest "$name")" == "$(cat "$dir/INDEX")" ]]; then
        state="up to date"
    else
        state="local out of date"
    fi

    case "$state" in
        "local out of date")
            state="${fg[red]}${state}${reset_color}"
            ;;
        "up to date")
            state="${fg[green]}${state}${reset_color}"
            ;;
    esac
    __zplug::io::print::put "($state) '${url:-?}'\n"
}

__zplug::utils::releases::is_64()
{
    uname -m | grep -q "64$"
}

__zplug::utils::releases::is_arm()
{
    uname -m | grep -q "^arm"
}

__zplug::utils::releases::get_url()
{
    local    repo="$1" result
    local -A tags
    local    cmd url
    local    arch
    local -a candidates

    if (( $# < 1 )); then
        __zplug::io::log::error \
            "too few arguments"
        return 1
    fi

    {
        tags[use]="$(
        __zplug::core::core::run_interfaces \
            'use' \
            "$repo"
        )"
        tags[at]="$(
        __zplug::core::core::run_interfaces \
            'at' \
            "$repo"
        )"

        #if [[ $tags[use] == '*.zsh' ]]; then
        #    tags[use]=
        #fi
        #if [[ $tags[at] == "master" ]]; then
        #    tags[at]="latest"
        #fi

        #if [[ -n $tags[at] && $tags[at != "latest" ]]; then
        #    tags[at]="tag/$tags[at"
        #else
        #    tags[at]="latest"
        #fi

        #if [[ -n $tags[use] ]]; then
        #    tags[use]="$(__zplug::utils::shell::glob2regexp "$tags[use")"
        #else
        #    tags[use]="$(__zplug::base::base::get_os)"
        #    if __zplug::base::base::is_osx; then
        #        tags[use]="(darwin|osx)"
        #    fi
        #fi
    }

    # Get machine information
    if __zplug::utils::releases::is_64; then
        arch="64"
    elif __zplug::utils::releases::is_arm; then
        arch="arm"
    else
        arch="386"
    fi

    url="https://github.com/$repo/releases/$tags[at]"
    if (( $+commands[curl] )); then
        cmd="curl -fsSL"
    elif (( $+commands[wget] )); then
        cmd="wget -qO -"
    fi

    candidates=(
    ${(@f)"$(
    eval "$cmd $url" \
        2> >(__zplug::io::log::capture) \
        | grep -o '/'"$repo"'/releases/download/[^"]*'
    )"}
    )
    if (( $#candidates == 0 )); then
        __zplug::io::print::f \
            --die \
            --zplug \
            "$repo: there are no available releases\n"
        return 1
    fi

    candidates=( $( echo "${(F)candidates[@]}" | grep -E "${tags[use]:-}" ) )
    if (( $#candidates > 1 )); then
        candidates=( $( echo "${(F)candidates[@]}" | grep "$arch" ) )
    fi
    result="${candidates[1]}"

    if [[ -z $result ]]; then
        __zplug::io::print::f \
            --die \
            --zplug \
            "$repo: repository not found\n"
        return 1
    fi

    echo "https://github.com$result"
}

__zplug::utils::releases::get()
{
    local    url="$1"
    local    repo dir header artifact cmd
    local -A tags

    if (( $# < 1 )); then
        __zplug::io::log::error \
            "too few arguments"
        return 1
    fi

    # make 'username/reponame' style
    repo="${url:s-https://github.com/--:F[4]h}"

    tags[dir]="$(
    __zplug::core::core::run_interfaces \
        'dir' \
        "$repo"
    )"
    header="${url:h:t}"
    artifact="${url:t}"

    if (( $+commands[curl] )); then
        cmd="curl -s -L -O"
    elif (( $+commands[wget] )); then
        cmd="wget"
    fi

    (
    __zplug::utils::shell::cd \
        --force \
        "$tags[dir]"

    # Grab artifact from G-R
    eval "$cmd $url" \
        2> >(__zplug::io::log::capture) >/dev/null

    __zplug::utils::releases::index \
        "$repo" \
        "$artifact" \
        2> >(__zplug::io::log::capture) >/dev/null &&
        echo "$header" >"$tags[dir]/INDEX"
    )

    return $status
}

__zplug::utils::releases::index()
{
    local    repo="$1" artifact="$2"
    local    cmd="${repo:t}"
    local -a binaries

    case "$artifact" in
        *.zip)
            {
                unzip "$artifact"
                rm -f "$artifact"
            } 2> >(__zplug::io::log::capture) >/dev/null
            ;;
        *.tar.gz|*.tgz)
            {
                tar xvf "$artifact"
                rm -f "$artifact"
            } 2> >(__zplug::io::log::capture) >/dev/null
            ;;
        *.*)
            __zplug::io::log::error \
                "$artifact: Unknown extension format"
            return 1
            ;;
        *)
            # Through
            ;;
    esac

    binaries=(
    $(
    file **/*(N-.) \
        | awk -F: '$2 ~ /executable/{print $1}'
    )
    )

    if (( $#binaries == 0 )); then
        __zplug::io::log::error \
            "$cmd: Failed to grab binaries from GitHub Releases"
        return 1
    fi

    {
        mv -f "$binaries[1]" "$cmd"
        chmod 755 "$cmd"
        rm -rf *~"$cmd"(N)
    } 2> >(__zplug::io::log::capture) >/dev/null

    if [[ ! -x $cmd ]]; then
        __zplug::io::print::die \
            "$repo: Failed to install\n"
        return 1
    fi

    __zplug::io::print::put \
        "$repo: Installed successfully\n"

    return 0
}
