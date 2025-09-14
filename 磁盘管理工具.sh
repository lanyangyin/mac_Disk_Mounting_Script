#!/bin/zsh

# 配置信息 - 定义关联数组存储应用名称和对应目录路径
typeset -A config
config=(
    obs-studio   /Users/lanan/Library/Application\ Support/obs-studio
    微信         /Users/lanan/Library/Containers/com.tencent.xinWeChat
)

# 显示使用说明函数
show_usage() {
    echo "用法: $0 [选项]"
    echo "选项:"
    echo "  -m, --mount      挂载磁盘并转移数据"
    echo "  -o, --open       打开磁盘目录"
    echo "  -r, --restore    恢复数据到原始位置"
    echo "  -h, --help       显示此帮助信息"
}

# 检查磁盘函数 - 验证磁盘是否存在并可访问
check_disks() {
    # 遍历配置中的每个应用和目录
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

    echo "磁盘检查完毕"
}

# 挂载磁盘并转移数据函数
mount_and_transfer() {
    # 首先检查磁盘状态，如果失败则返回
    check_disks || return 1

    echo "开始挂载并转移数据"

    # 初始化变量用于跟踪需要移动的文件
    files_to_move=()
    has_files_to_move=false

    # 遍历配置，检查需要移动的文件
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
                        echo "将要移动的文件:"
                        found_files=true
                        has_files_to_move=true
                    fi
                    echo "  $rel_path"
                    files_to_move+=("$file")
                fi
            fi
        done < <(find "$target_dir" -type f -print 2>/dev/null)

        if [[ $found_files == false ]]; then
            echo "没有需要移动的文件"
        fi

        echo ""
    done

    # 如果有文件需要移动，请求用户确认
    if [[ $has_files_to_move == true ]]; then
        read -q "REPLY?确认要移动上述文件吗？(y/n) "
        echo ""

        if [[ $REPLY =~ ^[Yy]$ ]]; then
            # 用户确认后，开始移动文件
            for key value in "${(@kv)config}"; do
                source_dir="/Volumes/$key"
                target_dir="$value"

                # 检查目录是否存在
                if [[ ! -d "$source_dir" || ! -d "$target_dir" ]]; then
                    continue
                fi

                echo "正在移动文件: $key"

                # 移动文件从目标目录到源目录
                while IFS= read -r file; do
                    if [[ -n "$file" ]]; then
                        rel_path="${file#$target_dir/}"

                        if [[ ! -e "$source_dir/$rel_path" ]]; then
                            # 创建目标目录结构并移动文件
                            mkdir -p "$(dirname "$source_dir/$rel_path")"
                            mv -v "$file" "$source_dir/$rel_path"
                        fi
                    fi
                done < <(find "$target_dir" -type f -print 2>/dev/null)
            done

            echo "文件移动完成"
        else
            echo "文件移动已取消"
        fi
    fi

    # 询问用户是否要清空目标目录
    echo ""
    read -q "REPLY2?是否要清空目标目录（只删除内部文件，保留目录本身）? (y/n) "
    echo ""

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

    # 卸载磁盘并使用mount_apfs重新挂载到指定目录
    for key value in "${(@kv)config}"; do
        temp_var=$(diskutil list | awk -v key=" $key " '/APFS Volume/ && $0 ~ key {print $NF}')
        diskutil unmount /dev/$temp_var || echo "$key 的磁盘 $temp_var 卸载失败"
        sudo /sbin/mount_apfs /dev/$temp_var "$value"
        sudo chmod 777 "$value"  # 设置目录权限为可读写
    done

    echo "挂载和数据转移完成"
}

# 打开磁盘目录函数
open_disks() {
    check_disks || return 1

    echo "开始打开磁盘目录"

    # 使用Finder打开每个磁盘卷和对应的目标目录
    for key value in "${(@kv)config}"; do
        source_dir="/Volumes/$key"
        target_dir="$value"

        echo "打开Finder窗口: $source_dir 和 $target_dir"
        open -a Finder "$source_dir"
        open -a Finder "$target_dir"
    done

    echo "目录已打开"
}

# 恢复数据到原始位置函数
restore_data() {
    check_disks || return 1

    echo "开始恢复数据"

    # 初始化变量用于跟踪需要移动的文件
    files_to_move=()
    has_files_to_move=false

    # 遍历配置，检查需要从磁盘卷恢复的文件
    for key value in "${(@kv)config}"; do
        source_dir="$value"
        target_dir="/Volumes/$key"

        echo "===== 检查文件 ($key) ====="

        found_files=false
        # 查找磁盘卷中的所有文件
        while IFS= read -r file; do
            if [[ -n "$file" ]]; then
                rel_path="${file#$target_dir/}"

                # 检查源目录中是否不存在该文件
                if [[ ! -e "$source_dir/$rel_path" ]]; then
                    if [[ $found_files == false ]]; then
                        echo "将要移动的文件:"
                        found_files=true
                        has_files_to_move=true
                    fi
                    echo "  $rel_path"
                    files_to_move+=("$file")
                fi
            fi
        done < <(find "$target_dir" -type f -print 2>/dev/null)

        if [[ $found_files == false ]]; then
            echo "没有需要移动的文件"
        fi

        echo ""
    done

    # 如果有文件需要移动，请求用户确认
    if [[ $has_files_to_move == true ]]; then
        read -q "REPLY?确认要移动上述文件吗？(y/n) "
        echo ""

        if [[ $REPLY =~ ^[Yy]$ ]]; then
            # 移动文件从磁盘卷回原始位置
            for key value in "${(@kv)config}"; do
                source_dir="$value"
                target_dir="/Volumes/$key"

                if [[ ! -d "$source_dir" || ! -d "$target_dir" ]]; then
                    continue
                fi

                echo "正在移动文件: $key"

                while IFS= read -r file; do
                    if [[ -n "$file" ]]; then
                        rel_path="${file#$target_dir/}"

                        if [[ ! -e "$source_dir/$rel_path" ]]; then
                            mkdir -p "$(dirname "$source_dir/$rel_path")"
                            mv -v "$file" "$source_dir/$rel_path"
                        fi
                    fi
                done < <(find "$target_dir" -type f -print 2>/dev/null)
            done

            echo "文件移动完成"
        else
            echo "文件移动已取消"
        fi
    fi

    # 询问用户是否要清空磁盘卷
    echo ""
    read -q "REPLY2?是否要清空目标目录（只删除内部文件，保留目录本身）? (y/n) "
    echo ""

    if [[ $REPLY2 =~ ^[Yy]$ ]]; then
        # 清空磁盘卷中的所有内容
        for key value in "${(@kv)config}"; do
            target_dir="/Volumes/$key"

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

    echo "数据恢复完成"
}

# 主程序入口点
main() {
    # 解析命令行参数
    case "$1" in
        -m|--mount)
            mount_and_transfer
            ;;
        -o|--open)
            open_disks
            ;;
        -r|--restore)
            restore_data
            ;;
        -h|--help)
            show_usage
            ;;
        *)
            echo "错误: 未知选项 '$1'"
            show_usage
            exit 1
            ;;
    esac
}

# 检查是否提供了参数
if [ $# -eq 0 ]; then
    echo "错误: 需要提供选项"
    show_usage
    exit 1
fi

# 执行主程序
main "$@"