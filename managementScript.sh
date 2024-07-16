#!/bin/bash

#MIT License
#Copyright (c) 2024, Arkadiusz Asmus
#

#CREATING FILE WITH LOGS
touch skrypt.log
source config.rc

# CHECK IF THE USER RAN THE SCRIPT AS ROOT
if [ "$EUID" -ne 0 ]; then
    echo "Run this script as root."
    exit 1
fi

# Check if the 'dialog' command is available
if ! command -v dialog &> /dev/null; then
    # Display the installation message stored in $INSTALL_DIALOG_MSG
    echo "$INSTALL_DIALOG_MSG"
    
    # Prompt the user to install 'dialog'
    read -r install_dialog
    if [ "$install_dialog" == "y" ]; then
        # Update package repositories and install 'dialog' silently (-y)
        apt-get update
        apt-get install -y dialog
    else
        # If the user chooses not to install 'dialog', exit with an error message
        echo "Cannot continue without dialog."
        exit 1
    fi
fi

if ! command -v zenity &> /dev/null; then
    echo "$INSTALL_ZENITY_MSG"
    read -r install_zenity
    if [ "$install_zenity" == "y" ]; then
        apt-get update
        apt-get install -y zenity
    else
        echo "Cannot continue without zenity."
        exit 1
    fi
fi

# SAVING LOGS TO A FILE WITH EXECUTION DATE
log_action() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") - $1" >> "$LOG_FILE"
}

log_action "Script started."

# CHECKING IF SYSTEMCTL IS INSTALLED
check_systemctl() {
    if ! command -v systemctl &> /dev/null; then
        echo "$INSTALL_SYSTEMCTL_MSG"
        read -r install_systemctl
        if [ "$install_systemctl" == "y" ]; then
            apt-get update
            apt-get install -y systemd
        else
            echo "Cannot proceed without systemctl."
            exit 1
        fi
    fi
}

# FUNCTION TO RETURN INSTALLED PACKAGES ON THE COMPUTER
list_installed_packages() {
    log_action "Called list_installed_packages function."
    package_name=$(dialog --inputbox "Enter the package name or part of the name to search (leave blank to display all installed packages):" 10 60 3>&1 1>&2 2>&3 3>&-)
    clear
    if [ -z "$package_name" ]; then
        dpkg --get-selections | less
    else
        if dpkg-query -W -f='${Status}' "$package_name" 2>/dev/null | grep -q "install ok installed"; then
            dpkg --get-selections | grep "$package_name" | less
        else
            dialog --yesno "Package $package_name is not installed. Do you want to install it?" 10 60
            response=$?
            if [ $response -eq 0 ]; then
                apt-get update
                apt-get install -y "$package_name"
            else
                dialog --msgbox "Package $package_name does not exist in the repositories." 10 60
            fi
        fi
    fi
    ask_another_task
}


# FUNCTION TO CHECK WHEN A PACKAGE WAS LAST ACCESSED; IF NOT USED IN 15 DAYS, USER CAN CHOOSE TO REMOVE IT
last_accessed_days() {
    log_action "Called last_accessed_days function."
    PACKAGE=$(dialog --inputbox "Enter the package name:" 10 60 3>&1 1>&2 2>&3 3>&-)
    clear
    if [ -z "$PACKAGE" ]; then
        dialog --msgbox "No package name provided." 10 60
        return 1
    fi
    FILES=$(dpkg -L "$PACKAGE")
    output=""
    for FILE in $FILES; do
        if [ -x "$FILE" ]; then
            LAST_ACCESS=$(stat -c %X "$FILE")
            CURRENT_TIME=$(date +%s)
            DIFF_SECONDS=$((CURRENT_TIME - LAST_ACCESS))
            DIFF_DAYS=$((DIFF_SECONDS / 86400))
            output+="File: $FILE - Last accessed: $DIFF_DAYS days ago\n"
        fi
    done
    echo -e "$output"
    read -p "Press Enter to continue..."
    all_over_15_days=true
    while read -r line; do
        if [[ $line =~ [0-9]+ ]]; then
            days=${BASH_REMATCH[0]}
            if [ "$days" -le 15 ]; then
                all_over_15_days=false
                break
            fi
        fi
    done <<< "$output"

    if $all_over_15_days; then
        dialog --yesno "The package has not been used for over 15 days. Do you want to remove it?" 10 60
        response=$?
        if [ $response -eq 0 ]; then
            apt remove "$PACKAGE"
            dialog --msgbox "Package $PACKAGE has been removed." 10 60
        else
            dialog --msgbox "Package $PACKAGE was not removed." 10 60
        fi
    else
        dialog --msgbox "Package $PACKAGE has been used recently." 10 60
    fi
    ask_another_task
}

