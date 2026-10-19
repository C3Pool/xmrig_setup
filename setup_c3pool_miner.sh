#!/bin/bash

VERSION=2.12

# printing greetings

echo "C3Pool mining setup script v$VERSION."
echo "警告: 请勿将此脚本使用在非法用途,如有发现在非自己所有权的服务器内使用该脚本"
echo "我们将在接到举报后,封禁违法的钱包地址,并将有关信息收集并提交给警方"
echo "(please report issues to support@c3pool.com email with full output of this script with extra \"-x\" \"bash\" option)"
echo

if [ "$(id -u)" == "0" ]; then
  echo "WARNING: Generally it is not adviced to run this script under root"
  echo "警告: 不建议在root用户下使用此脚本"
fi

# command line arguments
WALLET=$1
EMAIL=$2 # this one is optional

# checking prerequisites

if [ -z $WALLET ]; then
  echo "Script usage:"
  echo "> setup_c3pool_miner.sh <wallet address> [<your email address>]"
  echo "ERROR: Please specify your wallet address"
  exit 1
fi

# address formats accepted by the pool (same rules as pool lib/addressDetection.js;
# checksums are verified by the pool at login)
WALLET_BASE=`echo $WALLET | cut -f1 -d"."`
B58='[123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz]'
if [[ "$WALLET_BASE" =~ ^[48]$B58{94}$ || "$WALLET_BASE" =~ ^[48]$B58{105}$ ]]; then
  WALLET_TYPE="XMR"
elif [[ "$WALLET_BASE" =~ ^T$B58{33}$ ]]; then
  WALLET_TYPE="USDT (TRON)"
elif [[ "$WALLET_BASE" =~ ^0x[0123456789abcdefABCDEF]{40}$ ]]; then
  WALLET_TYPE="USDT (BSC/Polygon)"
elif [[ "$WALLET_BASE" =~ ^$B58{32,44}$ ]]; then
  WALLET_TYPE="USDT (Solana)"
else
  echo "ERROR: Wrong wallet address: $WALLET_BASE"
  echo "Supported addresses: XMR (95 or 106 chars), USDT-TRON (T...), USDT-BSC/Polygon (0x...), USDT-Solana"
  echo "发生错误: 钱包地址格式不正确: $WALLET_BASE"
  echo "支持的地址: XMR (95 或 106 位)、USDT-TRON (T 开头)、USDT-BSC/Polygon (0x 开头)、USDT-Solana"
  exit 1
fi
echo "Wallet address type: $WALLET_TYPE"
echo "钱包地址类型: $WALLET_TYPE"
if [ "$WALLET_TYPE" == "USDT (BSC/Polygon)" ]; then
  echo "NOTE: 0x addresses are identical on BSC and Polygon, please choose your USDT payout chain at https://c3pool.com site, otherwise payouts can't be made"
  echo "提示: 0x 地址在 BSC 和 Polygon 上相同，请到 https://c3pool.com 网站选择 USDT 结算链，否则无法付款"
fi
echo

if [ -z $HOME ]; then
  echo "ERROR: Please define HOME environment variable to your home directory"
  exit 1
fi

if [ ! -d $HOME ]; then
  echo "ERROR: Please make sure HOME directory $HOME exists or set it yourself using this command:"
  echo '  export HOME=<dir>'
  exit 1
fi

if ! type curl >/dev/null; then
  echo "ERROR: This script requires \"curl\" utility to work correctly"
  exit 1
fi

if ! type lscpu >/dev/null; then
  echo "WARNING: This script requires \"lscpu\" utility to work correctly"
fi

#if ! sudo -n true 2>/dev/null; then
#  if ! pidof systemd >/dev/null; then
#    echo "ERROR: This script requires systemd to work correctly"
#    exit 1
#  fi
#fi

# calculating port

CPU_THREADS=$(nproc)
EXP_MONERO_HASHRATE=$(( CPU_THREADS * 700 / 1000))
if [ -z $EXP_MONERO_HASHRATE ]; then
  echo "ERROR: Can't compute projected Monero CN hashrate"
  exit 1
fi

