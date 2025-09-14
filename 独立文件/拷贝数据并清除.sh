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

echo "检查完毕，开始转移"

# 初始化变量用于跟踪需要复制的文件
files_to_copy=()
has_files_to_copy=false

# 遍历配置，检查需要复制的文件
for key value in "${(@kv)config}"; do
    source_dir="/Volumes/$key"
    target_dir="$value"

    echo "===== 检查文件 ($key) ====="

    found_files=false
    # 使用find命令查找目标目录中的所有文件
    while IFS= read -r file; do
        if [[ -n "$file" ]]; then
            # 获取文件相对于目标目录的路径
            rel_path="${file#$target_dir/}"

            # 检查源目录中是否不存在该文件
            if [[ ! -e "$source_dir/$rel_path" ]]; then
                if [[ $found_files == false ]]; then
                    echo "将要复制的文件:"
                    found_files=true
                    has_files_to_copy=true
                fi
                echo "  $rel_path"
                files_to_copy+=("$file")
            fi
        fi
    done < <(find "$target_dir" -type f -print 2>/dev/null)

    if [[ $found_files == false ]]; then
        echo "没有需要复制的文件"
    fi

    echo ""
done

# 如果有文件需要复制，请求用户确认
if [[ $has_files_to_copy == true ]]; then
    read -q "REPLY?确认要复制上述文件吗？(y/n) "
    echo ""

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # 用户确认后，开始复制文件
        for key value in "${(@kv)config}"; do
            source_dir="/Volumes/$key"
            target_dir="$value"

            # 检查目录是否存在
            if [[ ! -d "$source_dir" || ! -d "$target_dir" ]]; then
                continue
            fi

            echo "正在复制文件: $key"

            # 复制文件从目标目录到源目录
            while IFS= read -r file; do
                if [[ -n "$file" ]]; then
                    rel_path="${file#$target_dir/}"

                    if [[ ! -e "$source_dir/$rel_path" ]]; then
                        # 创建目标目录结构并复制文件
                        mkdir -p "$(dirname "$source_dir/$rel_path")"
                        cp -v "$file" "$source_dir/$rel_path"
                    fi
                fi
            done < <(find "$target_dir" -type f -print 2>/dev/null)
        done

        echo "文件复制完成"
    else
        echo "文件复制已取消"
    fi
fi

# 询问用户是否要清空目标目录
REPLY2=y

if [[ $REPLY2 =~ ^[Yy]$ ]]; then
    # 清空目标目录中的所有内容
    for key value in "${(@kv)config}"; do
        target_dir="$value"
        
        if [[ -d "$target_dir" ]]; then
            echo "正在清空目录: $target_dir"
            find "$target_dir" -mindepth 1 -delete 2>/dev/null
            echo "目录已清空: $target_dir"
        else
            echo "目录不存在，跳过: $target_dir"
        fi
    done
    echo "所有目标目录已清空"
else
    echo "已跳过清空目录操作"
fi