#!/system/bin/sh
# Custom settings

# Take the current time
current_time=$(date +"%I:%M %P")

# Set Magisk Tailscale module variables
module_dir="/data/adb/modules/magisk-tailscaled" # Bad code, if magisk in the future change the path location, need to change this.
module_prop="${module_dir}/module.prop";

# Set tailscale directory variables
tailscale_dir="/data/adb/tailscale";
setting_file="${tailscale_dir}/settings.sh";

# Set path environment for busybox & other.
export PATH="/data/adb/magisk:/data/adb/ksu/bin:$PATH:/system/bin:${module_dir}/system/bin:${tailscale_dir}/bin"
export HOME="/data/adb/tailscale/tmp/" # Because tailscaled will write log to $HOME

# If setuidgid is unknown, use tailscale_user_group="0:3001" instead.
tailscale_user_group="root:net_bt_admin"
# tailscale_user=$(stat -c %U /proc/$PID)
# tailscale_group=$(stat -c %G /proc/$PID)

# Set tailscaled & tailscale configuration
tailscaled_bin="${tailscale_dir}/bin/tailscaled";
tailscaled_verbose="0";
tailscaled_tun_mode="tailscale0";
tailscaled_socket="${tailscale_dir}/tmp/tailscaled.sock";
tailscaled_state="${tailscale_dir}/tmp/tailscaled.state";
tailscaled_statedir="${tailscale_dir}/tmp/";
tailscaled_proxy="localhost:1099";
tailscaled_socks="localhost:1099";
tailscaled_port="41641";
tailscaled_bin_param="-verbose=${tailscaled_verbose} -outbound-http-proxy-listen=${tailscaled_proxy} -socks5-server=${tailscaled_socks} -tun=${tailscaled_tun_mode} -statedir=${tailscaled_statedir} -state=${tailscaled_state} -socket=${tailscaled_socket} -port=${tailscaled_port}";
tailscale_bin="${tailscale_dir}/bin/tailscale";
tailscale_bin_param="--socket=${tailscaled_socket}";

# Set tailscaled directory variables
tailscaled_run_dir="${tailscale_dir}/run";
tailscaled_scripts_dir="${tailscale_dir}/scripts";

# Set tailscaled log variables
# tailscaled_log="${tailscaled_run_dir}/tailscaled.log"
tailscaled_log="/dev/null" # daemon log cannot be accessed
tailscaled_runs_log="${tailscaled_run_dir}/runs.log"

# prepare iptables 
va1=$(getprop ro.build.version.release)
va2="11"
if [ "$va1" -ge "$va2" ]; then
  IPV="iptables -w 30"
  IP6V="ip6tables -w 30"
else
  IPV="iptables"
  IP6V="ip6tables"
fi

# ===================================================================================
# Hevsocks
# ===================================================================================

hevsocks_autostart=false;
hevsocks_bin="${tailscale_dir}/bin/hevsocks"
hevsocks_conf="${tailscale_dir}/tmp/hevsocks.yaml"
hevsocks_log="${tailscaled_run_dir}/$(basename ${hevsocks_bin}.log)"
hevsocks_ifname="hevsocks0"
# This mode will route all tcp packet use socks5 server tailscale, may unefficient for performance
hevsocks_up(){
  $IPV -t mangle -N HEVSOCKS 2>/dev/null
  $IPV -t mangle -F HEVSOCKS
  $IPV -t mangle -I OUTPUT -j HEVSOCKS
  $IPV -t mangle -I HEVSOCKS -m owner --uid-owner 0 --gid-owner 3001 -j RETURN
  $IPV -t mangle -A HEVSOCKS -p udp --dport 53 -j RETURN
  $IPV -t mangle -A HEVSOCKS -p tcp -j MARK --set-mark 1337
  ip route add default dev ${hevsocks_ifname} table 21 metric 1
  ip rule add fwmark 1337 lookup 21 pref 10
}
hevsocks_down(){
  ip rule del fwmark 1337
  ip route del default dev ${hevsocks_ifname} table 21 metric 1
  $IPV -t mangle -D OUTPUT -j HEVSOCKS
  $IPV -t mangle -F HEVSOCKS
  $IPV -t mangle -X HEVSOCKS
}

# ===================================================================================
# Coredns
# ===================================================================================
coredns_autostart=false;
coredns_conf="${tailscale_dir}/tmp/Corefile";
coredns_bin="${tailscale_dir}/bin/coredns";
coredns_port="1953";
coredns_log="${tailscaled_run_dir}/$(basename ${coredns_bin}.log)"
coredns_pid="${tailscaled_run_dir}/$(basename ${coredns_bin}.pid)"

coredns_post_up(){
  $IPV -t nat -N DNS_LOCAL
  $IPV -t nat -F DNS_LOCAL
  $IPV -t nat -I DNS_LOCAL -m owner --uid-owner 0 --gid-owner 3001 -j RETURN
  $IPV -t nat -A DNS_LOCAL -p udp --dport 53 ! -s 100.64.0.0/10 ! -d 100.100.100.100 -j DNAT --to-destination 127.0.0.1:1953
  $IPV -t nat -I OUTPUT -j DNS_LOCAL
}
coredns_pre_down(){
  $IPV -t nat -D OUTPUT -j DNS_LOCAL
  $IPV -t nat -F DNS_LOCAL
  $IPV -t nat -X DNS_LOCAL
}

# ===================================================================================

# Set tailscaled services variables
tailscaled_service="${tailscaled_scripts_dir}/tailscaled.service"
tailscaled_inotify="${tailscaled_scripts_dir}/tailscaled.inotify"

# Coloring
normal="\033[0m"
orange="\033[1;38;5;208m"
red="\033[1;31m"
green="\033[1;32m"
yellow="\033[1;33m"
blue="\033[1;34m"

# Logs function
log() {
  # Selects the text color according to the parameters
  case $1 in
    Info) color="${blue}" ;;
    Error) color="${red}" ;;
    Warning) color="${yellow}" ;;
    *) color= ;;
  esac
  # Add messages to time and parameters
  message="${current_time} [$1]: $2"
  if [ -z "$color" ]; then
    echo "${current_time} [Debug]: $1 $2" >> ${tailscaled_runs_log} 2>&1
    return;
  fi
  if [ -t 1 ]; then
    # Prints messages to the console
    echo -e "${color}${message}${normal}"
    echo "${message}" >> ${tailscaled_runs_log} 2>&1
  else
    # Print messages to a log file
    echo "${message}" >> ${tailscaled_runs_log} 2>&1
  fi
}

# This script is inspired from https://github.com/taamarin/box_for_magisk
# Thankyou for providing an amazing module.