get_port_based_on_hashrate() {
  local hashrate=$1
  if [ "$hashrate" -le "5000" ]; then
    echo 80
  elif [ "$hashrate" -le "25000" ]; then
    if [ "$hashrate" -gt "5000" ]; then
      echo 13333
    else
      echo 443
    fi
  elif [ "$hashrate" -le "50000" ]; then
    if [ "$hashrate" -gt "25000" ]; then
      echo 15555
    else
      echo 14444
    fi
  elif [ "$hashrate" -le "100000" ]; then
    if [ "$hashrate" -gt "50000" ]; then
      echo 19999
    else
      echo 17777
    fi
  elif [ "$hashrate" -le "1000000" ]; then
    echo 23333
  else
    echo "ERROR: Hashrate too high"
    exit 1
  fi
}

PORT=$(get_port_based_on_hashrate $EXP_MONERO_HASHRATE)
if [ -z $PORT ]; then
  echo "ERROR: Can't compute port"
  exit 1
fi

echo "Computed port: $PORT"


# printing intentions

echo "I will download, setup and run in background Monero CPU miner."
echo "将进行下载设置,并在后台中运行xmrig矿工."
echo "If needed, miner in foreground can be started by $HOME/c3pool/miner.sh script."
echo "如果需要,可以通过以下方法启动前台矿工输出 $HOME/c3pool/miner.sh script."
echo "Mining will happen to $WALLET wallet."
echo "将使用 $WALLET 地址进行开采"
if [ ! -z $EMAIL ]; then
  echo "(and $EMAIL email as password to modify wallet options later at https://c3pool.com site)"
fi
echo

if ! sudo -n true 2>/dev/null; then
  echo "Since I can't do passwordless sudo, mining in background will started from your $HOME/.profile file first time you login this host after reboot."
  echo "由于脚本无法执行无密码的sudo，因此在您重启后首次登录此主机时，后台开采将从您的 $HOME/.profile 文件开始."
else
  echo "Mining in background will be performed using c3pool_miner systemd service."
  echo "后台开采将使用c3pool_miner systemd服务执行."
fi

echo
echo "JFYI: This host has $CPU_THREADS CPU threads, so projected Monero hashrate is around $EXP_MONERO_HASHRATE KH/s."
echo

echo "Sleeping for 15 seconds before continuing (press Ctrl+C to cancel)"
echo "等待 15 秒将继续运行安装 (按 Ctrl+C 取消)"
sleep 15
echo
echo

# start doing stuff: preparing miner

echo "[*] Removing previous c3pool miner (if any)"
echo "[*] 卸载以前的 C3Pool 矿工 (如果存在)"
if sudo -n true 2>/dev/null; then
  sudo systemctl stop c3pool_miner.service
fi
pkill -9 -f "^$HOME/c3pool/xmrig( |$)" 2>/dev/null

echo "[*] Removing $HOME/c3pool directory"
rm -rf $HOME/c3pool

# hosts outside China download the latest GitHub release first, China (or unknown country) download.c3pool.org first
# (it always holds the latest build); the other source is used as fallback if the first one fails
C3_XMRIG_URL="https://download.c3pool.org/xmrig_setup/raw/master/xmrig.tar.gz"
# used only when the GitHub API can't be queried (e.g. rate limit)
GITHUB_XMRIG_FALLBACK_URL="https://github.com/C3Pool/xmrig-C3/releases/download/v6.26.0-C7/xmrig-v6.26.0-C7-linux-Static.tar.gz"

get_latest_github_xmrig_url() {
  curl -s --max-time 10 https://api.github.com/repos/C3Pool/xmrig-C3/releases/latest | grep -o '"browser_download_url": *"[^"]*linux-Static.tar.gz"' | head -n1 | cut -d '"' -f4
}

COUNTRY=`curl -s --max-time 5 https://www.cloudflare.com/cdn-cgi/trace | grep '^loc=' | cut -d= -f2`
echo "[*] Host country: ${COUNTRY:-unknown}"
echo "[*] 主机所在国家/地区: ${COUNTRY:-未知}"
GITHUB_XMRIG_URL=
if [ -n "$COUNTRY" ] && [ "$COUNTRY" != "CN" ]; then
  GITHUB_XMRIG_URL=`get_latest_github_xmrig_url`
fi
if [ -n "$GITHUB_XMRIG_URL" ]; then
  XMRIG_SOURCES="github c3"
else
  XMRIG_SOURCES="c3 github"
fi

