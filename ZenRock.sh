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

  # 让用户输入 MONIKER 名称
    read -p "请输入您的 MONIKER 名称: " MONIKER
    echo "您输入的 MONIKER 名称是: $MONIKER"

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
    WALLET_NAME="${WALLET_NAME:-wallet}"  # 如果 WALLET_NAME 未设置，则使用默认名称 'wallet'
    zenrockd keys add "$WALLET_NAME"  # 使用钱包名称创建钱包
    echo "钱包创建完成！"
}


# 导入钱包函数
function import_wallet() {
    echo "正在导入钱包..."
    WALLET="${WALLET:-wallet}"  # 如果 WALLET 未设置，则使用默认名称 'wallet'
    zenrockd keys add "$WALLET" --recover  # 使用钱包名称导入钱包
    echo "钱包导入完成！"
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

    # 获取用户输入的 Moniker 
    read -p "请输入您的 Moniker: " MONIKER  # 让用户自行输入 Moniker

    # 创建验证人
    zenrockd tx validation create-validator <(cat <<EOF
{
  "pubkey": $(zenrockd comet show-validator),
  "amount": "1000000urock",
  "moniker": "$MONIKER",
  "details": "I love blockchain ❤️",
  "commission-rate": "0.05",
  "commission-max-rate": "0.20",
  "commission-max-change-rate": "0.05",
  "min-self-delegation": "1"
}
EOF
) \
--chain-id gardia-2 \
--from wallet \
--gas-adjustment 1.4 \
--gas auto \
--gas-prices 30urock \
-y

    echo "验证人创建完成！"
}

# 查看余额函数
function check_balance() {
    echo "正在查看余额..."
    zenrockd q bank balances $(zenrockd keys show wallet -a)
}

# 生成密钥
function generate_keys() {
    echo "正在生成密钥..."
    cd $HOME
    rm -rf zenrock-validators
    git clone https://github.com/zenrocklabs/zenrock-validators
    read -p "Enter password for the keys: " key_pass
}

# 输出ecdsa地址
function output_ecdsa_address() {
    echo "输出ecdsa地址..."
    mkdir -p $HOME/.zrchain/sidecar/bin
    mkdir -p $HOME/.zrchain/sidecar/keys
    cd $HOME/zenrock-validators/utils/keygen/ecdsa && go build
    cd $HOME/zenrock-validators/utils/keygen/bls && go build
    ecdsa_output_file=$HOME/.zrchain/sidecar/keys/ecdsa.key.json
    ecdsa_creation=$($HOME/zenrock-validators/utils/keygen/ecdsa/ecdsa --password $key_pass -output-file $ecdsa_output_file)
    ecdsa_address=$(echo "$ecdsa_creation" | grep "Public address" | cut -d: -f2)
    echo "请保存 ECDSA 地址后按任意键继续..."
    read -n 1
    bls_output_file=$HOME/.zrchain/sidecar/keys/bls.key.json
    $HOME/zenrock-validators/utils/keygen/bls/bls --password $key_pass -output-file $bls_output_file
    echo "ecdsa address: $ecdsa_address"
}

