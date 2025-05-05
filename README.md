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

   - Create a 2VM
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
       docker network create -d overlay --attachable sso-network
   ```

- -d overlay: Specifies that it is an overlay network.
- --attachable: Allows standalone containers to attach to this network.

- This creates a new network called `sso-network` that will span across all nodes in the Swarm.
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

7. **Configure Docker Registry**:
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

8. **Deploy Services with Docker Swarm in production server ip v4 and Domain**:

   Create `docker-compose.yml` file in `Desktop\exam-2023-2024-vcc_tae` directory:

   ```shell
      networks:
      sso-network:
        driver: bridge

    services:
      # PostgreSQL Database
      postgres:
        image: postgres:15
        container_name: postgres
        environment:
          POSTGRES_USER: forgejo
          POSTGRES_PASSWORD: GVVX0pp3Z4UKo
          POSTGRES_DB: forgejo
        volumes:
          - ./.data/postgres:/var/lib/postgresql/data
        restart: unless-stopped
        networks:
          - sso-network
      # Dex OIDC Provider
      dex:
        image: ghcr.io/dexidp/dex:v2.36.0
        container_name: dex
        ports:
          - "5556:5556"
        volumes:
          - ./dex/config:/etc/dex/config:ro
        command: ["dex", "serve", "/etc/dex/config/config.yaml"]
        restart: unless-stopped
        networks:
          - sso-network

      # Forgejo Git Service
      forgejo:
        image: codeberg.org/forgejo/forgejo:1.20
        container_name: forgejo
        depends_on:
          - postgres
        ports:
          - "3000:3000"
        environment:
          - FORGEJO__security__INSTALL_LOCK=true
          - FORGEJO__database__DB_TYPE=postgres
          - FORGEJO__database__HOST=postgres:5432
          - FORGEJO__database__NAME=forgejo
          - FORGEJO__database__USER=forgejo
          - FORGEJO__database__PASSWD=GVVX0pp3Z4UKo
          - FORGEJO__server__DOMAIN=forgejo.devopsbd.site
          - FORGEJO__server__ROOT_URL=https://forgejo.devopsbd.site
          - FORGEJO__oauth2__ENABLED=true
          - FORGEJO__oauth2__JWT_SECRET=SIGVJfuwHVRnQ+rrhRoKzw7gExdOZLGVVX0pp3Z4UKo=
        volumes:
          - ./.data/forgejo:/data
        restart: unless-stopped
        networks:
          - sso-network
      # Grafana for SSO
      grafana:
        image: grafana/grafana:latest
        container_name: grafana
        ports:
          - "3001:3000"
        environment:
          - GF_AUTH_GENERIC_OAUTH_ENABLED=true
          - GF_AUTH_GENERIC_OAUTH_NAME=Dex
          - GF_AUTH_GENERIC_OAUTH_CLIENT_ID=grafana
          - GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET=grafana_secret
          - GF_AUTH_GENERIC_OAUTH_SCOPES=openid profile email
          - GF_AUTH_GENERIC_OAUTH_AUTH_URL=https://dex.devopsbd.site/dex/auth
          - GF_AUTH_GENERIC_OAUTH_TOKEN_URL=https://dex.devopsbd.site/dex/token
          - GF_AUTH_GENERIC_OAUTH_API_URL=https://dex.devopsbd.site/dex/userinfo
          - GF_AUTH_SIGNOUT_REDIRECT_URL=https://grafana.devopsbd.site/login
          - GF_SERVER_ROOT_URL=https://grafana.devopsbd.site
        volumes:
          - ./.data/grafana:/var/lib/grafana
          - ./grafana/provisioning/dashboards:/etc/grafana/provisioning/dashboards
          - ./grafana/provisioning/datasources:/etc/grafana/provisioning/datasources
        restart: unless-stopped
        networks:
          - sso-network

      # Nginx Reverse Proxy with Let's Encrypt
      nginx:
        image: nginx:latest
        container_name: nginx
        ports:
          - "80:80"
          - "443:443"
        volumes:
          - ./nginx/nginx.conf:/etc/nginx/nginx.conf
          - ./nginx/conf.d/default.conf:/etc/nginx/conf.d/default.conf
          - ./nginx/logs:/var/log/nginx
          - ./.data/certs/certbot/conf:/etc/letsencrypt ## For production
          - ./.data/certs/certbot/www:/var/www/certbot ## For production
        restart: unless-stopped
        depends_on:
          - grafana
          - forgejo
          - dex
        networks:
          - sso-network
        labels:
          org.label-schema.group: "nginx"

      # Prometheus
      prometheus:
        image: prom/prometheus:v2.48.0
        container_name: prometheus
        volumes:
          - ./prometheus:/etc/prometheus
          - ./.data/prometheus:/prometheus
        command:
          - "--config.file=/etc/prometheus/prometheus.yml"
          - "--storage.tsdb.path=/prometheus"
          - "--web.console.libraries=/etc/prometheus/console_libraries"
          - "--web.console.templates=/etc/prometheus/consoles"
          - "--storage.tsdb.retention.time=200h"
          - "--web.enable-lifecycle"
        restart: unless-stopped
        expose:
          - 9090
        networks:
          - sso-network
        labels:
          org.label-schema.group: "monitoring"

      # Alertmanager
      alertmanager:
        image: prom/alertmanager:v0.26.0
        container_name: alertmanager
        volumes:
          - ./alertmanager:/etc/alertmanager
        command:
          - "--config.file=/etc/alertmanager/config.yml"
          - "--storage.path=/alertmanager"
        restart: unless-stopped
        expose:
          - 9093
        networks:
          - sso-network
        labels:
          org.label-schema.group: "monitoring"

      # Node Exporter
      nodeexporter:
        image: prom/node-exporter:v1.7.0
        container_name: nodeexporter
        volumes:
          - /proc:/host/proc:ro
          - /sys:/host/sys:ro
          - /:/rootfs:ro
        command:
          - "--path.procfs=/host/proc"
          - "--path.rootfs=/rootfs"
          - "--path.sysfs=/host/sys"
          - "--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)"
        restart: unless-stopped
        expose:
          - 9100
        networks:
          - sso-network
        labels:
          org.label-schema.group: "monitoring"

      # cAdvisor
      cadvisor:
        image: gcr.io/cadvisor/cadvisor:v0.47.2
        container_name: cadvisor
        privileged: true
        devices:
          - /dev/kmsg:/dev/kmsg
        volumes:
          - /:/rootfs:ro
          - /var/run:/var/run:ro
          - /sys:/sys:ro
          - /var/lib/docker:/var/lib/docker:ro
        restart: unless-stopped
        expose:
          - 8080
        networks:
          - sso-network
        labels:
          org.label-schema.group: "monitoring"

      # Pushgateway
      pushgateway:
        image: prom/pushgateway:v1.6.2
        container_name: pushgateway
        restart: unless-stopped
        expose:
          - 9091
        networks:
          - sso-network
        labels:
          org.label-schema.group: "monitoring"

      certbot:
        image: certbot/certbot
        container_name: certbot
        restart: unless-stopped
        volumes:
          - ./.data/certs/certbot/conf:/etc/letsencrypt
          - ./.data/certs/certbot/www:/var/www/certbot
        networks:
          - sso-network
        entrypoint: "/bin/sh -c 'trap exit TERM; while :; do certbot renew; sleep 12h & wait $${!}; done;'"

      # Caddy
    #  caddy:
    #    image: caddy:2.7.5
    #    container_name: caddy
    #    ports:
    #      - "3000:3000"
    #      - "8080:8080"
    #      - "9090:9090"
    #      - "9093:9093"
    #      - "9091:9091"
    #    volumes:
    #      - ./caddy:/etc/caddy
    #    environment:
    #      - ADMIN_USER=${ADMIN_USER:-admin}
    #      - ADMIN_PASSWORD=${ADMIN_PASSWORD:-admin}
    #      - ADMIN_PASSWORD_HASH=${ADMIN_PASSWORD_HASH:-$2a$14$1l.IozJx7xQRVmlkEQ32OeEEfP5mRxTpbDTCTcXRqn19gXD8YK1pO}
    #    restart: unless-stopped
    #    networks:
    #      - sso-network
    #    labels:
    #      org.label-schema.group: "monitoring"


   ```
   **Note in this yml**
    - Update Domain name `https://grafana.devopsbd.site`
    - update `postgress` password
   **configure `dex/config.yml` google auth**

