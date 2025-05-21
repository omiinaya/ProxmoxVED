#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/omiinaya/ProxmoxVED/refs/heads/testing/misc/build.func)
# Copyright (c) 2025 community-scripts ORG
# Author: Adapted for Trellis
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/microsoft/TRELLIS

APP="Trellis"
var_tags="machine-learning;research;vision-language"
var_cpu="4"
var_ram="8192"
var_disk="50"
var_os="debian"
var_version="12"
var_unprivileged="0"  # Privileged mode for GPU passthrough

header_info "$APP"
variables
color
catch_errors

function update_script() {
    header_info
    check_container_storage
    check_container_resources
    if [[ ! -d /opt/TRELLIS ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi
    msg_info "Updating ${APP} LXC"
    $STD apt-get update
    $STD apt-get -y upgrade
    msg_ok "Updated ${APP} LXC"
    exit
}

# Detect NVIDIA driver version and CUDA version from host
msg_info "Detecting NVIDIA driver and CUDA versions on host..."
NVIDIA_VERSION=""
CUDA_VERSION=""
TMP_OUTPUT="/tmp/nvidia_smi_output"
if command -v nvidia-smi >/dev/null; then
    nvidia-smi --query-gpu=driver_version --format=csv,noheader > "$TMP_OUTPUT" 2>&1
    if [[ $? -ne 0 ]]; then
        msg_error "nvidia-smi failed. Output: $(cat "$TMP_OUTPUT")" >&2
        rm -f "$TMP_OUTPUT"
        exit 1
    fi
    NVIDIA_VERSION=$(cat "$TMP_OUTPUT")
    rm -f "$TMP_OUTPUT"
    if [[ -z "$NVIDIA_VERSION" || ! "$NVIDIA_VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
        msg_error "Failed to parse NVIDIA driver version. nvidia-smi output: '$NVIDIA_VERSION'" >&2
        nvidia-smi >&2
        exit 1
    fi
    echo "${NVIDIA_VERSION}" > /tmp/nvidia_version
    if [[ ! -f /tmp/nvidia_version || -z "$(cat /tmp/nvidia_version)" ]]; then
        msg_error "Failed to create /tmp/nvidia_version file. Contents of /tmp: $(ls -l /tmp)" >&2
        exit 1
    fi
else
    msg_error "nvidia-smi not found on host. Cannot determine NVIDIA driver version." >&2
    exit 1
fi

if command -v nvcc >/dev/null; then
    CUDA_VERSION=$(nvcc --version | grep -oP 'release \K[0-9]+\.[0-9]+(\.[0-9]+)?' || true)
    if [[ -z "$CUDA_VERSION" ]]; then
        msg_error "Failed to parse CUDA version from nvcc --version." >&2
        nvcc --version >&2
        exit 1
    fi
    CUDA_MAJOR_MINOR=$(echo "$CUDA_VERSION" | cut -d'.' -f1,2 | tr '.' '-')
    echo "${CUDA_MAJOR_MINOR}" > /tmp/cuda_version
    if [[ ! -f /tmp/cuda_version || -z "$(cat /tmp/cuda_version)" ]]; then
        msg_error "Failed to create /tmp/cuda_version file. Contents of /tmp: $(ls -l /tmp)" >&2
        exit 1
    fi
else
    msg_error "nvcc not found on host. A CUDA Toolkit must be installed to determine the CUDA version." >&2
    exit 1
fi
msg_ok "Detected NVIDIA driver version: $NVIDIA_VERSION, CUDA version: $CUDA_VERSION"

start
build_container

# Configure NVIDIA GPU passthrough
msg_ok "Configuring NVIDIA GPU passthrough..."
CT_CONF="/etc/pve/lxc/${CTID}.conf"
grep -q "nvidia" "$CT_CONF" 2>/dev/null || {
    cat <<EOF >>"$CT_CONF"
# NVIDIA GPU Passthrough
lxc.cgroup2.devices.allow: c 195:* rwm
lxc.cgroup2.devices.allow: c 238:* rwm
lxc.mount.entry: /dev/nvidia0 dev/nvidia0 none bind,optional,create=file
lxc.mount.entry: /dev/nvidiactl dev/nvidiactl none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-uvm dev/nvidia-uvm none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-modeset dev/nvidia-modeset none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-uvm-tools dev/nvidia-uvm-tools none bind,optional,create=file
EOF
}
# Restart container to apply passthrough configuration
pct stop $CTID
pct start $CTID
msg_ok "NVIDIA GPU passthrough configured"

# Copy NVIDIA and CUDA versions to container
msg_ok "Copying NVIDIA driver and CUDA versions to container..."
if ! pct push "$CTID" /tmp/nvidia_version /tmp/nvidia_version 2> /tmp/pct_push_error; then
    msg_error "Failed to copy /tmp/nvidia_version to container. Container ID: $CTID, Host /tmp contents: $(ls -l /tmp), Container status: $(pct status "$CTID"), Error: $(cat /tmp/pct_push_error)" >&2
    rm -f /tmp/pct_push_error
    exit 1
fi
if ! pct push "$CTID" /tmp/cuda_version /tmp/cuda_version 2> /tmp/pct_push_error; then
    msg_error "Failed to copy /tmp/cuda_version to container. Container ID: $CTID, Host /tmp contents: $(ls -l /tmp), Container status: $(pct status "$CTID"), Error: $(cat /tmp/pct_push_error)" >&2
    rm -f /tmp/pct_push_error
    exit 1
fi
rm -f /tmp/pct_push_error
msg_ok "NVIDIA driver and CUDA versions copied to container"

# Install CUDA Toolkit and build tools in container
msg_ok "Installing CUDA Toolkit and build tools in container..."
pct exec "$CTID" -- bash -c "
    CUDA_MAJOR_MINOR=\$(cat /tmp/cuda_version)
    wget https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/cuda-keyring_1.1-1_all.deb || {
        echo \"Failed to download CUDA keyring package.\" >&2
        exit 1
    }
    sudo DEBIAN_FRONTEND=noninteractive dpkg -i cuda-keyring_1.1-1_all.deb
    sudo DEBIAN_FRONTEND=noninteractive apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get -y install cuda-toolkit-\${CUDA_MAJOR_MINOR}

    # Set CUDA environment variables in current session
    export PATH=/usr/local/cuda-\${CUDA_MAJOR_MINOR}/bin:\$PATH
    export LD_LIBRARY_PATH=/usr/local/cuda-\${CUDA_MAJOR_MINOR}/lib64:\$LD_LIBRARY_PATH
    export CUDA_HOME=/usr/local/cuda-\${CUDA_MAJOR_MINOR}

    # Persist environment variables
    echo 'export PATH=/usr/local/cuda-\${CUDA_MAJOR_MINOR}/bin:\$PATH' >> ~/.bashrc
    echo 'export LD_LIBRARY_PATH=/usr/local/cuda-\${CUDA_MAJOR_MINOR}/lib64:\$LD_LIBRARY_PATH' >> ~/.bashrc
    echo 'export CUDA_HOME=/usr/local/cuda-\${CUDA_MAJOR_MINOR}' >> ~/.bashrc

    # Verify nvcc command
    nvcc --version || {
        echo \"nvcc command not found after setting environment variables.\" >&2
        exit 1
    }

    sudo DEBIAN_FRONTEND=noninteractive apt-get -y install cuda-cudart-dev-\${CUDA_MAJOR_MINOR} cuda-compiler-\${CUDA_MAJOR_MINOR} build-essential gcc g++ libstdc++6 python3 python3-pip cmake ninja-build llvm || {
        echo \"Failed to install CUDA toolkit and build tools for \${CUDA_MAJOR_MINOR}.\" >&2
        exit 1
    }
    rm cuda-keyring_1.1-1_all.deb
" || {
    msg_error "Failed to install CUDA Toolkit and configure environment in container $CTID." >&2
    exit 1
}
msg_ok "CUDA Toolkit and build tools installed and configured"

# Install Trellis-specific dependencies
msg_ok "Installing Trellis-specific dependencies..."
pct exec "$CTID" -- bash -c "
    export PATH=\"/opt/miniconda/bin:/usr/local/cuda-\${CUDA_MAJOR_MINOR}/bin:\$PATH\"
    export LD_LIBRARY_PATH=/usr/local/cuda-\${CUDA_MAJOR_MINOR}/lib64:\$LD_LIBRARY_PATH
    export CUDA_HOME=/usr/local/cuda-\${CUDA_MAJOR_MINOR}
    source /opt/miniconda/etc/profile.d/conda.sh
    conda init bash
    source ~/.bashrc
    \$STD conda create -n trellis python=3.10 -y
    \$STD conda activate trellis || {
        echo \"Failed to activate trellis Conda environment.\" >&2
        exit 1
    }
    \$STD conda install pytorch==2.4.0 torchvision==0.19.0 pytorch-cuda=12.1 -c pytorch -c nvidia -y || {
        echo \"Failed to install PyTorch.\" >&2
        exit 1
    }
    \$STD conda install open3d -c open3d -y || {
        echo \"Failed to install open3d.\" >&2
        exit 1
    }
    \$STD pip install xformers --index-url https://download.pytorch.org/whl/cu121
    \$STD pip install flash-attn --no-build-isolation
    # Debug CUDA availability
    \$STD nvidia-smi || {
        echo \"nvidia-smi failed in container.\" >&2
        exit 1
    }
    \$STD ls -l /dev/nvidia* || {
        echo \"NVIDIA devices not found.\" >&2
        exit 1
    }
    \$STD ldconfig -p | grep libcuda || {
        echo \"libcuda.so not found in ldconfig.\" >&2
        exit 1
    }
    # Verify PyTorch and CUDA availability
    \$STD python -c 'import torch; assert torch.cuda.is_available(), \"CUDA is not available\"; print(\"PyTorch\", torch.__version__, \"CUDA\", torch.version.cuda)' || {
        echo \"PyTorch or CUDA verification failed.\" >&2
        exit 1
    }
    \$STD git clone --recurse-submodules https://github.com/microsoft/TRELLIS.git /opt/TRELLIS
    cd /opt/TRELLIS
    \$STD bash setup.sh --basic --xformers --flash-attn --diffoctreerast --spconv --mipgaussian --kaolin --nvdiffrast || {
        echo \"Trellis setup.sh failed.\" >&2
        exit 1
    }
" || {
    msg_error "Failed to install Trellis dependencies in container $CTID." >&2
    exit 1
}
msg_ok "Trellis dependencies installed"

description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access Trellis in the container at /opt/TRELLIS${CL}"