# FUNCTION TO CHECK FOR AVAILABLE UPDATES FOR USER-SPECIFIED PACKAGES
check_updates() {
    log_action "Called check_updates function."
    package_names=$(dialog --inputbox "Enter package names or fragments separated by commas to check for updates:" 10 60 3>&1 1>&2 2>&3 3>&-)
    clear
    if [ -z "$package_names" ]; then
        dialog --msgbox "Enter package names or fragments to check for updates." 10 60
    else
        IFS=',' read -r -a packages <<< "$package_names"
        updates_found=false
        for package_name in "${packages[@]}"; do
            if dpkg-query -W -f='${Status}' "$package_name" 2>/dev/null | grep -q "install ok installed"; then
                current_version=$(dpkg -l "$package_name" | awk 'NR==6 {print $3}')
                latest_version=$(apt-cache policy "$package_name" | grep Candidate | awk '{print $2}')
                if [ "$current_version" != "$latest_version" ]; then
                    updates_found=true
                    dialog --yesno "Updates available for package $package_name. Do you want to install them?" 10 60
                    response=$?
                    if [ $response -eq 0 ]; then
                        apt-get update
                        apt-get install -y "$package_name"
                    else
                        dialog --msgbox "Update for package $package_name was cancelled." 10 60
                    fi
                fi
            else
                dialog --msgbox "Package $package_name is not installed." 10 60
            fi
        done
        if [ "$updates_found" = false ]; then
            dialog --msgbox "No updates available for the specified packages." 10 60
        fi
    fi
    ask_another_task
}

# FUNCTION TO FIND INACTIVE APPLICATION FILES AND MANAGE THEM
find_inactive_apps() {
    log_action "Called find_inactive_apps function."
    days=$DAYS_TO_CHECK
    clear
    if ! [[ "$days" =~ ^[0-9]+$ ]]; then
        dialog --msgbox "Enter a valid number of days." 10 60
        ask_another_task
        return
    fi
    menu_choice=$(dialog --menu "Select the type of files to search:" 15 60 3 \
        1 "Executable files only (extensions with executable files)" \
        2 "All files" 3>&1 1>&2 2>&3 3>&-)
    clear
    case $menu_choice in
        1)
            file_pattern="*.{exe,com,bat,dll,jar,msi,vbs}"
            ;;
        2)
            file_pattern="*"
            ;;
        *)
            dialog --msgbox "Invalid choice. Run the script again." 10 60
            ask_another_task
            return
            ;;
    esac

    dir_choice=$(dialog --menu "Select the directory to search:" 15 60 4 \
        1 "Default directories (/usr/bin /usr/sbin /bin /sbin)" \
        2 "Choose directory" 3>&1 1>&2 2>&3 3>&-)
    clear
    case $dir_choice in
        1)
            search_dirs="/usr/bin /usr/sbin /bin /sbin"
            ;;
        2)
            search_dirs=$(zenity --file-selection --directory --title="Select a directory to search")
            ;;
        *)
            dialog --msgbox "Invalid choice. Run the script again." 10 60
            ask_another_task
            return
            ;;
    esac

    inactive_files=$(find $search_dirs -type f -name "$file_pattern" -atime +"$days" -exec stat -c "%n %X" {} + 2>/dev/null)
    if [ -z "$inactive_files" ]; then
        dialog --msgbox "No inactive files/programs found in the last $days days." 10 60
    else
        result="Inactive files/programs found in the last $days days:\n\n"
        while read -r line; do
            file=$(echo "$line" | cut -d ' ' -f1)
            last_access=$(echo "$line" | cut -d ' ' -f2)
            days_since_access=$(( ( $(date +%s) - last_access ) / 86400 ))
            result+="File: $file, Days since last access: $days_since_access\n"
        done <<< "$inactive_files"
        dialog --msgbox "$result" 20 60
        read -p "Enter file/program names to remove (space-separated): " files_to_remove
        if [ -n "$files_to_remove" ]; then
            for file in $files_to_remove; do
                if [ -e "$file" ]; then
                    rm "$file" && dialog --msgbox "File/program $file has been removed." 10 60
                else
                    dialog --msgbox "File/program $file does not exist or cannot be removed." 10 60
                fi
            done
        else
            dialog --msgbox "No file/program names provided for removal." 10 60
        fi
    fi
    ask_another_task
}

