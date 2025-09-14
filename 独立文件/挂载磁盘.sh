#!/bin/zsh

# 配置信息 - 定义关联数组存储应用名称和对应目录路径
typeset -A config
config=(
    obs-studio   /Users/lanan/Library/Application\ Support/obs-studio
    微信         /Users/lanan/Library/Containers/com.tencent.xinWeChat
)

# 检查磁盘状态
for key value in "${(@kv)config}"; do
    # 使用diskutil查找与key名称匹配的APFS卷
    temp_var=$(diskutil list | awk -v key=" $key " '/APFS Volume/ && $0 ~ key {print $NF}')
    temp_var_formatted=$(echo "$temp_var" | tr '\n' ';')

    # 统计找到的磁盘数量
    disk_count=$(echo "$temp_var" | grep -c "disk")

    # 检查是否找到多个同名磁盘卷
    if [ $disk_count -gt 1 ]; then
        echo "⚠警告: $key 找到多个同名磁盘卷 $temp_var_formatted"
        return 1
    # 检查是否未找到磁盘卷
    elif [ $disk_count -eq 0 ]; then
        echo "⚠警告: $key 未找到磁盘卷"
        return 1
    fi

    # 检查挂载点目录是否存在
    if [ ! -d "$value" ]; then
        echo "⚠警告: $key 所对应的 $temp_var_formatted 的挂载点 $value 不存在"
        return 1
    fi

    # 输出找到的磁盘信息
    echo "$key: $value: $temp_var"
done

# 卸载并重新挂载所有磁盘卷以确保它们处于正确状态
for key value in "${(@kv)config}"; do
    temp_var=$(diskutil list | awk -v key=" $key " '/APFS Volume/ && $0 ~ key {print $NF}')
    echo "正在卸载 $temp_var..."
    diskutil unmount /dev/$temp_var || echo "$key 的磁盘 $temp_var 卸载失败"

    echo "正在重新挂载 $temp_var..."
    diskutil mount /dev/$temp_var

    # 等待2秒让系统完成挂载操作
    sleep 2
done

echo "检查完毕，开始挂载"

# 卸载磁盘并使用mount_apfs重新挂载到指定目录
for key value in "${(@kv)config}"; do
    temp_var=$(diskutil list | awk -v key=" $key " '/APFS Volume/ && $0 ~ key {print $NF}')
    diskutil unmount /dev/$temp_var || echo "$key 的磁盘 $temp_var 卸载失败"
    sudo /sbin/mount_apfs /dev/$temp_var "$value"
    sudo chmod 777 "$value"  # 设置目录权限为可读写
done