XMRIG_DOWNLOADED=
for XMRIG_SOURCE in $XMRIG_SOURCES; do
  if [ "$XMRIG_SOURCE" == "c3" ]; then
    XMRIG_URL=$C3_XMRIG_URL
  else
    [ -n "$GITHUB_XMRIG_URL" ] || GITHUB_XMRIG_URL=`get_latest_github_xmrig_url`
    XMRIG_URL=${GITHUB_XMRIG_URL:-$GITHUB_XMRIG_FALLBACK_URL}
  fi
  echo "[*] Downloading C3Pool advanced version of xmrig from $XMRIG_URL to /tmp/xmrig.tar.gz"
  echo "[*] 从 $XMRIG_URL 下载 C3Pool 版本的 Xmrig 到 /tmp/xmrig.tar.gz 中"
  if curl -fL --progress-bar "$XMRIG_URL" -o /tmp/xmrig.tar.gz; then
    XMRIG_DOWNLOADED=1
    break
  fi
  echo "WARNING: Can't download $XMRIG_URL file to /tmp/xmrig.tar.gz"
  echo "警告: 无法下载 $XMRIG_URL 文件到 /tmp/xmrig.tar.gz"
done
if [ -z "$XMRIG_DOWNLOADED" ]; then
  echo "ERROR: Can't download C3Pool advanced version of xmrig"
  echo "发生错误: 无法下载 C3Pool 版本的 Xmrig"
  exit 1
fi

echo "[*] Unpacking /tmp/xmrig.tar.gz to $HOME/c3pool"
echo "[*] 解压 /tmp/xmrig.tar.gz 到 $HOME/c3pool"
[ -d $HOME/c3pool ] || mkdir $HOME/c3pool
if ! tar xf /tmp/xmrig.tar.gz -C $HOME/c3pool; then
  echo "ERROR: Can't unpack /tmp/xmrig.tar.gz to $HOME/c3pool directory"
  echo "发生错误: 无法解压 /tmp/xmrig.tar.gz 到 $HOME/c3pool 目录"
  exit 1
fi
rm /tmp/xmrig.tar.gz

echo "[*] Checking if advanced version of $HOME/c3pool/xmrig works fine (and not removed by antivirus software)"
echo "[*] 检查目录 $HOME/c3pool/xmrig 中的xmrig是否运行正常 (或者是否被杀毒软件误杀)"
sed -i 's/"donate-level": *[^,]*,/"donate-level": 1,/' $HOME/c3pool/config.json
$HOME/c3pool/xmrig --help >/dev/null
if (test $? -ne 0); then
  if [ -f $HOME/c3pool/xmrig ]; then
    echo "WARNING: Advanced version of $HOME/c3pool/xmrig is not functional"
	echo "警告: 版本 $HOME/c3pool/xmrig 无法正常工作"
  else 
    echo "WARNING: Advanced version of $HOME/c3pool/xmrig was removed by antivirus (or some other problem)"
	echo "警告: 该目录 $HOME/c3pool/xmrig 下的xmrig已被杀毒软件删除 (或其它问题)"
  fi

  echo "[*] Looking for the latest version of Monero miner"
  echo "[*] 查看最新版本的 xmrig 挖矿工具"
  LATEST_XMRIG_LINUX_RELEASE=`curl -s https://api.github.com/repos/xmrig/xmrig/releases/latest | grep -o '"browser_download_url": *"[^"]*linux-static-x64.tar.gz"' | head -n1 | cut -d '"' -f4`
  if [ -z "$LATEST_XMRIG_LINUX_RELEASE" ]; then
    echo "ERROR: Can't find the latest xmrig release for Linux on GitHub"
    echo "发生错误: 无法在 GitHub 上找到最新的 Linux 版 xmrig"
    exit 1
  fi

  echo "[*] Downloading $LATEST_XMRIG_LINUX_RELEASE to /tmp/xmrig.tar.gz"
  echo "[*] 下载 $LATEST_XMRIG_LINUX_RELEASE 到 /tmp/xmrig.tar.gz"
  if ! curl -fL --progress-bar $LATEST_XMRIG_LINUX_RELEASE -o /tmp/xmrig.tar.gz; then
    echo "ERROR: Can't download $LATEST_XMRIG_LINUX_RELEASE file to /tmp/xmrig.tar.gz"
	echo "发生错误: 无法下载 $LATEST_XMRIG_LINUX_RELEASE 文件到 /tmp/xmrig.tar.gz"
    exit 1
  fi

  echo "[*] Unpacking /tmp/xmrig.tar.gz to $HOME/c3pool"
  echo "[*] 解压 /tmp/xmrig.tar.gz 到 $HOME/c3pool"
  if ! tar xf /tmp/xmrig.tar.gz -C $HOME/c3pool --strip=1; then
    echo "WARNING: Can't unpack /tmp/xmrig.tar.gz to $HOME/c3pool directory"
	echo "警告: 无法解压 /tmp/xmrig.tar.gz 到 $HOME/c3pool 目录下"
  fi
  rm /tmp/xmrig.tar.gz

  echo "[*] Checking if stock version of $HOME/c3pool/xmrig works fine (and not removed by antivirus software)"
  echo "[*] 检查目录 $HOME/c3pool/xmrig 中的xmrig是否运行正常 (或者是否被杀毒软件误杀)"
  sed -i 's/"donate-level": *[^,]*,/"donate-level": 0,/' $HOME/c3pool/config.json
  $HOME/c3pool/xmrig --help >/dev/null
  if (test $? -ne 0); then 
    if [ -f $HOME/c3pool/xmrig ]; then
      echo "ERROR: Stock version of $HOME/c3pool/xmrig is not functional too"
	  echo "发生错误: 该目录中的 $HOME/c3pool/xmrig 也无法使用"
    else 
      echo "ERROR: Stock version of $HOME/c3pool/xmrig was removed by antivirus too"
	  echo "发生错误: 该目录中的 $HOME/c3pool/xmrig 已被杀毒软件删除"
    fi
    exit 1
  fi
