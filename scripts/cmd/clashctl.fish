set fn_arr \
clashui \
clashstatus \
clashsecret \
clashmixin \
clashsub \
clashlog \
clashupgrade \
clashhelp

set -gx fish_version $FISH_VERSION

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
            set -l proxy_env (bash -i -c 'clashproxy on >/dev/null; env | grep -i -E "^(http|https|all|no)_proxy="')
            for line in $proxy_env
                set -l kv (string split -m1 '=' $line)
                set -gx $kv[1] $kv[2]
            end
        case off
            bash -i -c 'clashproxy off'
            set -e \
            http_proxy \
            https_proxy \
            HTTP_PROXY \
            HTTPS_PROXY \
            all_proxy \
            ALL_PROXY \
            no_proxy \
            NO_PROXY
        case '*'
            bash -i -c 'clashproxy'
    end
end