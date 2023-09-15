#-> use: ["pust", "@bodhi.lib.yq"]
function chamber
    # def vars
    set raw_conf host server_port up_mbps down_mbps obfs
    # fetch data from upstream for the first time
    if test "$bodhi_verbose" = debug
        logger 3 "@bodhi.chamber CONT -> Fetching INIT Data"
    end
    if set raw_conf (curl -sL "$upstream_api/api/v1/server/UniProxy/config?node_id=$nodeid&node_type=hysteria&token=$psk")
        set raw_conf_md5 (echo -n "$raw_conf" | md5sum | string split ' ')[1]
    else
        logger 5 "@bodhi.chamber HALT -> Can't fetch init conf, abort"
        exit 1
    end
    if curl -sL "$upstream_api/api/v1/server/UniProxy/user?node_id=$nodeid&node_type=hysteria&token=$psk" -o userlist
    else
        logger 5 "@bodhi.chamber HALT -> Can't fetch init userlist, abort"
        exit 1
    end
    if test "$bodhi_verbose" = debug
    else
        logger 3 "@bodhi.chamber CONT -> Fetched data $raw_conf"
    end
    # generating conf
    set host (echo "$raw_conf" | yq .host)
    set server_port (echo "$raw_conf" | yq .server_port)
    set up_mbps (echo "$raw_conf" | yq .up_mbps)
    set down_mbps (echo "$raw_conf" | yq .down_mbps)
    set obfs (echo "$raw_conf" | yq .obfs)
    set push_interval (echo "$raw_conf" | yq .base_config.push_interval)
    # detect hysteria ver
    if echo "$hysteria_ver" | string match -q v2
        set -x hysteria2 true
    else
        set -x hysteria2 false
    end
    if $hysteria2
        if test "$obfs" = true
            echo "listen: $server_port
obfs:
  type: salamander
  salamander:
    password: $obfs
tls:
  cert: $tls_cert
  key: $tls_key
auth:
  type: command
  command: ./knck
trafficStats:
  listen: 127.0.0.1:$api_port
outbounds:
  - name: defob
    type: direct
    direct:
      mode: 64" >server.yaml
        else
            echo "listen: $server_port
tls:
  cert: $tls_cert
  key: $tls_key
auth:
  type: command
  command: ./knck
trafficStats:
  listen: 127.0.0.1:$api_port
outbounds:
  - name: defob
    type: direct
    direct:
      mode: 64" >server.yaml
        end
    else
        if test "$obfs" = true
            echo "{
    \"listen\": \":$server_port\",
    \"obfs\": \"$obfs\",
    \"cert\": \"$tls_cert\",
    \"prometheus_listen\": \"127.0.0.1:$api_port\",
    \"resolve_preference\": \"64\",
    \"key\": \"$tls_key\" ,
    \"auth\": {
        \"mode\": \"external\",
        \"config\": {
            \"cmd\": \"./knck\"
        }
    }
}" >server.json
        else
            echo "{
    \"listen\": \":$server_port\",
    \"cert\": \"$tls_cert\",
    \"prometheus_listen\": \"127.0.0.1:$api_port\",
    \"resolve_preference\": \"64\",
    \"key\": \"$tls_key\" ,
    \"auth\": {
        \"mode\": \"external\",
        \"config\": {
            \"cmd\": \"./knck\"
        }
    }
}" >server.json
        end
    end
    echo '#!/usr/bin/fish
if ./bin/yq \'.users[].uuid\' userlist | string match -q "$argv[2]"
else
    exit 1
end' >knck
    chmod +x knck
    # Launch core
    if $hysteria2
        $core_path -c ./server.yaml server &
    else
        $core_path -c ./server.json server &
    end
    set last_core_pid $last_pid
    if test "$bodhi_verbose" = debug
        logger 3 "@bodhi.chamber CONT -> Core Launched"
    end
    trap handle_stop SIGTSTP
    trap handle_stop SIGTERM
    trap handle_stop SIGINT
    push $push_interval $last_core_pid $raw_conf_md5
end