fi

echo "[*] Miner $HOME/c3pool/xmrig is OK"
echo "[*] 矿工 $HOME/c3pool/xmrig 运行正常"

PASS=`hostname | cut -f1 -d"." | sed -r 's/[^a-zA-Z0-9\-]+/_/g'`
if [ "$PASS" == "localhost" ]; then
  PASS=`ip route get 1 | awk '{for(i=1;i<NF;i++) if($i=="src"){print $(i+1);exit}}'`
fi
if [ -z $PASS ]; then
  PASS=na
fi
if [ ! -z $EMAIL ]; then
  PASS="$PASS:$EMAIL"
fi

sed -i 's/"url": *"[^"]*",/"url": "auto.c3pool.org:'$PORT'",/' $HOME/c3pool/config.json
sed -i 's/"user": *"[^"]*",/"user": "'$WALLET'",/' $HOME/c3pool/config.json
sed -i 's/"pass": *"[^"]*",/"pass": "'$PASS'",/' $HOME/c3pool/config.json
sed -i 's/"max-cpu-usage": *[^,]*,/"max-cpu-usage": 100,/' $HOME/c3pool/config.json
sed -i 's#"log-file": *null,#"log-file": "'$HOME/c3pool/xmrig.log'",#' $HOME/c3pool/config.json
sed -i 's/"syslog": *[^,]*,/"syslog": true,/' $HOME/c3pool/config.json

cp $HOME/c3pool/config.json $HOME/c3pool/config_background.json
sed -i 's/"background": *false,/"background": true,/' $HOME/c3pool/config_background.json

# preparing script

echo "[*] Creating $HOME/c3pool/miner.sh script"
echo "[*] 在该目录下创建 $HOME/c3pool/miner.sh 脚本"
cat >$HOME/c3pool/miner.sh <<EOL
#!/bin/bash
if ! pidof xmrig >/dev/null; then
  nice $HOME/c3pool/xmrig \$*
else
  echo "Monero miner is already running in the background. Refusing to run another one."
  echo "Run \"killall xmrig\" or \"sudo killall xmrig\" if you want to remove background miner first."
  echo "门罗币矿工已经在后台运行。 拒绝运行另一个."
  echo "如果要先删除后台矿工，请运行 \"killall xmrig\" 或 \"sudo killall xmrig\"."
fi
EOL

chmod +x $HOME/c3pool/miner.sh

# preparing script background work and work under reboot

if ! sudo -n true 2>/dev/null; then
  if ! grep c3pool/miner.sh $HOME/.profile >/dev/null; then
    echo "[*] Adding $HOME/c3pool/miner.sh script to $HOME/.profile"
	echo "[*] 添加 $HOME/c3pool/miner.sh 到 $HOME/.profile"
    echo "$HOME/c3pool/miner.sh --config=$HOME/c3pool/config_background.json >/dev/null 2>&1" >>$HOME/.profile
  else 
    echo "Looks like $HOME/c3pool/miner.sh script is already in the $HOME/.profile"
	echo "脚本 $HOME/c3pool/miner.sh 已存在于 $HOME/.profile 中."
  fi
  echo "[*] Running miner in the background (see logs in $HOME/c3pool/xmrig.log file)"
  echo "[*] 已在后台运行xmrig矿工 (请查看 $HOME/c3pool/xmrig.log 日志文件)"
  /bin/bash $HOME/c3pool/miner.sh --config=$HOME/c3pool/config_background.json >/dev/null 2>&1