# FUNCTION TO DISPLAY INSTALLED UTILITY PROGRAMS
list_installed_utilities() {
    log_action "Called list_installed_utilities function."
    utilities=$(dpkg-query -W -f='${Package} ${Installed-Date}\n' | sort)
  
    if [ -z "$utilities" ]; then
        echo "No installed utility programs."
    else
        echo "Installed utility programs:"
        echo "$utilities"
        echo "$utilities" > /var/tmp/package_files.txt

        read -p "Select a utility program: " selected_utility
        if [ -n "$selected_utility" ]; then
            if ! dpkg -l "$selected_utility" &> /dev/null; then
                dialog --msgbox "Utility program $selected_utility does not exist." 10 60
                ask_another_task
            fi

            dialog --infobox "Selected utility program: $selected_utility" 5 40
            dialog --menu "What do you want to do with $selected_utility?" 15 60 4 \
                1 "Remove" \
                2 "Update" \
                3 "Change directory location" \
                4 "Check last run" --stdout > /tmp/option_choice.txt

            choice=$?
            case $choice in
                0)
                    option_choice=$(cat /tmp/option_choice.txt)
                    case $option_choice in
                        1)
                            apt-get remove --purge "$selected_utility"
                            ;;
                        2)
                            apt-get update
                            apt-get install --only-upgrade "$selected_utility"
                            ;;
                        3)
                            new_directory=$(zenity --file-selection --directory --title="Select a new location for $selected_utility")
                            if [ -n "$new_directory" ]; then
                                if [ -d "$new_directory" ]; then
                                    dpkg -L "$selected_utility" | xargs -I{} mv {} "$new_directory"
                                    dialog --msgbox "Changed directory location for $selected_utility." 10 60
                                else
                                    dialog --msgbox "The specified directory does not exist." 10 60
                                fi
                            else
                                dialog --msgbox "No new location selected." 10 60
                            fi
                            ;;
                        4)
                            last_run=$(stat -c %X "$(which "$selected_utility")" 2>/dev/null)
                            if [ -n "$last_run" ]; then
                                current_time=$(date +%s)
                                seconds_since_last_run=$((current_time - last_run))
                                days_since_last_run=$(( seconds_since_last_run / 86400 ))
                                if [ $days_since_last_run -gt 0 ]; then
                                    dialog --msgbox "Utility program $selected_utility was last run: $days_since_last_run days ago." 10 60
                                else
                                    dialog --msgbox "Utility program $selected_utility was last run: today." 10 60
                                fi
                            else
                                dialog --msgbox "Cannot find utility program $selected_utility." 10 60
                            fi
                            ;;
                        *)
                            dialog --msgbox "Invalid choice." 10 60
                            ;;
                    esac
                    ;;
                1)
                    dialog --msgbox "Cancelled." 10 60
                    ;;
                *)
                    dialog --msgbox "Invalid choice." 10 60
                    ;;
            esac
        fi
    fi

    rm -f /var/tmp/package_files.txt

    ask_another_task
}

# AFTER EACH FUNCTION ENDS, ASK IF THE USER WANTS TO PERFORM ANOTHER OPERATION
ask_another_task() {
    log_action "Called ask_another_task function."
    dialog --yesno "Do you want to perform another operation?" 10 60
    response=$?
    rm -f /tmp/option_choice.txt /tmp/package_files.txt
    if [ $response -eq 0 ]; then
        main_menu
    else
        dialog --msgbox "Operation completed." 10 60
        exit 0
    fi
}

