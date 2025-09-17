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

# 检查磁盘状态函数
check_disk_status() {
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
    return 0
}

# 卸载并重新挂载函数
remount_disks() {
    for key value in "${(@kv)config}"; do
        temp_var=$(diskutil list | awk -v key=" $key " '/APFS Volume/ && $0 ~ key {print $NF}')
        echo "正在卸载 $temp_var..."
        diskutil unmount /dev/$temp_var || echo "$key 的磁盘 $temp_var 卸载失败"

        echo "正在重新挂载 $temp_var..."
        diskutil mount /dev/$temp_var

        # 等待2秒让系统完成挂载操作
        sleep 2
    done
}

# 打开磁盘函数
open_disk() {
    remount_disks
    echo "检查完毕"

    # 询问用户是否要打开磁盘卷和挂载目标文件夹
    echo ""
    echo "即将打开："
    for key value in "${(@kv)config}"; do
        source_dir="/Volumes/$key"
        target_dir="$value"

        echo "  $source_dir"
        echo "  $target_dir"
    done
    echo ""
    read -q "REPLY?是否要打开这些磁盘卷和挂载目标文件夹? (y/n) "
    echo ""

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # 使用Finder打开每个磁盘卷和对应的目标目录
        for key value in "${(@kv)config}"; do
            source_dir="/Volumes/$key"
            target_dir="$value"

            echo "打开Finder窗口: $source_dir 和 $target_dir"
            open -a Finder "$source_dir"
            open -a Finder "$target_dir"
        done
        echo "已完成打开操作"
    else
        echo "已取消打开操作"
    fi
}

# 复原磁盘默认挂载函数
restore_default_mount() {
    # 询问用户是否要打开磁盘卷和挂载目标文件夹
    echo ""
    echo "即将复原默认挂载："
    for key value in "${(@kv)config}"; do
        temp_var=$(diskutil list | awk -v key=" $key " '/APFS Volume/ && $0 ~ key {print $NF}')
        source_dir="/Volumes/$key"
        target_dir="$value"
        echo "   $temp_var （ $target_dir ） --> $temp_var （ $source_dir ）"
    done
    echo ""
    read -q "REPLY?是否复原磁盘默认挂载? (y/n) "
    echo ""

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        remount_disks
        echo "已完成复原挂载操作"
    else
        echo "已取消复原挂载操作"
    fi
}

# 挂载硬盘函数
mount_disk() {
    remount_disks
    echo "检查完毕"

    # 询问用户是否要挂载磁盘卷到目标文件夹
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
}

# 恢复数据函数
recover_data() {
    remount_disks
    echo "检查完毕"

    # 初始化变量用于跟踪需要复制的文件
    files_to_copy=()
    has_files_to_copy=false
    copy_executed=false

    # 遍历配置，检查需要从磁盘卷恢复的文件
    for key value in "${(@kv)config}"; do
        source_dir="/Volumes/$key"
        target_dir="$value"

        echo "===== 检查文件 ($key) ====="

        found_files=false
        # 查找磁盘卷中的所有文件
        while IFS= read -r file; do
            if [[ -n "$file" ]]; then
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

    # 如果有文件需要复制，请求用户确认
    if [[ $has_files_to_copy == true ]]; then
        read -q "REPLY?确认要复制上述文件吗？(y/n) "
        echo ""

        if [[ $REPLY =~ ^[Yy]$ ]]; then
            # 复制文件从磁盘卷到原始位置
            for key value in "${(@kv)config}"; do
                source_dir="/Volumes/$key"
                target_dir="$value"

                if [[ ! -d "$target_dir" || ! -d "$source_dir" ]]; then
                    continue
                fi

                echo "正在复制文件: $key"

                while IFS= read -r file; do
                    if [[ -n "$file" ]]; then
                        rel_path="${file#$source_dir/}"

                        if [[ ! -e "$target_dir/$rel_path" ]]; then
                            mkdir -p "$(dirname "$target_dir/$rel_path")"
                            cp -v "$file" "$target_dir/$rel_path"
                        fi
                    fi
                done < <(find "$source_dir" -type f -print 2>/dev/null)
            done

            echo "文件复制完成"
            copy_executed=true
        else
            echo "文件复制已取消"
        fi
    else
        copy_executed=true
    fi

    # 询问用户是否要清空磁盘卷
    if [[ $has_files_to_copy == true ]]; then
        echo ""
        read -q "REPLY2?是否要清空目标目录（只删除内部文件，保留目录本身）? (y/n) "
        echo ""
    else
        # 如果没有文件需要复制直接删除目标目录
        REPLY2=y
    fi

    if [[ $REPLY2 =~ ^[Yy]$ ]]; then
        # 安全检查：确保复制操作已执行且源文件夹中所有文件都在目标文件夹中
        safe_to_delete=true
        for key value in "${(@kv)config}"; do
            source_dir="/Volumes/$key"
            target_dir="$value"

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
            echo "❌ 已跳过清空目录操作 - 安全冗余检查失败"
        fi
    else
        echo "已跳过清空目录操作"
    fi
}

