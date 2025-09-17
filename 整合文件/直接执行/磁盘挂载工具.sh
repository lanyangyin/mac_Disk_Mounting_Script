#!/bin/zsh

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 初始化空关联数组
typeset -A config

# 函数：显示标题
show_title() {
    echo -e "${PURPLE}"
    echo "================================================"
    echo "           磁盘挂载工具 v1.0"
    echo "================================================"
    echo -e "${NC}"
}

# 函数：显示菜单
show_menu() {
    echo -e "${CYAN}请选择要执行的操作（可多选，用空格分隔）：${NC}"
    echo -e "  ${GREEN}1${NC}. 打开磁盘"
    echo -e "  ${GREEN}2${NC}. 复原磁盘默认挂载"
    echo -e "  ${GREEN}3${NC}. 挂载硬盘"
    echo -e "  ${GREEN}4${NC}. 移回数据"
    echo -e "  ${GREEN}5${NC}. 转移数据"
    echo -e "  ${GREEN}6${NC}. 转移数据并挂载磁盘"
    echo -e "  ${GREEN}0${NC}. 退出"
    echo -e "${CYAN}请输入选择（例如: 1 3 5）：${NC}"
}

# 函数：解析命令行参数
parse_arguments() {
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
                echo -e "${RED}未知参数: $1${NC}"
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
        echo -e "${RED}错误: 未提供任何配置参数${NC}"
        echo "用法: $0 -n 应用名称 -p 挂载路径 [-n 应用名称2 -p 挂载路径2 ...]"
        exit 1
    fi
}

# 函数：检查磁盘状态
check_disk_status() {
    echo -e "${BLUE}正在检查磁盘状态...${NC}"
    for key value in "${(@kv)config}"; do
        # 使用diskutil查找与key名称匹配的APFS卷
        temp_var=$(diskutil list | awk -v key=" $key " '/APFS Volume/ && $0 ~ key {print $NF}')
        temp_var_formatted=$(echo "$temp_var" | tr '\n' ';')

        # 统计找到的磁盘数量
        disk_count=$(echo "$temp_var" | grep -c "disk")

        # 检查是否找到多个同名磁盘卷
        if [ $disk_count -gt 1 ]; then
            echo -e "${YELLOW}⚠警告: $key 找到多个同名磁盘卷 $temp_var_formatted${NC}"
            return 1
        # 检查是否未找到磁盘卷
        elif [ $disk_count -eq 0 ]; then
            echo -e "${YELLOW}⚠警告: $key 未找到磁盘卷${NC}"
            return 1
        fi

        # 检查挂载点目录是否存在
        if [ ! -d "$value" ]; then
            echo -e "${YELLOW}⚠警告: $key 所对应的 $temp_var_formatted 的挂载点 $value 不存在${NC}"
            return 1
        fi

        # 输出找到的磁盘信息
        echo -e "${GREEN}$key: $value: $temp_var${NC}"
    done
    return 0
}

# 函数：卸载并重新挂载磁盘
remount_disks() {
    echo -e "${BLUE}正在重新挂载磁盘...${NC}"
    for key value in "${(@kv)config}"; do
        temp_var=$(diskutil list | awk -v key=" $key " '/APFS Volume/ && $0 ~ key {print $NF}')
        echo -e "${CYAN}正在卸载 $temp_var...${NC}"
        diskutil unmount /dev/$temp_var || echo -e "${YELLOW}$key 的磁盘 $temp_var 卸载失败${NC}"

        echo -e "${CYAN}正在重新挂载 $temp_var...${NC}"
        diskutil mount /dev/$temp_var

        # 等待2秒让系统完成挂载操作
        sleep 2
    done
}

# 函数：打开磁盘
open_disk() {
    echo -e "${PURPLE}执行操作: 打开磁盘${NC}"

    if ! check_disk_status; then
        return 1
    fi

    remount_disks

    echo -e "${GREEN}检查完毕${NC}"

    # 使用Finder打开每个磁盘卷和对应的目标目录
    for key value in "${(@kv)config}"; do
        source_dir="/Volumes/$key"
        target_dir="$value"

        echo -e "${CYAN}打开Finder窗口: $source_dir 和 $target_dir${NC}"
        open -a Finder "$source_dir"
        open -a Finder "$target_dir"
    done

    return 0
}