## Demo Video

[![Watch the video](https://img.youtube.com/vi/7S5-Oi3CTq0/0.jpg)](https://youtu.be/7S5-Oi3CTq0)


## configure on site SSL 
   **Check `make-ssl.sh` file `0` for `production certificate` `1` for `Test fake certificate`**
   ```
   # put your multi domain here, separated by space. Don't forget make nginx multi domain conf
    domains=(example.com my.com)
    rsa_key_size=4096
    data_path="./.data/certs"
    email="example@gmail.com" # Adding a valid address is strongly recommended, please add your own email !
    staging=1 # Set to 1 if you're testing your setup to avoid hitting request limits, set 0 for production env.
    nginx_container="nginx"
```

   **Update `domains, email, staging` & use `docker-compose.yml` file for `production`**
   ```sh
   sudo ./make-ssl.sh
   docker-compose down
   docker-compose up -d ## verify service up and up and running
   ```

Deploy the stack using Docker Swarm from the `VCC-control` VM:

```sh
docker stack deploy -c /vagrant/docker-compose.yml mystack   ## for production live
```
**Local Deploy**
  - NO Need to modify 2 `docker-compose-local.yml` & `docker-compose.exporters-local.yml` file.
  ```sh
     docker stack deploy -c /vagrant/docker-compose-local.yml  mystack-local
     docker stack deploy -c /vagrant/docker-compose.exporters-local.yml mystack-exporters
  ```
### Summary of Steps

1. **Install Prerequisites**: Vagrant, VirtualBox, Git.
2. **Navigate to Project Directory**: `cd Desktop\exam-2023-2024-vcc_tae`.
3. **Configure VMs using Vagrantfile**.
4. **Set up Docker and Docker Swarm** on the VMs.
5. **Configure NFS** for shared storage.
6. **Set up Docker Registry**.
7. **Deploy Services** using Docker Swarm.
