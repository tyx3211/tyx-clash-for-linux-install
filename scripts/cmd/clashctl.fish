if not set -q CLASHCTL_CMD_DIR
    set -gx CLASHCTL_CMD_DIR "$HOME/clashctl/scripts/cmd"
end

function _clashctl_bash_call
    set -l fn $argv[1]
    set -e argv[1]
    switch $fn
        case clashui clashstatus clashsecret clashmixin clashsub clashtun clashlog clashupgrade clashhelp clashctl clashon clashoff clashrestart clashproxy
        case '*'
            echo "unknown clashctl fish wrapper function: $fn" >&2
            return 1
    end

    bash -c '
        cmd_dir=$1
        fn=$2
        shift 2
        case "$fn" in
        clashui|clashstatus|clashsecret|clashmixin|clashsub|clashtun|clashlog|clashupgrade|clashhelp|clashctl|clashon|clashoff|clashrestart|clashproxy)
            ;;
        *)
            exit 64
            ;;
        esac
        . "$cmd_dir/clashctl.sh" || exit $?
        "$fn" "$@"
    ' -- "$CLASHCTL_CMD_DIR" "$fn" $argv
end

function clashui
    _clashctl_bash_call clashui $argv
end

function clashstatus
    _clashctl_bash_call clashstatus $argv
end

function clashsecret
    _clashctl_bash_call clashsecret $argv
end

function clashmixin
    _clashctl_bash_call clashmixin $argv
end

function clashsub
    _clashctl_bash_call clashsub $argv
end

function clashtun
    _clashctl_bash_call clashtun $argv
end

function clashlog
    _clashctl_bash_call clashlog $argv
end

function clashupgrade
    _clashctl_bash_call clashupgrade $argv
end

function clashhelp
    _clashctl_bash_call clashhelp $argv
end

function clashctl
    if test (count $argv) -eq 0
        clashhelp
        return
    end


    set suffix $argv[1]
    set argv $argv[2..-1]

    switch $suffix
        case on
            clashon $argv
        case off
            clashoff $argv
        case restart
            clashrestart $argv
        case update-self
            _clashctl_bash_call clashctl update-self $argv
        case '*'
            set -l fn clash"$suffix"
            if functions -q $fn
                $fn $argv
            else
                clashhelp
                return 1
            end
    end
end

function clashon
    _clashctl_bash_call clashon $argv
end

function clashoff
    _clashctl_bash_call clashoff $argv
    set -l bash_status $status

    if test $bash_status -eq 0
        set -e \
        http_proxy \
        https_proxy \
        HTTP_PROXY \
        HTTPS_PROXY \
        all_proxy \
        ALL_PROXY \
        no_proxy \
        NO_PROXY
    end

    return $bash_status
end

function clashrestart
    _clashctl_bash_call clashrestart $argv
end

function clashproxy
    set -l global false
    set -l action ""
    for arg in $argv
        if test "$arg" = "-g" -o "$arg" = "--global"
            set global true
            continue
        end
        if test -z "$action"
            set action $arg
        end
    end

    switch $action
        case on
            set -l env_tmp (mktemp)
            bash -c '
                cmd_dir=$1
                shift
                . "$cmd_dir/clashctl.sh" || exit $?
                clashproxy "$@" >/dev/null && env
            ' -- "$CLASHCTL_CMD_DIR" $argv >$env_tmp 2>/dev/null
            set -l bash_status $status
            if test $bash_status -ne 0
                rm -f $env_tmp
                return $bash_status
            end
            set -l proxy_env (grep -i -E '^(http|https|all|no)_proxy=' $env_tmp)
            rm -f $env_tmp
            for line in $proxy_env
                set -l kv (string split -m1 '=' $line)
                set -gx $kv[1] $kv[2]
            end
            if test "$global" = true
                echo "😼 已为当前终端开启代理，并开启全局自动代理"
            else
                echo "😼 已为当前终端开启代理"
            end
        case off
            bash -c '
                cmd_dir=$1
                shift
                . "$cmd_dir/clashctl.sh" || exit $?
                clashproxy "$@" >/dev/null
            ' -- "$CLASHCTL_CMD_DIR" $argv >/dev/null 2>&1
            set -l bash_status $status
            if test $bash_status -ne 0
                return $bash_status
            end
            set -e \
            http_proxy \
            https_proxy \
            HTTP_PROXY \
            HTTPS_PROXY \
            all_proxy \
            ALL_PROXY \
            no_proxy \
            NO_PROXY
            if test "$global" = true
                echo "😼 已为当前终端关闭代理，并关闭全局自动代理"
            else
                echo "😼 已为当前终端关闭代理"
            end
        case '' status
            if test "$global" = true
                _clashctl_bash_call clashproxy $argv
            else
                set -l proxy_env (env | grep -i -E '^(http|https|all|no)_proxy=')
                if test -n "$proxy_env"
                    echo "😼 当前终端代理：开启"
                    printf '%s\n' $proxy_env
                else
                    echo "😾 当前终端代理：关闭"
                end
            end
        case mode
            _clashctl_bash_call clashproxy $argv
        case '*'
            _clashctl_bash_call clashproxy $argv
    end
end