# 拷贝数据函数
copy_data() {
    remount_disks
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

    # 如果有文件需要复制，请求用户确认
    if [[ $has_files_to_copy == true ]]; then
        read -q "REPLY?确认要复制上述文件吗？(y/n) "
        echo ""

        if [[ $REPLY =~ ^[Yy]$ ]]; then
            # 用户确认后，开始复制文件
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
            echo "文件复制已取消"
        fi
    else
        copy_executed=true
    fi

    # 询问用户是否要清空目标目录
    if [[ $has_files_to_copy == true ]]; then
        echo ""
        read -q "REPLY2?是否要清空目标目录（只删除内部文件，保留目录本身）? (y/n) "
        echo ""
    else
        # 如果没有文件需要复制直接删除目标目录
        REPLY2=y
    fi

    if [[ $REPLY2 =~ ^[Yy]$ ]]; then
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
    else
        echo "已跳过清空目录操作"
    fi
}

# 转移数据挂载磁盘函数
transfer_data_and_mount() {
    remount_disks
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

    # 如果有文件需要复制，请求用户确认
    if [[ $has_files_to_copy == true ]]; then
        read -q "REPLY?确认要复制上述文件吗？(y/n) "
        echo ""

        if [[ $REPLY =~ ^[Yy]$ ]]; then
            # 用户确认后，开始复制文件
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
            echo "文件复制已取消"
        fi
    else
        copy_executed=true
    fi

    # 询问用户是否要清空目标目录
    if [[ $has_files_to_copy == true ]]; then
        echo ""
        read -q "REPLY2?是否要清空目标目录（只删除内部文件，保留目录本身）? (y/n) "
        echo ""
    else
        # 如果没有文件需要复制直接删除目标目录
        REPLY2=y
    fi

    if [[ $REPLY2 =~ ^[Yy]$ ]]; then
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
}

# 主菜单函数
show_menu() {
    echo ""
    echo "========================================"
    echo "          磁盘挂载工具"
    echo "========================================"
    echo "请选择要执行的操作（可多选，用空格分隔）:"
    echo ""
    echo "  1. 打开磁盘"
    echo "  2. 复原磁盘默认挂载"
    echo "  3. 挂载硬盘"
    echo "  4. 恢复数据"
    echo "  5. 拷贝数据"
    echo "  6. 转移数据并挂载磁盘"
    echo ""
    echo "  0. 退出"
    echo ""
    echo "========================================"
}

# 主程序
while true; do
    # 检查磁盘状态
    if ! check_disk_status; then
        echo "磁盘状态检查失败，请检查配置后重试"
        exit 1
    fi

    # 显示菜单
    show_menu

    # 读取用户选择
    read "selection?请输入选择（多个选项用空格分隔）: "
    echo ""

    # 处理用户选择
    selections=(${=selection})
    valid_selection=true

    # 验证选择是否有效
    for s in $selections; do
        if [[ $s -lt 0 || $s -gt 6 ]]; then
            echo "无效选择: $s"
            valid_selection=false
        fi
    done

    if [[ $valid_selection == false ]]; then
        echo "请重新选择"
        continue
    fi

    # 处理退出选项
    if [[ ${selections[(ie)0]} -le ${#selections} ]]; then
        echo "退出程序"
        exit 0
    fi

    # 按顺序执行选中的功能
    for s in $selections; do
        case $s in
            1)
                echo "执行: 打开磁盘"
                open_disk
                ;;
            2)
                echo "执行: 复原磁盘默认挂载"
                restore_default_mount
                ;;
            3)
                echo "执行: 挂载硬盘"
                mount_disk
                ;;
            4)
                echo "执行: 恢复数据"
                recover_data
                ;;
            5)
                echo "执行: 拷贝数据"
                copy_data
                ;;
            6)
                echo "执行: 转移数据并挂载磁盘"
                transfer_data_and_mount
                ;;
        esac
        echo ""
    done

    # 询问是否继续
    echo "========================================"
    read -q "REPLY?是否继续使用磁盘挂载工具? (y/n) "
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "退出程序"
        exit 0
    fi
done