# 设置配置
function set_operator_config() {
    echo "设置配置..."
    echo "请充值 Holesky $ETH 到钱包，然后输入 'yes' 继续"
    read -p "是否已完成充值? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "请在充值后重试."
        return
    fi

    read -p "请输入测试网 Holesky 终端点: " TESTNET_HOLESKY_ENDPOINT
    read -p "请输入主网终端点: " MAINNET_ENDPOINT
    read -p "请输入测试网 Holesky RPC URL: " ETH_RPC_URL
    read -p "请输入测试网 Holesky WebSocket URL: " ETH_WS_URL

    OPERATOR_VALIDATOR_ADDRESS_TBD=$(zenrockd keys show wallet --bech val -a)
    OPERATOR_ADDRESS_TBU=$ecdsa_address
    EIGEN_OPERATOR_CONFIG="$HOME/.zrchain/sidecar/eigen_operator_config.yaml"
    ECDSA_KEY_PATH=$ecdsa_output_file
    BLS_KEY_PATH=$bls_output_file

    cp $HOME/zenrock-validators/configs/eigen_operator_config.yaml $HOME/.zrchain/sidecar/
    cp $HOME/zenrock-validators/configs/config.yaml $HOME/.zrchain/sidecar/

    sed -i "s|EIGEN_OPERATOR_CONFIG|$EIGEN_OPERATOR_CONFIG|g" "$HOME/.zrchain/sidecar/config.yaml"
    sed -i "s|TESTNET_HOLESKY_ENDPOINT|$TESTNET_HOLESKY_ENDPOINT|g" "$HOME/.zrchain/sidecar/config.yaml"
    sed -i "s|MAINNET_ENDPOINT|$MAINNET_ENDPOINT|g" "$HOME/.zrchain/sidecar/config.yaml"
    sed -i "s|OPERATOR_VALIDATOR_ADDRESS_TBD|$OPERATOR_VALIDATOR_ADDRESS_TBD|g" "$HOME/.zrchain/sidecar/eigen_operator_config.yaml"
    sed -i "s|OPERATOR_ADDRESS_TBU|$OPERATOR_ADDRESS_TBU|g" "$HOME/.zrchain/sidecar/eigen_operator_config.yaml"
    sed -i "s|ETH_RPC_URL|$ETH_RPC_URL|g" "$HOME/.zrchain/sidecar/eigen_operator_config.yaml"
    sed -i "s|ETH_WS_URL|$ETH_WS_URL|g" "$HOME/.zrchain/sidecar/eigen_operator_config.yaml"
    sed -i "s|ECDSA_KEY_PATH|$ECDSA_KEY_PATH|g" "$HOME/.zrchain/sidecar/eigen_operator_config.yaml"
    sed -i "s|BLS_KEY_PATH|$BLS_KEY_PATH|g" "$HOME/.zrchain/sidecar/eigen_operator_config.yaml"

    wget -O $HOME/.zrchain/sidecar/bin/validator_sidecar https://releases.gardia.zenrocklabs.io/validator_sidecar-1.2.3
    chmod +x $HOME/.zrchain/sidecar/bin/validator_sidecar

    sudo tee /etc/systemd/system/zenrock-testnet-sidecar.service > /dev/null <<EOF
[Unit]
Description=Validator Sidecar
After=network-online.target

[Service]
User=$USER
ExecStart=$HOME/.zrchain/sidecar/bin/validator_sidecar
Restart=on-failure
RestartSec=30
LimitNOFILE=65535
Environment="OPERATOR_BLS_KEY_PASSWORD=$key_pass"
Environment="OPERATOR_ECDSA_KEY_PASSWORD=$key_pass"
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable zenrock-testnet-sidecar.service
    sudo systemctl start zenrock-testnet-sidecar.service
}

# 备份 sidecar 配置和密钥
function backup_sidecar_config() {
    echo "正在备份 sidecar 配置和密钥..."
    backup_dir="$HOME/.zrchain/sidecar_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p $backup_dir
    cp -r $HOME/.zrchain/sidecar/* $backup_dir
    echo "备份完成，备份路径为：$backup_dir"
}

# 检查日志
function check_logs() {
    echo "正在检查日志..."
    journalctl -fu zenrock-testnet-sidecar.service -o cat
}

# 主菜单
function setup_operator() {
    echo "您可以执行以下验证器操作："
    echo "1. 生成密钥" 
    echo "2. 输出ecdsa地址" 
    echo "3. 设置配置" 
    echo "4. 检查日志" 
    echo "5. 备份sidecar 配置和密钥"  
    read -p "请输入选项（1-5）: " OPTION

    case $OPTION in
        1) generate_keys ;;
        2) output_ecdsa_address ;;
        3) set_operator_config ;;
        4) check_logs ;; 
        5) backup_sidecar_config ;;
        *) echo "无效选项，请重新选择。" ;;
    esac
}

# 委托验证者函数
function delegate_validator() {
    echo "正在委托验证者..."
    zenrockd tx validation delegate $(zenrockd keys show wallet --bech val -a) 1000000urock --from wallet --chain-id gardia-2 --gas-adjustment 1.4 --gas auto --gas-prices 25urock -y
    echo "委托完成！"
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
        echo "5) 创建验证人"
        echo "6) 委托验证者"
        echo "7) 查看余额"
        echo "8) 设置操作员函数"
        echo "9) 删除节点" 
        echo "10) 退出脚本"  

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
                create_validator
                ;;
            6)
                delegate_validator 
                ;;
            7)
                check_balance
                ;;
            8)
                setup_operator
                ;;
            9)
                delete_node
                ;;
            10)
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
