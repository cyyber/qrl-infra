#!/bin/bash
set -euo pipefail

# -------------------------------------------------------
# Cloud-init: minimal provisioning for QRL ${role} node
# -------------------------------------------------------

# Install Docker
apt-get update -y
apt-get install -y ca-certificates curl gnupg python3 python3-pip jq awscli

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

systemctl enable docker
systemctl start docker

# Create qrl user
useradd -m -s /bin/bash -G docker qrl || true

# Mount EBS data volume
if [ -b /dev/xvdf ]; then
  if ! blkid /dev/xvdf; then
    mkfs.ext4 /dev/xvdf
  fi
  mkdir -p ${data_dir}
  mount /dev/xvdf ${data_dir}
  echo "/dev/xvdf ${data_dir} ext4 defaults,nofail 0 2" >> /etc/fstab
fi

# Create data directories
mkdir -p ${data_dir}/{execution,beacon,validator,logs}
chown -R qrl:qrl ${data_dir}

# Sysctl tuning for high-throughput networking
cat > /etc/sysctl.d/99-qrl.conf <<SYSCTL
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
net.ipv4.tcp_rmem = 4096 1048576 16777216
net.ipv4.tcp_wmem = 4096 1048576 16777216
net.core.netdev_max_backlog = 5000
fs.file-max = 2097152
SYSCTL
sysctl -p /etc/sysctl.d/99-qrl.conf

# Increase file descriptor limits
cat > /etc/security/limits.d/99-qrl.conf <<LIMITS
qrl soft nofile 65536
qrl hard nofile 65536
LIMITS

# Download genesis artifacts from S3
aws s3 cp s3://${s3_bucket}/genesis/ ${data_dir}/ --recursive || echo "Genesis files not yet available in S3"

echo "Cloud-init complete for ${role} node"