# 函数：复原磁盘默认挂载
restore_disk() {
    echo -e "${PURPLE}执行操作: 复原磁盘默认挂载${NC}"

    if ! check_disk_status; then
        return 1
    fi

    echo ""
    echo -e "${CYAN}即将复原默认挂载：${NC}"
    for key value in "${(@kv)config}"; do
        temp_var=$(diskutil list | awk -v key=" $key " '/APFS Volume/ && $0 ~ key {print $NF}')
        source_dir="/Volumes/$key"
        target_dir="$value"
        echo -e "   ${GREEN}$temp_var （ $target_dir ） --> $temp_var （ $source_dir ）${NC}"
    done
    echo ""

    remount_disks

    return 0
}

# 函数：挂载硬盘
mount_disk() {
    echo -e "${PURPLE}执行操作: 挂载硬盘${NC}"

    if ! check_disk_status; then
        return 1
    fi

    remount_disks

    echo -e "${GREEN}检查完毕${NC}"

    # 卸载磁盘并使用mount_apfs重新挂载到指定目录
    for key value in "${(@kv)config}"; do
        temp_var=$(diskutil list | awk -v key=" $key " '/APFS Volume/ && $0 ~ key {print $NF}')
        diskutil unmount /dev/$temp_var || echo -e "${YELLOW}$key 的磁盘 $temp_var 卸载失败${NC}"
        sudo /sbin/mount_apfs /dev/$temp_var "$value"
        sudo chmod 777 "$value"  # 设置目录权限为可读写
    done

    return 0
}

# 函数：移回数据
move_data_back() {
    echo -e "${PURPLE}执行操作: 移回数据${NC}"

    if ! check_disk_status; then
        return 1
    fi

    remount_disks

    echo -e "${GREEN}检查完毕${NC}"

    # 初始化变量用于跟踪需要复制的文件
    local files_to_copy=()
    local has_files_to_copy=false
    local copy_executed=false

    # 遍历配置，检查需要从磁盘卷恢复的文件
    for key value in "${(@kv)config}"; do
        source_dir="/Volumes/$key"
        target_dir="$value"

        echo -e "${CYAN}===== 检查文件 ($key) =====${NC}"

        local found_files=false
        # 查找磁盘卷中的所有文件
        while IFS= read -r file; do
            if [[ -n "$file" ]]; then
                rel_path="${file#$source_dir/}"

                # 检查源目录中是否不存在该文件
                if [[ ! -e "$target_dir/$rel_path" ]]; then
                    if [[ $found_files == false ]]; then
                        echo -e "${YELLOW}将要复制的文件:${NC}"
                        found_files=true
                        has_files_to_copy=true
                    fi
                    echo -e "  ${YELLOW}$rel_path${NC}"
                    files_to_copy+=("$file")
                fi
            fi
        done < <(find "$source_dir" -type f -print 2>/dev/null)

        if [[ $found_files == false ]]; then
            echo -e "${GREEN}没有需要复制的文件${NC}"
        fi

        echo ""
    done

    # 复制文件
    if [[ $has_files_to_copy == true ]]; then
        # 复制文件从磁盘卷到原始位置
        for key value in "${(@kv)config}"; do
            source_dir="/Volumes/$key"
            target_dir="$value"

            if [[ ! -d "$target_dir" || ! -d "$source_dir" ]]; then
                continue
            fi

            echo -e "${CYAN}正在复制文件: $key${NC}"

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

        echo -e "${GREEN}文件复制完成${NC}"
        copy_executed=true
    else
        copy_executed=true
    fi

    # 清空磁盘卷
    # 安全检查：确保复制操作已执行且源文件夹中所有文件都在目标文件夹中
    local safe_to_delete=true
    for key value in "${(@kv)config}"; do
        source_dir="/Volumes/$key"
        target_dir="$value"

        # 检查是否执行了复制步骤
        if [[ $copy_executed != true ]]; then
            echo -e "${RED}❌ 安全警告: 未执行复制步骤，不允许删除源文件夹中的文件${NC}"
            safe_to_delete=false
            break
        fi

        # 检查源文件夹中是否有文件不在目标文件夹中
        while IFS= read -r file; do
            if [[ -n "$file" ]]; then
                rel_path="${file#$source_dir/}"
                if [[ ! -e "$target_dir/$rel_path" ]]; then
                    echo -e "${RED}❌ 安全警告: 源文件夹中的文件 $rel_path 不在目标文件夹中，不允许删除${NC}"
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
                echo -e "${CYAN}正在清空目录: $target_dir${NC}"
                find "$target_dir" -mindepth 1 -delete 2>/dev/null
                echo -e "${GREEN}目录已清空: $target_dir${NC}"
            else
                echo -e "${YELLOW}目录不存在，跳过: $target_dir${NC}"
            fi
        done
        echo -e "${GREEN}所有目标目录已清空${NC}"
    else
        echo -e "${RED}❌ 已跳过清空目录操作 - 安全冗余检查失败${NC}"
    fi

    return 0
}

