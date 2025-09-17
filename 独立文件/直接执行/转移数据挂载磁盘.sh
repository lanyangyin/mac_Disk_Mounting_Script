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

# 初始化变量用于跟踪需要复制的文件
files_to_copy=()
has_files_to_copy=false
copy_executed=false

# 遍历配置，检查需要复制的文件
for key value in "${(@kv)config}"; do
    source_dir="$value"
    target_dir="/Volumes/$key"

    echo "===== 检查文件 ($key) ====="

    found_files=false
    # 使用find命令查找目标目录中的所有文件
    while IFS= read -r file; do
        if [[ -n "$file" ]]; then
            # 获取文件相对于目标目录的路径
            rel_path="${file#$source_dir/}"

            # 检查源目录中是否不存在该文件
            if [[ ! -e "$target_dir/$rel_path" ]]; then
                if [[ $found_files == false ]]; then
                    echo "将要复制的文件:"
                    found_files=true
                    has_files_to_copy=true
                fi
                echo "  $rel_path"
                files_to_copy+=("$file")
            fi
        fi
    done < <(find "$source_dir" -type f -print 2>/dev/null)

    if [[ $found_files == false ]]; then
        echo "没有需要复制的文件"
    fi

    echo ""
done

# 复制文件
if [[ $has_files_to_copy == true ]]; then
    # 开始复制文件
    for key value in "${(@kv)config}"; do
        source_dir="$value"
        target_dir="/Volumes/$key"

        # 检查目录是否存在
        if [[ ! -d "$target_dir" || ! -d "$source_dir" ]]; then
            continue
        fi

        echo "正在复制文件: $key"

        # 复制文件从目标目录到源目录
        while IFS= read -r file; do
            if [[ -n "$file" ]]; then
                rel_path="${file#$source_dir/}"

                if [[ ! -e "$target_dir/$rel_path" ]]; then
                    # 创建目标目录结构并复制文件
                    mkdir -p "$(dirname "$target_dir/$rel_path")"
                    cp -v "$file" "$target_dir/$rel_path"
                fi
            fi
        done < <(find "$source_dir" -type f -print 2>/dev/null)
    done

    echo "文件复制完成"
    copy_executed=true
else
    copy_executed=true
fi

# 清空目标目录
# 安全检查：确保复制操作已执行且源文件夹中所有文件都在目标文件夹中
safe_to_delete=true
for key value in "${(@kv)config}"; do
    source_dir="$value"
    target_dir="/Volumes/$key"

    # 检查是否执行了复制步骤
    if [[ $copy_executed != true ]]; then
        echo "❌ 安全警告: 未执行复制步骤，不允许删除源文件夹中的文件"
        safe_to_delete=false
        break
    fi

    # 检查源文件夹中是否有文件不在目标文件夹中
    while IFS= read -r file; do
        if [[ -n "$file" ]]; then
            rel_path="${file#$source_dir/}"
            if [[ ! -e "$target_dir/$rel_path" ]]; then
                echo "❌ 安全警告: 源文件夹中的文件 $rel_path 不在目标文件夹中，不允许删除"
                safe_to_delete=false
                break 2
            fi
        fi
    done < <(find "$source_dir" -type f -print 2>/dev/null)
done

# 只有通过安全检查才执行删除
if [[ $safe_to_delete == true ]]; then
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
    echo "❌ 已跳过清空目录操作 - 安全冗余检查失败"
fi

# 卸载磁盘并使用mount_apfs重新挂载到指定目录
for key value in "${(@kv)config}"; do
    temp_var=$(diskutil list | awk -v key=" $key " '/APFS Volume/ && $0 ~ key {print $NF}')
    diskutil unmount /dev/$temp_var || echo "$key 的磁盘 $temp_var 卸载失败"
    sudo /sbin/mount_apfs /dev/$temp_var "$value"
    sudo chmod 777 "$value"  # 设置目录权限为可读写
done