# DISPLAY ACTIVE OR ALL SERVICES ON THE COMPUTER
list_active_services() {
    log_action "Called list_active_services function."
    check_systemctl
    dialog --yesno "Do you want to display only active services?" 10 60
    response=$?
    clear
    if [ $response -eq 0 ]; then
        systemctl list-units --type=service --state=active | awk '{print $1, $2, $3, $4}' | tail -n +2 | column -t
    else
        systemctl list-units --type=service | awk '{print $1, $2, $3, $4}' | tail -n +2 | column -t
    fi
    manage_service
}

# INVOKES THE SERVICE MANAGEMENT MENU
manage_service() {
    log_action "Called manage_service function."
    local service_name=""
    while [ -z "$service_name" ]; do
        read -p "Enter the service name you want to manage: " service_name
        if ! systemctl list-unit-files --type=service | grep -q "\<$service_name\>"; then
            echo "Service $service_name does not exist."
            read -p "Press Enter to continue..."
            manage_service
        fi
    done
    
    dialog --menu "What do you want to do with service $service_name?" 15 60 6 \
        1 "Restart" \
        2 "Stop" \
        3 "Show detailed description" \
        4 "Enable automatic startup on boot" \
        5 "Reload configuration without stopping" \
        6 "Back to main menu" --stdout > /tmp/service_option_choice.txt

    option_choice=$(cat /tmp/service_option_choice.txt)

    case $option_choice in
        1)
            systemctl restart "$service_name"
            read -p "Press Enter to continue..."
            ask_another_task
            ;;
        2)
            systemctl stop "$service_name"
            read -p "Press Enter to continue..."
            ask_another_task
            ;;
        3)
            show_desc_service "$service_name"
            ;;
        4)
            systemctl enable "$service_name"
            read -p "Press Enter to continue..."
            ask_another_task
            ;;
        5)
            systemctl reload "$service_name"
            read -p "Press Enter to continue..."
            ask_another_task
            ;;
        6)
            main_menu
            ;;
        *)
            echo "Operation completed."
            ;;
    esac
}

# STARTS A NEW SERVICE PROVIDED BY THE USER
start_new_service() {
    log_action "Called start_new_service function."
    valid_services=$(systemctl list-unit-files --type=service | awk '{print $1}' | tail -n +2)
    
    while true; do
        dialog --inputbox "Enter the name of the new service to start:" 10 60 3>&1 1>&2 2>&3 3>&-
        new_service=$?
        clear
        if [ $new_service -eq 0 ]; then
            if echo "$valid_services" | grep -qw "$new_service"; then
                systemctl start "$new_service"
                dialog --msgbox "Service $new_service has been started." 10 60
                break
            else
                dialog --msgbox "The entered service name is invalid." 10 60
            fi
        else
            break
        fi
    done
}

# DISPLAYS SERVICE DESCRIPTION
show_desc_service() {
    log_action "Called show_desc_service function."
    local service_name="$1"
    if [ -n "$service_name" ]; then
        if systemctl list-unit-files --type=service | grep -q "\<$service_name\>"; then
            echo "Detailed information about service $service_name:"
            systemctl show "$service_name" | less
            echo "Press Enter to return to the menu."
        else
            echo "Service $service_name does not exist."
        fi
    else
        echo "No service name provided."
    fi
}

# DISPLAY SERVICES STARTED AT SYSTEM BOOT
startup_services() {
    log_action "Called startup_services function."
    local services_info
    services_info=$(systemctl list-unit-files --type=service | grep enabled | awk '{printf "%-3s%-40s%s\n", NR, $1, $2}')

    if [ -z "$services_info" ]; then
        echo "No services started at system boot."
        read -p "Press Enter to continue..."
        return
    fi

    while true; do
        clear
        echo "Services started at system boot:"
        echo "---------------------------------"
        echo "Nr  Service Name                         Status"
        echo "---------------------------------"
        echo "$services_info"
        echo "---------------------------------"
        echo "Select the service number to manage (or press Enter to exit):"
        read -p "Service number: " selected_service_num

        if [ -z "$selected_service_num" ]; then
            break
        fi

        selected_service=$(echo "$services_info" | sed -n "${selected_service_num}p" | awk '{print $2}')
        selected_status=$(echo "$services_info" | sed -n "${selected_service_num}p" | awk '{print $3}')

        clear
        config_choice=$(dialog --menu "What do you want to do with service $selected_service?" 15 60 5 \
            1 "Enable" \
            2 "Disable" \
            3 "Start with delay" \
            4 "Back" --stdout)

        case $config_choice in
            1)
                systemctl enable "$selected_service"
                ;;
            2)
                systemctl disable "$selected_service"
                ;;
            3)
                create_delayed_service "$selected_service"
                ;;
            4)
                main_menu
                ;;
            *)
                echo "Unknown option."
                main_menu
                ;;
        esac

        read -p "Press Enter to continue..."
    done
    ask_another_task
}

