function _clashctl_bash_call
    set -l fn $argv[1]
    set -e argv[1]
    bash -i -c "$fn \"\$@\"" -- $argv
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
    if test -z "$argv"
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
            bash -i -c 'clashctl update-self "$@"' -- $argv
        case '*'
            clash"$suffix" $argv
    end
end

function clashon
    bash -i -c 'clashon "$@"' -- $argv
end

function clashoff
    bash -i -c 'clashoff "$@"' -- $argv

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

function clashrestart
    bash -i -c 'clashrestart "$@"' -- $argv
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
            set -l proxy_env (bash -i -c 'clashproxy "$@" >/dev/null; env' -- $argv 2>/dev/null | grep -i -E '^(http|https|all|no)_proxy=')
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
            bash -i -c 'clashproxy "$@" >/dev/null' -- $argv >/dev/null 2>&1
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
                bash -i -c 'clashproxy "$@"' -- $argv
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
            bash -i -c 'clashproxy "$@"' -- $argv
        case '*'
            bash -i -c 'clashproxy "$@"' -- $argv
    end
end
