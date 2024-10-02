#!/bin/bash

# 脚本保存路径
SCRIPT_PATH="$HOME/ZenRock.sh"

# 部署脚本函数
function deploy_script() {
    echo "正在执行部署脚本..."
    
    # 更新系统包列表和升级已安装的包
    sudo apt update -y && sudo apt upgrade -y

    # 安装所需的软件包
    sudo apt install -y ca-certificates zlib1g-dev libncurses5-dev libgdbm-dev \
    libnss3-dev tmux iptables curl nvme-cli git wget make jq libleveldb-dev \
    build-essential pkg-config ncdu tar clang bsdmainutils lsb-release \
    libssl-dev libreadline-dev libffi-dev jq gcc screen unzip lz4


    # 检查 Go 是否已安装
    if ! command -v go &> /dev/null; then
        echo "Go 未安装，正在安装 Go..."
        cd $HOME
        VER="1.23.1"
        wget "https://golang.org/dl/go$VER.linux-amd64.tar.gz"
        sudo rm -rf /usr/local/go
        sudo tar -C /usr/local -xzf "go$VER.linux-amd64.tar.gz"
        rm "go$VER.linux-amd64.tar.gz"

        # 更新环境变量
        [ ! -f ~/.bash_profile ] && touch ~/.bash_profile
        echo "export PATH=\$PATH:/usr/local/go/bin:~/go/bin" >> ~/.bash_profile
        source $HOME/.bash_profile

        [ ! -d ~/go/bin ] && mkdir -p ~/go/bin
        echo "Go 安装完成！"
    else
        echo "Go 已安装，版本: $(go version)"
    fi

  # 设置 Moniker
  read -p "请输入您的 Moniker 名称: " MONIKER

  # 下载二进制文件
  mkdir -p $HOME/.zrchain/cosmovisor/genesis/bin
  wget -O $HOME/.zrchain/cosmovisor/genesis/bin/zenrockd https://releases.gardia.zenrocklabs.io/zenrockd-4.7.1
  chmod +x $HOME/.zrchain/cosmovisor/genesis/bin/zenrockd

  # 创建符号链接
  sudo ln -s $HOME/.zrchain/cosmovisor/genesis $HOME/.zrchain/cosmovisor/current -f
  sudo ln -s $HOME/.zrchain/cosmovisor/current/bin/zenrockd /usr/local/bin/zenrockd -f

# 使用 Cosmovisor 管理节点
go install cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@v1.6.0

# 创建服务
sudo tee /etc/systemd/system/zenrock-testnet.service > /dev/null << EOF
[Unit]
Description=zenrock node service
After=network-online.target

[Service]
User=$USER
ExecStart=$(which cosmovisor) run start
Restart=on-failure
RestartSec=10
LimitNOFILE=65535
Environment="DAEMON_HOME=$HOME/.zrchain"
Environment="DAEMON_NAME=zenrockd"
Environment="UNSAFE_SKIP_BACKUP=true"
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin:$HOME/.zrchain/cosmovisor/current/bin"

[Install]
WantedBy=multi-user.target
EOF

# 重新加载服务并启用
sudo systemctl daemon-reload
sudo systemctl enable zenrock-testnet.service

# 配置节点
zenrockd config set client chain-id gardia-2
zenrockd config set client keyring-backend test
zenrockd config set client node tcp://localhost:18257

# 初始化节点
zenrockd init $MONIKER --chain-id gardia-2

# 下载创世区块和地址簿
curl -Ls https://snapshots.kjnodes.com/zenrock-testnet/genesis.json > $HOME/.zrchain/config/genesis.json
curl -Ls https://snapshots.kjnodes.com/zenrock-testnet/addrbook.json > $HOME/.zrchain/config/addrbook.json

# 添加种子节点
sed -i -e "s|^seeds *=.*|seeds = \"3f472746f46493309650e5a033076689996c8881@zenrock-testnet.rpc.kjnodes.com:18259\"|" $HOME/.zrchain/config/config.toml

# 设置 GAS
sed -i -e "s|^minimum-gas-prices *=.*|minimum-gas-prices = \"0urock\"|" $HOME/.zrchain/config/app.toml

# 设置修剪参数
sed -i \
    -e 's|^pruning *=.*|pruning = "custom"|' \
    -e 's|^pruning-keep-recent *=.*|pruning-keep-recent = "100"|' \
    -e 's|^pruning-keep-every *=.*|pruning-keep-every = "0"|' \
    -e 's|^pruning-interval *=.*|pruning-interval = "19"|' \
    $HOME/.zrchain/config/app.toml

# 调整端口
sed -i -e "s%^proxy_app = \"tcp://127.0.0.1:26658\"%proxy_app = \"tcp://127.0.0.1:18258\"%;" \
       -e "s%^laddr = \"tcp://127.0.0.1:26657\"%laddr = \"tcp://127.0.0.1:18257\"%;" \
       -e "s%^pprof_laddr = \"localhost:6060\"%pprof_laddr = \"localhost:18260\"%;" \
       -e "s%^laddr = \"tcp://0.0.0.0:26656\"%laddr = \"tcp://0.0.0.0:18256\"%;" \
       -e "s%^prometheus_listen_addr = \":26660\"%prometheus_listen_addr = \":18266\"%;" \
       $HOME/.zrchain/config/config.toml

sed -i -e "s%^address = \"tcp://0.0.0.0:1317\"%address = \"tcp://0.0.0.0:18217\"%;" \
       -e "s%^address = \":8080\"%address = \":18280\"%;" \
       -e "s%^address = \"0.0.0.0:9090\"%address = \"0.0.0.0:18290\"%;" \
       -e "s%^address = \"0.0.0.0:9091\"%address = \"0.0.0.0:18291\"%;" \
       -e "s%:8545%:18245%;" \
       -e "s%:8546%:18246%;" \
       -e "s%:6065%:18265%;" \
       $HOME/.zrchain/config/app.toml

# 下载快照并启动节点
curl -L https://snapshots.kjnodes.com/zenrock-testnet/snapshot_latest.tar.lz4 | tar -Ilz4 -xf - -C $HOME/.zrchain
[[ -f $HOME/.zrchain/data/upgrade-info.json ]] && cp $HOME/.zrchain/data/upgrade-info.json $HOME/.zrchain/cosmovisor/genesis/upgrade-info.json

# 启动服务
sudo systemctl start zenrock-testnet.service
}

