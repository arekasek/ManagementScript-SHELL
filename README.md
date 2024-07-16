![obraz](https://github.com/user-attachments/assets/a3deed44-30c4-4214-b676-8ecee260ff1a)
![Zrzut ekranu z 2024-07-16 03-37-59](https://github.com/user-attachments/assets/9dc6ea40-d09a-4d2d-88c7-690770ec0fdb)


# System Administration Script

This script is designed to assist with system administration tasks on Debian-based Linux systems. It provides interactive menus for managing applications and services, checking for updates, and performing maintenance tasks.

## Features

- **Application Management:**
  - List installed packages
  - List installed utilities
  - Find inactive applications
  - Check updates for selected applications/programs
  - Find and manage inactive files

- **Service Management:**
  - Display active services
  - Start a new service
  - Manage services started at system boot

## Prerequisites

- **Root Access:** Ensure you run the script with root privileges (`sudo`).
- **Dependencies:** The script relies on `dialog` and `zenity` for user interface components. If not already installed, the script will attempt to install them.

## Usage

### Running the Script

```bash 
sudo ./system_admin.sh [-a] [-u] [-v] [-h]
```
## Options

- **-a**: Display the applications/programs menu.
- **-u**: Display the services menu.
- **-v**: Show script version and author information.
- **-h**: Display help information.

## Example

To manage applications:

```bash
sudo ./system_admin.sh -a
```

## Notes

- The script creates a `skrypt.log` file to log its activities.
- Ensure you have reviewed and adjusted the `config.rc` file for your specific environment before running the script.

## Before Use

Before using this script, please ensure you have reviewed the [manual](./managementScript.1) for detailed instructions on its features and options.


[![MIT License](https://img.shields.io/badge/License-MIT-green.svg)](https://choosealicense.com/licenses/mit/)


