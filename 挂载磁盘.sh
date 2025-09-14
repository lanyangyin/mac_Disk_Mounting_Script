#!/bin/zsh

typeset -A config
config=(
    obs-studio   /Users/lanan/Library/Application\ Support/obs-studio 
    微信         /Users/lanan/Library/Containers/com.tencent.xinWeChat
)

for key value in "${(@kv)config}"; do
    temp_var=$(diskutil list | awk -v key=" $key " '/APFS Volume/ && $0 ~ key {print $NF}')
    temp_var_formatted=$(echo "$temp_var" | tr '\n' ';')
    
    disk_count=$(echo "$temp_var" | grep -c "disk")
    
    if [ $disk_count -gt 1 ]; then
        echo "⚠警告: $key 找到多个同名磁盘卷 $temp_var_formatted"
        return 1
    elif [ $disk_count -eq 0 ]; then
        echo "⚠警告: $key 未找到磁盘卷"
        return 1
    fi
    
    if [ ! -d "$value" ]; then
        echo "⚠警告: $key 所对应的 $temp_var_formatted 的挂载点 $value 不存在"
        return 1
    fi
    
    echo "$key: $value: $temp_var"
done

for key value in "${(@kv)config}"; do
    temp_var=$(diskutil list | awk -v key=" $key " '/APFS Volume/ && $0 ~ key {print $NF}')
    echo "正在卸载 $temp_var..."
    diskutil unmount /dev/$temp_var || echo "$key 的磁盘 $temp_var 卸载失败"
    
    echo "正在重新挂载 $temp_var..."
    diskutil mount /dev/$temp_var
    
    sleep 2
done

echo "检查完毕，开始挂载"

for key value in "${(@kv)config}"; do
    temp_var=$(diskutil list | awk -v key=" $key " '/APFS Volume/ && $0 ~ key {print $NF}')    
    diskutil unmount /dev/$temp_var || echo "$key 的磁盘 $temp_var 卸载失败"
    sudo /sbin/mount_apfs /dev/$temp_var "$value"    
    sudo chmod 777 "$value"
done