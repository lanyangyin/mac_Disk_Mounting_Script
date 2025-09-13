#!/bin/zsh

# 配置信息
typeset -A config
config=(
    obs-studio   /Users/lanan/Library/Application\ Support/obs-studio 
    微信         /Users/lanan/Library/Containers/com.tencent.xinWeChat
)

# 显示使用说明
show_usage() {
    echo "用法: $0 [选项]"
    echo "选项:"
    echo "  -m, --mount      挂载磁盘并转移数据"
    echo "  -o, --open       打开磁盘目录"
    echo "  -r, --restore    恢复数据到原始位置"
    echo "  -h, --help       显示此帮助信息"
}

# 检查磁盘函数
check_disks() {
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
    
    echo "磁盘检查完毕"
}

# 挂载磁盘并转移数据
mount_and_transfer() {
    check_disks || return 1
    
    echo "开始挂载并转移数据"
    
    files_to_move=()
    has_files_to_move=false

    for key value in "${(@kv)config}"; do
        source_dir="/Volumes/$key"
        target_dir="$value"
        
        echo "===== 检查文件 ($key) ====="
        
        found_files=false
        while IFS= read -r file; do
            if [[ -n "$file" ]]; then
                rel_path="${file#$target_dir/}"
                
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

    if [[ $has_files_to_move == true ]]; then
        read -q "REPLY?确认要移动上述文件吗？(y/n) "
        echo ""
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            for key value in "${(@kv)config}"; do
                source_dir="/Volumes/$key"
                target_dir="$value"
                
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

    echo ""
    read -q "REPLY2?是否要清空目标目录（只删除内部文件，保留目录本身）? (y/n) "
    echo ""

    if [[ $REPLY2 =~ ^[Yy]$ ]]; then
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

    for key value in "${(@kv)config}"; do
        temp_var=$(diskutil list | awk -v key=" $key " '/APFS Volume/ && $0 ~ key {print $NF}')    
        diskutil unmount /dev/$temp_var || echo "$key 的磁盘 $temp_var 卸载失败"
        sudo /sbin/mount_apfs /dev/$temp_var "$value"    
        sudo chmod 777 "$value"
    done
    
    echo "挂载和数据转移完成"
}

# 打开磁盘目录
open_disks() {
    check_disks || return 1
    
    echo "开始打开磁盘目录"

    for key value in "${(@kv)config}"; do    
        source_dir="/Volumes/$key"
        target_dir="$value"
        
        echo "打开Finder窗口: $source_dir 和 $target_dir"
        open -a Finder "$source_dir"
        open -a Finder "$target_dir"
    done
    
    echo "目录已打开"
}

# 恢复数据到原始位置
restore_data() {
    check_disks || return 1
    
    echo "开始恢复数据"

    files_to_move=()
    has_files_to_move=false

    for key value in "${(@kv)config}"; do
        source_dir="$value"
        target_dir="/Volumes/$key"
        
        echo "===== 检查文件 ($key) ====="
        
        found_files=false
        while IFS= read -r file; do
            if [[ -n "$file" ]]; then
                rel_path="${file#$target_dir/}"
                
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

    if [[ $has_files_to_move == true ]]; then
        read -q "REPLY?确认要移动上述文件吗？(y/n) "
        echo ""
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
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

    echo ""
    read -q "REPLY2?是否要清空目标目录（只删除内部文件，保留目录本身）? (y/n) "
    echo ""

    if [[ $REPLY2 =~ ^[Yy]$ ]]; then
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

# 主程序
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