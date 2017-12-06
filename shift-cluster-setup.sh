# IPFS cluster installation
#
# First do this stuff on your own:
#
# apt-get update && apt-get -y upgrade && apt-get -y dist-upgrade
# apt-get install git nano ufw build-essential jq
# useradd -s /bin/bash -m shift
# sudo visudo and add `shift ALL=(ALL) NOPASSWD:ALL`
# sudo su - shift
# sudo ufw allow 22/tcp
# sudo ufw allow 443/tcp
# sudo ufw allow 4001/tcp
# sudo ufw allow 9096/tcp
# sudo ufw enable

# Install IPFS
user=`whoami`
echo "Installing IPFS"
wget https://dist.ipfs.io/ipfs-update/v1.5.2/ipfs-update_v1.5.2_linux-amd64.tar.gz -O ipfs-update.tar.gz
tar -xzvf ipfs-update.tar.gz
cd ipfs-update
sudo ./install.sh
sudo ipfs-update install latest

# Install GO
echo "Installing Go…"
wget https://storage.googleapis.com/golang/go1.9.linux-amd64.tar.gz -O go.tar.gz
sudo tar -C /usr/local -vxzf go.tar.gz
echo "GOPATH=\$HOME/go" >> ~/.profile
echo "PATH=\$GOPATH/bin:/usr/local/go/bin:\$PATH" >> ~/.profile
source ~/.profile

# Install ipfs-cluster from source
echo "Fetching IPFS Cluster…"
go get -u -d github.com/ipfs/ipfs-cluster
cd $GOPATH/src/github.com/ipfs/ipfs-cluster
make install

# Create self signed cert
echo "Creating certificate…"
sudo openssl genrsa -out shift.key 2048
openssl req -nodes -newkey rsa:2048 -key shift.key -out shift.csr -subj "/C=NL/O=Shift/CN=shiftnrg.org"
sudo openssl x509 -req -days 365 -in shift.csr -signkey shift.key -out shift.crt
sudo bash -c 'cat shift.key shift.crt >> /etc/ssl/private/shift.pem'

# Install HAProxy
echo "Installing HAProxy…"
sudo add-apt-repository ppa:vbernat/haproxy-1.7
sudo apt update
sudo apt install -y haproxy

# Configure HAProxy
sudo sed -i '20i \\ttune.ssl.default-dh-param 2048' /etc/haproxy/haproxy.cfg

extra="
frontend https-in
    bind *:443 ssl crt /etc/ssl/private/shift.pem
    mode http
    default_backend shift

backend shift
    mode http
    balance roundrobin
    option forwardfor
    option httpchk GET / HTTP/1.1\r\nHost:localhost
    server ipfs 127.0.0.1:8080
    http-request set-header X-Forwarded-Port %[dst_port]
    http-request add-header X-Forwarded-Proto https if { ssl_fc }"

echo "$extra" | sudo tee -a /etc/haproxy/haproxy.cfg

# Initialize IPFS and IPFS cluster
echo "Initializing IPFS and IPFS cluster…"
ipfs init
tmp=$(mktemp)
jq '.Discovery.MDNS.Enabled = false | .Bootstrap = []' ~/.ipfs/config > "$tmp" && mv "$tmp" ~/.ipfs/config
ipfs bootstrap add /ip4/80.209.230.17/tcp/4001/ipfs/QmQUoRhFDqYNYtzRXuv7tcQ2ksQnSAWNaWtvtopSBSn4Bi

CLUSTER_SECRET=b57e85e353280d0a220010ae3999431c99a1718b85bf03a231f696bf48a9f986 ipfs-cluster-service init
jq '.consensus.raft.heartbeat_timeout = "10s" | .consensus.raft.election_timeout = "10s" | .cluster.leave_on_shutdown = true | .cluster.replication_factor = 2' ~/.ipfs-cluster/service.json > "$tmp" && mv "$tmp" ~/.ipfs-cluster/service.json

sudo chown $user:$user ~/.ipfs
sudo chown $user:$user ~/.ipfs-cluster

# Start services
echo "Starting HAProxy…"
mkdir ~/logs
sudo service haproxy restart
nohup ipfs daemon > ~/logs/ipfs.log 2>&1 &
nohup ipfs-cluster-service --bootstrap /ip4/80.209.230.17/tcp/9096/ipfs/QmZyixbZdEn4qHj5JBjYP5wnid5ir1yWSoYTsVHFRyC3LM -f > ~/logs/ipfs-cluster.log 2>&1 &