# 函数：转移数据
move_data() {
    echo -e "${PURPLE}执行操作: 转移数据${NC}"

    if ! check_disk_status; then
        return 1
    fi

    remount_disks

    echo -e "${GREEN}检查完毕${NC}"

    # 初始化变量用于跟踪需要复制的文件
    local files_to_copy=()
    local has_files_to_copy=false
    local copy_executed=false

    # 遍历配置，检查需要复制的文件
    for key value in "${(@kv)config}"; do
        source_dir="$value"
        target_dir="/Volumes/$key"

        echo -e "${CYAN}===== 检查文件 ($key) =====${NC}"

        local found_files=false
        # 使用find命令查找目标目录中的所有文件
        while IFS= read -r file; do
            if [[ -n "$file" ]]; then
                # 获取文件相对于目标目录的路径
                rel_path="${file#$source_dir/}"

                # 检查源目录中是否不存在该文件
                if [[ ! -e "$target_dir/$rel_path" ]]; then
                    if [[ $found_files == false ]]; then
                        echo -e "${YELLOW}将要复制的文件:${NC}"
                        found_files=true
                        has_files_to_copy=true
                    fi
                    echo -e "  ${YELLOW}$rel_path${NC}"
                    files_to_copy+=("$file")
                fi
            fi
        done < <(find "$source_dir" -type f -print 2>/dev/null)

        if [[ $found_files == false ]]; then
            echo -e "${GREEN}没有需要复制的文件${NC}"
        fi

        echo ""
    done

    # 复制文件
    if [[ $has_files_to_copy == true ]]; then
        # 开始将文件从源目录复制到磁盘卷
        for key value in "${(@kv)config}"; do
            source_dir="$value"
            target_dir="/Volumes/$key"

            # 检查目录是否存在
            if [[ ! -d "$target_dir" || ! -d "$source_dir" ]]; then
                continue
            fi

            echo -e "${CYAN}正在复制文件: $key${NC}"

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

        echo -e "${GREEN}文件复制完成${NC}"
        copy_executed=true
    else
        copy_executed=true
    fi

    # 清空目标目录
    # 安全检查：确保复制操作已执行且源文件夹中所有文件都在目标文件夹中
    local safe_to_delete=true
    for key value in "${(@kv)config}"; do
        source_dir="$value"
        target_dir="/Volumes/$key"

        # 检查是否执行了复制步骤
        if [[ $copy_executed != true ]]; then
            echo -e "${RED}❌ 安全警告: 未执行复制步骤，不允许删除源文件夹中的文件${NC}"
            safe_to_delete=false
            break
        fi

        # 检查源文件夹中是否有文件不在目标文件夹中
        while IFS= read -r file; do
            if [[ -n "$file" ]]; then
                rel_path="${file#$source_dir/}"
                if [[ ! -e "$target_dir/$rel_path" ]]; then
                    echo -e "${RED}❌ 安全警告: 源文件夹中的文件 $rel_path 不在目标文件夹中，不允许删除${NC}"
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
                echo -e "${CYAN}正在清空目录: $target_dir${NC}"
                find "$target_dir" -mindepth 1 -delete 2>/dev/null
                echo -e "${GREEN}目录已清空: $target_dir${NC}"
            else
                echo -e "${YELLOW}目录不存在，跳过: $target_dir${NC}"
            fi
        done
        echo -e "${GREEN}所有目标目录已清空${NC}"
    else
        echo -e "${RED}❌ 已跳过清空目录操作 - 安全冗余检查失败${NC}"
    fi

    return 0
}