else

  if [[ $(grep MemTotal /proc/meminfo | awk '{print $2}') -gt 3500000 ]]; then
    echo "[*] Enabling huge pages"
	echo "[*] 启用 huge pages"
    sudo sed -i '/^vm.nr_hugepages=/d' /etc/sysctl.conf
    echo "vm.nr_hugepages=$((1168+$(nproc)))" | sudo tee -a /etc/sysctl.conf
    sudo sysctl -w vm.nr_hugepages=$((1168+$(nproc)))
  fi

  if ! type systemctl >/dev/null; then

    echo "[*] Running miner in the background (see logs in $HOME/c3pool/xmrig.log file)"
	echo "[*] 已在后台运行xmrig矿工 (请查看 $HOME/c3pool/xmrig.log 日志文件)"
    /bin/bash $HOME/c3pool/miner.sh --config=$HOME/c3pool/config_background.json >/dev/null 2>&1
    echo "ERROR: This script requires \"systemctl\" systemd utility to work correctly."
    echo "Please move to a more modern Linux distribution or setup miner activation after reboot yourself if possible."

  else

    echo "[*] Creating c3pool_miner systemd service"
    cat >/tmp/c3pool_miner.service <<EOL
[Unit]
Description=Monero miner service

[Service]
ExecStart=$HOME/c3pool/xmrig --config=$HOME/c3pool/config.json
Restart=always
Nice=10
CPUWeight=1

[Install]
WantedBy=multi-user.target
EOL
    sudo mv /tmp/c3pool_miner.service /etc/systemd/system/c3pool_miner.service
    echo "[*] Starting c3pool_miner systemd service"
	echo "[*] 启动c3pool_miner systemd服务"
    sudo pkill -f "^$HOME/c3pool/xmrig( |$)" 2>/dev/null
    sudo systemctl daemon-reload
    sudo systemctl enable c3pool_miner.service
    sudo systemctl start c3pool_miner.service
    echo "To see miner service logs run \"sudo journalctl -u c3pool_miner -f\" command"
	echo "查看矿工服务日志,请运行 \"sudo journalctl -u c3pool_miner -f\" 命令"
  fi
fi

echo ""
echo "NOTE: If you are using shared VPS it is recommended to avoid 100% CPU usage produced by the miner or you will be banned"
echo "提示: 如果您使用共享VPS，建议避免由矿工产生100％的CPU使用率，否则可能将被禁止使用"
if [ "$CPU_THREADS" -lt "4" ]; then
  echo "HINT: Please execute these or similair commands under root to limit miner to 75% percent CPU usage:"
  echo "sudo apt-get update; sudo apt-get install -y cpulimit"
  echo "sudo cpulimit -e xmrig -l $((75*$CPU_THREADS)) -b"
  if [ "`tail -n1 /etc/rc.local`" != "exit 0" ]; then
    echo "sudo sed -i -e '\$acpulimit -e xmrig -l $((75*$CPU_THREADS)) -b\\n' /etc/rc.local"
  else
    echo "sudo sed -i -e '\$i \\cpulimit -e xmrig -l $((75*$CPU_THREADS)) -b\\n' /etc/rc.local"
  fi
else
  echo "HINT: Please execute these commands and reboot your VPS after that to limit miner to 75% percent CPU usage:"
  echo "sed -i 's/\"max-threads-hint\": *[^,]*,/\"max-threads-hint\": 75,/' \$HOME/c3pool/config.json"
  echo "sed -i 's/\"max-threads-hint\": *[^,]*,/\"max-threads-hint\": 75,/' \$HOME/c3pool/config_background.json"
fi
echo ""

echo "[*] Setup complete"
echo "[*] 安装完成"
echo "警告: 请勿将此脚本使用在非法用途,如有发现在非自己所有权的服务器内使用该脚本"
echo "我们将在接到举报后,封禁违法的钱包地址,并将有关信息收集并提交给警方"