# 创建钱包函数
function create_wallet() {
    echo "正在创建钱包..."
    zenrockd keys add $WALLET
    WALLET_ADDRESS=$(zenrockd keys show $WALLET -a)
    
    echo "export WALLET_ADDRESS=\"$WALLET_ADDRESS\"" >> $HOME/.bash_profile
    source $HOME/.bash_profile

    echo "钱包创建完成！"
    echo "钱包地址: $WALLET_ADDRESS"
}

# 导入钱包函数
function import_wallet() {
    echo "正在导入钱包..."
    zenrockd keys add $WALLET --recover
  

    echo "export WALLET_ADDRESS=\"$WALLET_ADDRESS\"" >> $HOME/.bash_profile
    source $HOME/.bash_profile

    echo "钱包导入完成！"
    echo "钱包地址: $WALLET_ADDRESS"
}

# 查看日志
function check_sync_status() {
    echo "正在查看日志状态..."
    sudo journalctl -u zenrock-testnet.service -f --no-hostname -o cat
}

# 删除节点函数
function delete_node() {
    echo "正在删除节点..."
    sudo systemctl stop zenrockd
    sudo systemctl disable zenrockd
    sudo rm -rf /etc/systemd/system/zenrockd.service
    sudo rm $(which zenrockd)
    sudo rm -rf $HOME/.zrchain
    sed -i "/ZENROCK_/d" $HOME/.bash_profile
    echo "节点删除完成！"
}

# 创建验证人函数
function create_validator() {
    echo "正在创建验证人..."
    cd $HOME

    # 获取用户输入的 Moniker 和 Email
    read -p "请输入您的 Moniker 名称: " MONIKER
    read -p "请输入您的安全邮箱: " SECURITY_EMAIL

    # 创建验证人
    zenrockd tx validation create-validator <(cat <<EOF
{
  "pubkey": $(zenrockd comet show-validator),
  "amount": "1000000urock",
  "moniker": "$MONIKER",
  "identity": "",
  "website": "",
  "security": "$SECURITY_EMAIL",
  "details": "I love blockchain ❤️",
  "commission-rate": "0.05",
  "commission-max-rate": "0.20",
  "commission-max-change-rate": "0.05",
  "min-self-delegation": "1"
}
EOF
) \
--chain-id gardia-2 \
--from $WALLET \
--gas-adjustment 1.4 \
--gas auto \
--gas-prices 0urock \
-y

    echo "验证人创建完成！"
}

# 委托质押函数
function delegate_stake() {
    read -p "请输入质押金额 (默认 1000000): " STAKE_AMOUNT
    STAKE_AMOUNT=${STAKE_AMOUNT:-1000000}  # 如果没有输入，则默认为 1000000

    echo "正在委托质押 $STAKE_AMOUNT uro"
    zenrockd tx validation delegate $(zenrockd keys show $WALLET --bech val -a) ${STAKE_AMOUNT}urock \
        --from $WALLET --chain-id $ZENROCK_CHAIN_ID --fees 30urock -y

    echo "委托质押完成！"
}

# 主菜单函数
function main_menu() {
    while true; do
        clear
        echo "脚本由推特 @ferdie_jhovie，免费开源，请勿相信收费"
        echo "================================================================"
        echo "节点社区 Telegram 群组: https://t.me/niuwuriji"
        echo "节点社区 Telegram 频道: https://t.me/niuwuriji"
        echo "节点社区 Discord 社群: https://discord.gg/GbMV5EcNWF"
        echo "退出脚本，请按键盘 ctrl+c 退出即可"
        echo "请选择要执行的操作:"
        echo "1) 部署脚本"
        echo "2) 创建钱包"
        echo "3) 导入钱包"
        echo "4) 查看节点同步状态"
        echo "5) 删除节点"
        echo "6) 创建验证人"
        echo "7) 委托质押"
        echo "8) 退出脚本"

        read -p "输入选项: " choice

        case $choice in
            1)
                deploy_script
                ;;
            2)
                create_wallet
                ;;
            3)
                import_wallet
                ;;
            4)
                check_sync_status
                ;;
            5)
                delete_node
                ;;
            6)
                create_validator
                ;;
            7)
                delegate_stake
                ;;
            8)
                echo "退出脚本。"
                exit 0
                ;;
            *)
                echo "无效选项，请重试."
                ;;
        esac

        read -p "按任意键继续..."
    done
}

# 运行主菜单
main_menu
