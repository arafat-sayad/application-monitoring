#!/bin/bash

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
DEFAULT_VM_NAME="VirtualBox-Server"
VM_CPUS=2
VM_MEM=4096
VM_DISK=51200
TEMP_ISO_MAP="${HOME}/.vbox_iso_map.tmp"

# Set paths based on whether we're running with sudo
if [ "$(id -u)" -eq 0 ] && [ -n "$SUDO_USER" ]; then
    ISO_DIR="/home/$SUDO_USER/vbox-isos"
    VM_DIR="/home/$SUDO_USER/VirtualBox-VMs"
else
    ISO_DIR="$HOME/vbox-isos"
    VM_DIR="$HOME/VirtualBox-VMs"
fi

# Available ISO downloads
declare -A ISO_URLS=(
    ["1"]="https://releases.ubuntu.com/24.04/ubuntu-24.04.2-live-server-amd64.iso"
    ["2"]="https://releases.ubuntu.com/22.04/ubuntu-22.04.5-live-server-amd64.iso"
    ["3"]="https://releases.ubuntu.com/20.04/ubuntu-20.04.6-live-server-amd64.iso"
    ["4"]="https://releases.ubuntu.com/18.04/ubuntu-18.04.6-live-server-amd64.iso"
    ["5"]="https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.5.0-amd64-netinst.iso"
    ["6"]="https://download.rockylinux.org/pub/rocky/9/isos/x86_64/Rocky-9.3-x86_64-minimal.iso"
)

# Function to ensure proper permissions
ensure_permissions() {
    # When running as root via sudo
    if [ "$(id -u)" -eq 0 ]; then
        if [ -z "$SUDO_USER" ]; then
            echo -e "${RED}Error: Please run this script with sudo, not as root${NC}"
            exit 1
        fi
        
        # Set correct home directory
        USER_HOME="/home/$SUDO_USER"
        
        # Ensure directories exist with correct permissions
        mkdir -p "$USER_HOME/vbox-isos" "$USER_HOME/VirtualBox-VMs"
        chown -R "$SUDO_USER":"$SUDO_USER" "$USER_HOME/vbox-isos" "$USER_HOME/VirtualBox-VMs"
        
        # Set VirtualBox machine folder to user's directory
        run_as_user VBoxManage setproperty machinefolder "$USER_HOME/VirtualBox-VMs"
    else
        # When running as regular user
        mkdir -p "$ISO_DIR" "$VM_DIR"
    fi
}

# Function to run commands as the original user
run_as_user() {
    if [ "$(id -u)" -eq 0 ] && [ -n "$SUDO_USER" ]; then
        sudo -u "$SUDO_USER" "$@"
    else
        "$@"
    fi
}

# Function to run with sudo only when needed
run_with_sudo() {
    if [ "$(id -u)" -ne 0 ]; then
        sudo "$@"
    else
        "$@"
    fi
}

# Function to detect network bridge adapter
get_bridge_adapter() {
    BRIDGE_ADAPTER=$(ip link show | grep -o '^[0-9]\+: [^: ]\+' | awk '{print $2}' | grep -v lo | head -n 1)
    if [ -z "$BRIDGE_ADAPTER" ]; then
        echo -e "${RED}No network adapter found for bridge networking${NC}"
        exit 1
    fi
    echo "$BRIDGE_ADAPTER"
}

# Function to display menu
show_menu() {
    clear
    echo -e "${CYAN}============================================${NC}"
    echo -e "${CYAN}        VirtualBox VM Setup Wizard          ${NC}"
    echo -e "${CYAN}============================================${NC}"
    echo
}

