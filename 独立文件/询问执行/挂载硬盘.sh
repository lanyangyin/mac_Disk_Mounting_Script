#!/bin/zsh

# 初始化空关联数组
typeset -A config

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--name)
            app_name="$2"
            shift 2
            ;;
        -p|--path)
            mount_path="$2"
            shift 2
            ;;
        *)
            echo "未知参数: $1"
            exit 1
            ;;
    esac

    # 当收集到一对完整的名称和路径时，添加到配置
    if [[ -n "$app_name" && -n "$mount_path" ]]; then
        config[$app_name]="$mount_path"
        app_name=""
        mount_path=""
    fi
done

# 检查是否提供了任何配置
if [ ${#config[@]} -eq 0 ]; then
    echo "错误: 未提供任何配置参数"
    echo "用法: $0 -n 应用名称 -p 挂载路径 [-n 应用名称2 -p 挂载路径2 ...]"
    exit 1
fi

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

echo "检查完毕"

# 询问用户是否要打开磁盘卷和挂载目标文件夹
echo ""
echo "即将挂载："
for key value in "${(@kv)config}"; do
    temp_var=$(diskutil list | awk -v key=" $key " '/APFS Volume/ && $0 ~ key {print $NF}')
    source_dir="/Volumes/$key"
    target_dir="$value"
    echo "  $source_dir （ $temp_var ）--> $target_dir"
done
echo ""
read -q "REPLY?是否要挂载这些磁盘卷到目标文件夹? (y/n) "
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    # 卸载磁盘并使用mount_apfs重新挂载到指定目录
    for key value in "${(@kv)config}"; do
        temp_var=$(diskutil list | awk -v key=" $key " '/APFS Volume/ && $0 ~ key {print $NF}')
        diskutil unmount /dev/$temp_var || echo "$key 的磁盘 $temp_var 卸载失败"
        sudo /sbin/mount_apfs /dev/$temp_var "$value"
        sudo chmod 777 "$value"  # 设置目录权限为可读写
    done
    echo "已完成挂载操作"
else
    echo "已取消挂载操作"
fi