# 函数：转移数据并挂载磁盘
move_data_and_mount() {
    echo -e "${PURPLE}执行操作: 转移数据并挂载磁盘${NC}"

    if ! check_disk_status; then
        return 1
    fi

    remount_disks

    echo -e "${GREEN}检查完毕${NC}"

    # 初始化变量用于跟踪需要复制的文件
    local files_to_copy=()
    local has_files_to_copy=false
    local copy_executed=false

    # 遍历配置，检查需要复制的文件
    for key value in "${(@kv)config}"; do
        source_dir="$value"
        target_dir="/Volumes/$key"

        echo -e "${CYAN}===== 检查文件 ($key) =====${NC}"

        local found_files=false
        # 使用find命令查找目标目录中的所有文件
        while IFS= read -r file; do
            if [[ -n "$file" ]]; then
                # 获取文件相对于目标目录的路径
                rel_path="${file#$source_dir/}"

                # 检查源目录中是否不存在该文件
                if [[ ! -e "$target_dir/$rel_path" ]]; then
                    if [[ $found_files == false ]]; then
                        echo -e "${YELLOW}将要复制的文件:${NC}"
                        found_files=true
                        has_files_to_copy=true
                    fi
                    echo -e "  ${YELLOW}$rel_path${NC}"
                    files_to_copy+=("$file")
                fi
            fi
        done < <(find "$source_dir" -type f -print 2>/dev/null)

        if [[ $found_files == false ]]; then
            echo -e "${GREEN}没有需要复制的文件${NC}"
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

            echo -e "${CYAN}正在复制文件: $key${NC}"

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

        echo -e "${GREEN}文件复制完成${NC}"
        copy_executed=true
    else
        copy_executed=true
    fi

    # 清空目标目录
    # 安全检查：确保复制操作已执行且源文件夹中所有文件都在目标文件夹中
    local safe_to_delete=true
    for key value in "${(@kv)config}"; do
        source_dir="$value"
        target_dir="/Volumes/$key"

        # 检查是否执行了复制步骤
        if [[ $copy_executed != true ]]; then
            echo -e "${RED}❌ 安全警告: 未执行复制步骤，不允许删除源文件夹中的文件${NC}"
            safe_to_delete=false
            break
        fi

        # 检查源文件夹中是否有文件不在目标文件夹中
        while IFS= read -r file; do
            if [[ -n "$file" ]]; then
                rel_path="${file#$source_dir/}"
                if [[ ! -e "$target_dir/$rel_path" ]]; then
                    echo -e "${RED}❌ 安全警告: 源文件夹中的文件 $rel_path 不在目标文件夹中，不允许删除${NC}"
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
                echo -e "${CYAN}正在清空目录: $target_dir${NC}"
                find "$target_dir" -mindepth 1 -delete 2>/dev/null
                echo -e "${GREEN}目录已清空: $target_dir${NC}"
            else
                echo -e "${YELLOW}目录不存在，跳过: $target_dir${NC}"
            fi
        done
        echo -e "${GREEN}所有目标目录已清空${NC}"
    else
        echo -e "${RED}❌ 已跳过清空目录操作 - 安全冗余检查失败${NC}"
    fi

    # 卸载磁盘并使用mount_apfs重新挂载到指定目录
    for key value in "${(@kv)config}"; do
        temp_var=$(diskutil list | awk -v key=" $key " '/APFS Volume/ && $0 ~ key {print $NF}')
        diskutil unmount /dev/$temp_var || echo -e "${YELLOW}$key 的磁盘 $temp_var 卸载失败${NC}"
        sudo /sbin/mount_apfs /dev/$temp_var "$value"
        sudo chmod 777 "$value"  # 设置目录权限为可读写
    done

    return 0
}

# 主程序
main() {
    # 解析命令行参数
    parse_arguments "$@"

    while true; do
        show_title
        show_menu

        read -r choices
        choices=(${=choices}) # 将输入拆分为数组

        # 处理退出选项
        if [[ ${choices[(ie)0]} -le ${#choices} ]]; then
            echo -e "${GREEN}感谢使用，再见！${NC}"
            exit 0
        fi

        # 执行选中的操作
        for choice in $choices; do
            case $choice in
                1)
                    open_disk
                    ;;
                2)
                    restore_disk
                    ;;
                3)
                    mount_disk
                    ;;
                4)
                    move_data_back
                    ;;
                5)
                    move_data
                    ;;
                6)
                    move_data_and_mount
                    ;;
                *)
                    echo -e "${RED}无效选项: $choice${NC}"
                    continue
                    ;;
            esac

            # 检查操作是否成功
            if [[ $? -ne 0 ]]; then
                echo -e "${RED}操作执行失败！${NC}"
            else
                echo -e "${GREEN}操作执行成功！${NC}"
            fi

            echo ""
        done

        # 询问是否继续
        echo -e "${CYAN}是否继续执行其他操作？(y/n): ${NC}"
        read -r continue_choice
        if [[ "$continue_choice" != "y" && "$continue_choice" != "Y" ]]; then
            echo -e "${GREEN}感谢使用，再见！${NC}"
            break
        fi
    done
}

# 启动主程序
main "$@"