# Function to get VM name from user
get_vm_name() {
    show_menu
    echo -e "${BLUE}Virtual Machine Configuration${NC}"
    echo
    read -p "Enter VM name [$DEFAULT_VM_NAME]: " VM_NAME
    VM_NAME=${VM_NAME:-$DEFAULT_VM_NAME}
    
    # Validate VM name
    if [[ ! "$VM_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo -e "${RED}Invalid VM name. Only letters, numbers, hyphens and underscores are allowed.${NC}"
        sleep 2
        get_vm_name
    fi
    
    # Check if VM already exists
    if run_as_user VBoxManage list vms | grep -q "\"$VM_NAME\""; then
        echo -e "${YELLOW}VM '$VM_NAME' already exists. Please choose a different name.${NC}"
        sleep 2
        get_vm_name
    fi
}

# Function to check VirtualBox installation
check_virtualbox() {
    echo -e "${BLUE}Checking VirtualBox installation...${NC}"
    if command -v vboxmanage >/dev/null 2>&1; then
        VERSION=$(vboxmanage --version)
        echo -e "${GREEN}VirtualBox already installed (version $VERSION)${NC}"
        return 0
    else
        echo -e "${YELLOW}VirtualBox not found, will install${NC}"
        return 1
    fi
}

# Function to install VirtualBox
install_virtualbox() {
    echo -e "${BLUE}Installing VirtualBox...${NC}"
    
    # Add repository
    echo -e "${YELLOW}Adding VirtualBox repository...${NC}"
    run_with_sudo apt-get update
    run_with_sudo apt-get install -y software-properties-common apt-transport-https wget
    wget -q https://www.virtualbox.org/download/oracle_vbox_2016.asc -O- | run_with_sudo apt-key add -
    wget -q https://www.virtualbox.org/download/oracle_vbox.asc -O- | run_with_sudo apt-key add -
    run_with_sudo add-apt-repository "deb [arch=amd64] https://download.virtualbox.org/virtualbox/debian $(lsb_release -cs) contrib"
    
    # Install VirtualBox
    echo -e "${YELLOW}Installing packages...${NC}"
    run_with_sudo apt-get update
    run_with_sudo apt-get install -y virtualbox-7.0
    
    # Setup kernel modules (requires root)
    echo -e "${YELLOW}Setting up kernel modules...${NC}"
    run_with_sudo /sbin/vboxconfig
    
    # Verify installation
    if command -v vboxmanage >/dev/null 2>&1; then
        echo -e "${GREEN}VirtualBox installed successfully${NC}"
    else
        echo -e "${RED}VirtualBox installation failed${NC}"
        exit 1
    fi
}

# Function to download ISO
download_iso() {
    local choice=$1
    local url="${ISO_URLS[$choice]}"
    local filename=$(basename "$url")
    
    echo -e "${YELLOW}Downloading $filename...${NC}"
    
    mkdir -p "$ISO_DIR"
    chown "$SUDO_USER":"$SUDO_USER" "$ISO_DIR" 2>/dev/null || true
    if wget -O "$ISO_DIR/$filename.tmp" "$url"; then
        mv "$ISO_DIR/$filename.tmp" "$ISO_DIR/$filename"
        chown "$SUDO_USER":"$SUDO_USER" "$ISO_DIR/$filename" 2>/dev/null || true
        echo -e "${GREEN}Successfully downloaded $filename${NC}"
        ISO_FILE="$filename"
        return 0
    else
        echo -e "${RED}Failed to download $filename${NC}"
        return 1
    fi
}

# Function to select ISO
select_iso() {
    while true; do
        show_menu
        echo -e "${BLUE}ISO Selection Menu${NC}"
        echo
        
        # List existing ISOs with L prefix
        echo -e "${BLUE}Existing ISO files in $ISO_DIR:${NC}"
        local i=1
        declare -A local_iso_map
        shopt -s nullglob
        for iso in "$ISO_DIR"/*.iso; do
            iso_name=$(basename "$iso")
            local_iso_map["$i"]="$iso"
            echo -e "  ${CYAN}L$i)${NC} $iso_name"
            ((i++))
        done
        shopt -u nullglob
        
        if [ "$i" -eq 1 ]; then
            echo -e "${YELLOW}No existing ISOs found.${NC}"
        fi
        
        # List download options with D prefix
        echo
        echo -e "${BLUE}Available ISO downloads:${NC}"
        for key in "${!ISO_URLS[@]}"; do
            url="${ISO_URLS[$key]}"
            filename=$(basename "$url")
            echo -e "  ${CYAN}D$key)${NC} $filename"
        done
        
        echo
        echo -e "  ${CYAN}0)${NC} Exit"
        echo
        read -p "Select an existing ISO (L#) or choose to download (D#), 0 to exit: " choice
        
        case $choice in
            0)
                echo -e "${YELLOW}Exiting...${NC}"
                exit 0
                ;;
            L[1-9]*)
                local num=${choice#L}
                if [ -n "${local_iso_map[$num]}" ]; then
                    ISO_FILE=$(basename "${local_iso_map[$num]}")
                    echo -e "${GREEN}Selected ISO: $ISO_FILE${NC}"
                    return
                else
                    echo -e "${RED}Invalid selection${NC}"
                    sleep 1
                fi
                ;;
            D[1-9]*)
                local num=${choice#D}
                if [ -n "${ISO_URLS[$num]}" ]; then
                    download_iso "$num"
                    return
                else
                    echo -e "${RED}Invalid selection${NC}"
                    sleep 1
                fi
                ;;
            *)
                echo -e "${RED}Invalid input. Please use L# for local ISOs or D# for downloads${NC}"
                sleep 1
                ;;
        esac
    done
}

# Function to create VM
create_vm() {
    BRIDGE_ADAPTER=$(get_bridge_adapter)
    
    echo -e "${BLUE}Creating virtual machine '$VM_NAME'...${NC}"
    
    # Ensure we're using the correct paths
    if [ "$(id -u)" -eq 0 ] && [ -n "$SUDO_USER" ]; then
        ISO_DIR="/home/$SUDO_USER/vbox-isos"
        VM_DIR="/home/$SUDO_USER/VirtualBox-VMs"
    fi
    
    # Ensure proper permissions
    ensure_permissions
    
    # Create VM as the user who invoked sudo
    echo -e "${YELLOW}Creating new VM...${NC}"
    if ! run_as_user VBoxManage createvm --name "$VM_NAME" --ostype "Ubuntu_64" --register --basefolder "$VM_DIR"; then
        echo -e "${RED}Failed to create VM. Checking permissions...${NC}"
        echo -e "${YELLOW}Try running: sudo chown -R \$USER:\$USER \"$VM_DIR\"${NC}"
        exit 1
    fi
    
    # Configure system
    echo -e "${YELLOW}Configuring VM settings...${NC}"
    run_as_user VBoxManage modifyvm "$VM_NAME" --memory "$VM_MEM" --cpus "$VM_CPUS" --firmware efi \
        --nic1 bridged --bridgeadapter1 "$BRIDGE_ADAPTER" --audio none --usb off
    
    # Create storage
    echo -e "${YELLOW}Setting up storage...${NC}"
    run_as_user VBoxManage storagectl "$VM_NAME" --name "SATA Controller" --add sata --controller IntelAhci
    run_as_user VBoxManage createhd --filename "$VM_DIR/$VM_NAME/$VM_NAME.vdi" --size "$VM_DISK" --format VDI --variant Standard
    run_as_user VBoxManage storageattach "$VM_NAME" --storagectl "SATA Controller" --port 0 --device 0 \
        --type hdd --medium "$VM_DIR/$VM_NAME/$VM_NAME.vdi"
    
    # Attach ISO
    echo -e "${YELLOW}Attaching installation ISO...${NC}"
    run_as_user VBoxManage storagectl "$VM_NAME" --name "IDE Controller" --add ide
    run_as_user VBoxManage storageattach "$VM_NAME" --storagectl "IDE Controller" --port 0 --device 0 \
        --type dvddrive --medium "$ISO_DIR/$ISO_FILE"
    
    # Configure boot
    run_as_user VBoxManage modifyvm "$VM_NAME" --boot1 dvd --boot2 disk --boot3 none --boot4 none
    
    echo -e "${GREEN}Virtual machine created successfully${NC}"
}

# Function to start VM
start_vm() {
    echo -e "${BLUE}Starting virtual machine '$VM_NAME'...${NC}"
    
    # Start VM
    if run_as_user VBoxManage startvm "$VM_NAME" --type headless; then
        echo -e "${GREEN}VM started successfully in headless mode${NC}"
        echo -e "${BLUE}You can connect to the console or wait for SSH if enabled${NC}"
        
        # Get VM UUID
        VM_UUID=$(run_as_user VBoxManage list vms | grep "\"$VM_NAME\"" | awk '{print $2}' | tr -d '{}')
        echo -e "${CYAN}VM UUID: $VM_UUID${NC}"
        
        # Show how to access
        echo -e "\n${YELLOW}To access this VM:${NC}"
        echo -e "1. GUI: Run 'virtualbox' and select '$VM_NAME'"
        echo -e "2. Console: VBoxManage startvm \"$VM_NAME\" --type separate"
        echo -e "3. SSH: Connect after OS installation (if SSH server is installed)"
    else
        echo -e "${RED}Failed to start VM${NC}"
        echo -e "${YELLOW}Check VirtualBox logs for details${NC}"
        exit 1
    fi
}

# Cleanup function
cleanup() {
    [ -f "$TEMP_ISO_MAP" ] && rm -f "$TEMP_ISO_MAP"
}

# Main execution
trap cleanup EXIT
show_menu

# Check if running with sudo, but get original user
if [ "$(id -u)" -eq 0 ] && [ -z "$SUDO_USER" ]; then
    echo -e "${RED}Error: Please run this script with sudo, not as root${NC}"
    exit 1
fi

# Ensure proper permissions before starting
ensure_permissions

# Step 1: Get VM name from user
get_vm_name

# Step 2: Check/Install VirtualBox
if ! check_virtualbox; then
    install_virtualbox
else
    echo -e "${GREEN}VirtualBox is already properly installed${NC}"
fi

# Step 3: Select ISO
select_iso

# Step 4: Create VM
create_vm

# Step 5: Start VM
start_vm

# Final output
echo -e "${GREEN}=== Setup Completed Successfully ===${NC}"
echo -e "${BLUE}VM Name:${NC} $VM_NAME"
echo -e "${BLUE}Selected ISO:${NC} $ISO_FILE"
echo -e "${BLUE}VM Location:${NC} $VM_DIR/$VM_NAME"
echo -e "${BLUE}Network Mode:${NC} Bridged (Adapter: $BRIDGE_ADAPTER)"
echo -e "${BLUE}Connect to the VM console to complete OS installation${NC}"