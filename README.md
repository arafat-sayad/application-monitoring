Here's a step-by-step breakdown of the solution to this exam

### Prerequisites

1. **Install Git**:
   - Download and install [Git](https://git-scm.com/downloads).

### Project Setup

1. **Navigate to the Project Directory**: 
clone your project repository Open a terminal or command prompt and navigate to your project directory:
   ```sh
   git clone https://github.com/ergitoshkezi/(your project repository name).git
   cd your project repository
   ```

2. **Install virtualbox & configure your vm**:
   use this command & virtualbox is correctly set up.
   -    Create a 2VM 
      - VCC-target1
      - VCC-target2
   ```sh
   cp setup_vbox_ubuntu.sh.example setup_vbox_ubuntu.sh
   chmod +x ./setup_vbox_ubuntu.sh
   sudo ./setup_vbox_ubuntu.sh
   ```
   Key Points of the VirtualBox VM Setup Script:
   - Automated VM Configuration:
     - Creates headless VirtualBox VMs with predefined resources (2 CPUs, 4GB RAM, 50GB disk) or user-customized names

     - Configures bridged networking for direct LAN access using the host's primary network interface
   - Cross-User Compatibility:
     - Handles both regular user and sudo execution scenarios
     - Maintains proper file ownership with run_as_user wrapper for VirtualBox commands
     - Stores ISOs/VMs in user-specific directories (~/vbox-isos, ~/VirtualBox-VMs)

   - ISO Management:
     - Offers preconfigured OS downloads (Ubuntu 18.04-24.04, Debian 12, Rocky Linux 9)
     - Supports local ISO selection via interactive menu (L# for existing files, D# for new downloads)

   - Safety & Validation:
     - Prevents duplicate VM names with existence checks
     - Validates user input for VM naming (alphanumeric/hyphen/underscore only)
     - Auto-installs VirtualBox if missing (with kernel module configuration)

   - Bridged Networking:
     - Automatically detects the host's primary network interface for VM bridging
     - Ensures VMs have direct network access without NAT limitations

   - Headless Operation:
     - Starts VMs without GUI by default for server use
     - Provides UUID and connection instructions (SSH/GUI access) post-creation

   - Permission Hardening:
     - Ensures proper directory ownership when using sudo
     - Uses temporary files with cleanup traps to avoid stale data

**Your VM is now configured successfully. You can access it via SSH or other methods.**

### Tasks Breakdown

1. **Add Docker APT Repository Key and Install Docker**:
   On each VM, run the following commands:
   ```sh
   sudo apt-get update
   sudo apt-get install -y \
       ca-certificates \
       curl \
       gnupg \
       lsb-release

   sudo mkdir -p /etc/apt/keyrings
   curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

   echo \
     "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
     $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

   sudo apt-get update
   sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

   ## Make sure Docker is running:
   sudo systemctl enable docker
   sudo systemctl start docker
   ```

2. **Initialize the Docker Swarm leader(Manager) and worker**

   **Initialize Docker Swarm On the manager node**:
   On the `VCC-control1` VM, run:
   ```sh
   ip add show ## Use ip a or ip addr show to check your IP address. Look for the wlp2s0 interface — it might show something like 192.168.50.10.
   sudo docker swarm init --advertise-addr 192.168.50.10
   ```

3. **Join Worker Nodes to Swarm**:
   On the `VCC-control` VM, get the join token:
   ```sh
   docker swarm join-token worker
   ```
   Copy the join command that appears and run it on `VCC-target1` and `VCC-target2` VMs.
   **Verify the Swarm Nodes MANAGER**
   ```sh
   docker node ls

   root@VCC-target1:# docker node ls
   ID                    HOSTNAME     STATUS    AVAILABILITY   MANAGER STATUS   ENGINE VERSION
   8n24p6bn5gmcql8zp *   VCC-target1   Ready     Active         Leader           27.3.1
   ljb1xqaermbz6ib0h0    VCC-target2   Ready     Active                          27.3.1

   ```

4. ## Create a Docker Swarm Overlay Network

   Now that Swarm is initialized, you need to create an overlay network. This network will enable your containers to communicate with each other across different nodes in the Swarm.

   Run the following command to create the network:

   ```shell
       docker network create -d overlay --attachable my_overlay_network
   ```

  - -d overlay: Specifies that it is an overlay network.
  - --attachable: Allows standalone containers to attach to this network.

  - This creates a new network called `my_overlay_network` that will span across all nodes in the Swarm.
  Ensure that the `docker-compose.yml` specifies external: true under networks to use the external Swarm network.

5. ## Create Volumes in Docker Swarm

  For Docker Swarm, volume handling is similar to standalone `Docker Compose`. The volumes you defined in the `docker-compose.yml (e.g., ./data, ./.data/SSO, etc.)` will be mounted automatically when you deploy the stack.

  If you need shared volumes across multiple nodes, ensure you're using a distributed storage solution like `NFS or a Docker volume plugin like GlusterFS. Otherwise, local volumes` will be limited to the node where the container is running.

6. **Install and Configure NFS**:
   On the `VCC-control` VM:
   ```sh
   sudo apt-get install nfs-kernel-server
   sudo mkdir -p /data
   echo "/data *(rw,sync,no_subtree_check)" | sudo tee -a /etc/exports
   sudo exportfs -a
   sudo systemctl restart nfs-kernel-server
   ```
   On `VCC-target1` and `VCC-target2` VMs:
   ```sh
   sudo apt-get install nfs-common
   sudo mkdir -p /data
   echo "192.168.50.10:/data /data nfs defaults 0 0" | sudo tee -a /etc/fstab
   sudo mount -a
   ```

5. **Configure Docker Registry**:
   On the `VCC-control` VM:
     ```sh
      services:
        registry:
          image: registry:2
          restart: always
          volumes:
            - /data/registry:/var/lib/registry
          environment:
            REGISTRY_HTTP_ADDR: 0.0.0.0:5000
            REGISTRY_STORAGE_DELETE_ENABLED: "true"  # Enable deletion of images
          networks:
            - registry-net
      networks:
        registry-net:
     ```

6. **Deploy Services with Docker Swarm**:
   Create `docker-compose.yml` file in `C:\Users\Hp\Desktop\exam-2023-2024-vcc_tae` directory:
   ```yaml
   version: '3.8'
   services:
     postgres:
       image: postgres:16.1
       volumes:
         - postgres_data:/var/lib/postgresql/data
       environment:
         POSTGRES_USER: forgejo
         POSTGRES_PASSWORD: secret
         POSTGRES_DB: forgejo
     traefik:
       image: traefik:v2.10.7
       ports:
         - "80:80"
         - "443:443"
       volumes:
         - /var/run/docker.sock:/var/run/docker.sock
         - traefik_data:/etc/traefik
       command:
         - "--entrypoints.web.address=:80"
         - "--entrypoints.websecure.address=:443"
         - "--providers.docker"
         - "--certificatesresolvers.myresolver.acme.tlschallenge=true"
         - "--certificatesresolvers.myresolver.acme.email=your-email@example.com"
         - "--certificatesresolvers.myresolver.acme.storage=/etc/traefik/acme.json"
   volumes:
     postgres_data:
     traefik_data:
   ```

   Deploy the stack using Docker Swarm from the `VCC-control` VM:
   ```sh
   docker stack deploy -c /vagrant/docker-compose.yml mystack
   ```

### Summary of Steps

1. **Install Prerequisites**: Vagrant, VirtualBox, Git.
2. **Navigate to Project Directory**: `cd C:\Users\Hp\Desktop\exam-2023-2024-vcc_tae`.
3. **Configure VMs using Vagrantfile**.
4. **Set up Docker and Docker Swarm** on the VMs.
5. **Configure NFS** for shared storage.
6. **Set up Docker Registry**.
7. **Deploy Services** using Docker Swarm.