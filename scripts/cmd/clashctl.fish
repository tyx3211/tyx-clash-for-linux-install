set fn_arr \
clashui \
clashstatus \
clashsecret \
clashmixin \
clashsub \
clashlog \
clashupgrade \
clashhelp

for fn in $fn_arr
    eval "
    function $fn
        bash -i -c '$fn \"\$@\"' -- \$argv
    end
    "
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
        case '*'
            clash"$suffix" $argv
    end
end

function clashon
    bash -i -c 'clashon'
end

function clashoff
    bash -i -c 'clashoff'

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

function clashproxy
    switch $argv[1]
        case on
            set -l proxy_env (bash -i -c 'clashproxy on >/dev/null; env' 2>/dev/null | grep -i -E '^(http|https|all|no)_proxy=')
            for line in $proxy_env
                set -l kv (string split -m1 '=' $line)
                set -gx $kv[1] $kv[2]
            end
            echo "😼 已开启系统代理"
        case off
            bash -i -c 'clashproxy off >/dev/null' >/dev/null 2>&1
            set -e \
            http_proxy \
            https_proxy \
            HTTP_PROXY \
            HTTPS_PROXY \
            all_proxy \
            ALL_PROXY \
            no_proxy \
            NO_PROXY
            echo "😼 已关闭系统代理"
        case '' status
            set -l proxy_env (env | grep -i -E '^(http|https|all|no)_proxy=')
            if test -n "$proxy_env"
                echo "😼 系统代理：开启"
                printf '%s\n' $proxy_env
            else
                echo "😾 系统代理：关闭"
            end
        case mode
            if test (count $argv) -gt 1
                bash -i -c 'clashproxy mode "$1"' -- "$argv[2]"
            else
                bash -i -c 'clashproxy mode'
            end
        case '*'
            bash -i -c 'clashproxy "$@"' -- $argv
    end
end