# START SERVICES AT BOOT WITH DELAY (IN SECONDS)
create_delayed_service() {
    log_action "Called create_delayed_service function."
    local service_name="$1"

    delay_time=$(zenity --entry --title="Service Delay" --text="Enter delay time in seconds:")
    clear
    if ! [[ "$delay_time" =~ ^[0-9]+$ ]]; then
        zenity --error --text="Please enter a valid number of seconds."
        return
    fi

    local timer_unit="$service_name-delay.timer"
    local service_unit="$service_name-delay.service"

    cat << EOF | sudo tee "/etc/systemd/system/$timer_unit" > /dev/null
[Unit]
Description=Timer for delaying the start of $service_name

[Timer]
OnBootSec=$delay_time
OnUnitActiveSec=1h

[Install]
WantedBy=timers.target
EOF

    cat << EOF | sudo tee "/etc/systemd/system/$service_unit" > /dev/null
[Unit]
Description=Delayed start of $service_name
Requires=$timer_unit

[Service]
Type=oneshot
ExecStart=/bin/systemctl start $service_name

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable "$timer_unit"
    zenity --info --text="Timer and service for $service_name have been created and enabled."
}

# SHOW APPLICATIONS MENU
show_apps_menu() {
    app_choice=$(dialog --menu "What do you want to do?" 15 60 4 \
        1 "List installed packages" \
        2 "List installed utilities" \
        3 "Find inactive applications" \
        4 "Check updates for selected applications/programs" \
        5 "Find inactive files" 3>&1 1>&2 2>&3 3>&-)
  
    clear
  
    case $app_choice in
        1)
            list_installed_packages
            ;;
        2)
            list_installed_utilities
            ;;
        3)
            last_accessed_days
            ;;
        4)
            check_updates
            ;;
        5)
            find_inactive_apps
            ;;
        *)
            dialog --msgbox "Operation completed." 10 60
            ask_another_task
            ;;
    esac
}

# SHOW SERVICES MENU
show_services_menu() {
    service_choice=$(dialog --menu "What do you want to do?" 15 60 2 \
        1 "Display active services" \
        2 "Start a new service" \
        3 "Services started at system boot" 3>&1 1>&2 2>&3 3>&-)
  
    clear
  
    case $service_choice in
        1)
            list_active_services
            ;;
        2)
            start_new_service
            ;;
        3)
            startup_services
            ;;
        *)
            dialog --msgbox "Operation completed." 10 60
            ask_another_task
            ;;
    esac
}

# MAIN MENU FUNCTION
main_menu() {
    while getopts ":avuh" opt; do
        case ${opt} in
            a)
                show_apps_menu
                ;;
            u)
                show_services_menu
                ;;
            v)
                echo "Version 1.0, author: [Arkadiusz Asmus 200797]"
                ;;
            h)
                echo "Usage: $0 [-a] [-u] [-v] [-h]"
                echo "  -a: Display applications/programs menu."
                echo "  -u: Display services menu."
                echo "  -v: Script version and author."
                echo "  -h: Help window."
                exit 0
                ;;
            \?)
                echo "Error: Invalid option: $OPTARG" >&2
                ;;
        esac
    done

    if [[ $OPTIND -eq 1 ]]; then
        choice=$(dialog --menu "What do you want to do?" 15 60 2 \
            1 "Manage applications/programs" \
            2 "Manage services" 3>&1 1>&2 2>&3 3>&-)
      
        clear
      
        case $choice in
            1)
                show_apps_menu
                ;;
            2)
                show_services_menu
                ;;
            *)
                dialog --msgbox "Operation completed." 10 60
                exit 1
                ;;
        esac
    fi

    rm -f /tmp/option_choice.txt /tmp/package_files.txt
}

main_menu "$@"
log_action "Script finished."
rm -f /tmp/option_choice.txt /tmp/package_files.txt
