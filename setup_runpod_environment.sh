#!/bin/bash
# RunPod RTX 5090 Test Environment Setup Script

set -e  # Exit on any error

echo "=========================================="
echo "RTX 5090 FFmpeg Test Environment Setup"
echo "=========================================="

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    log_warn "Running as root. Some commands may behave differently."
fi

# 1. System Information
log_info "Checking system information..."
echo "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'=' -f2 | tr -d '\"')"
echo "Kernel: $(uname -r)"
echo "Architecture: $(uname -m)"
echo "CPU Cores: $(nproc)"
echo "RAM: $(free -h | grep Mem | awk '{print $2}')"

# 2. Check GPU
log_info "Checking GPU information..."
if command -v nvidia-smi &> /dev/null; then
    nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader,nounits
    GPU_MEMORY=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits)
    log_info "GPU Memory: ${GPU_MEMORY} MB"

    # Check if RTX 5090
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader)
    if [[ "$GPU_NAME" == *"5090"* ]]; then
        log_info "RTX 5090 detected! ✅"
    else
        log_warn "GPU is not RTX 5090: $GPU_NAME"
        log_warn "Test may not produce expected results."
    fi
else
    log_error "nvidia-smi not found! GPU drivers may not be installed."
    exit 1
fi

# 3. Update system packages
log_info "Updating system packages..."
if command -v apt-get &> /dev/null; then
    apt-get update -qq
    apt-get install -y \
        software-properties-common \
        wget \
        curl \
        git \
        build-essential \
        cmake \
        pkg-config \
        yasm \
        nasm \
        unzip \
        htop \
        iotop \
        sysstat \
        tree
elif command -v yum &> /dev/null; then
    yum update -y
    yum install -y \
        wget \
        curl \
        git \
        gcc \
        gcc-c++ \
        cmake \
        pkgconfig \
        yasm \
        nasm \
        unzip \
        htop \
        iotop \
        sysstat \
        tree
fi

# 4. Install CUDA Toolkit (if not present)
log_info "Checking CUDA installation..."
if command -v nvcc &> /dev/null; then
    CUDA_VERSION=$(nvcc --version | grep "release" | awk '{print $6}' | cut -c2-)
    log_info "CUDA $CUDA_VERSION already installed ✅"
else
    log_warn "CUDA toolkit not found. Installing..."

    # Download and install CUDA
    wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.0-1_all.deb
    dpkg -i cuda-keyring_1.0-1_all.deb
    apt-get update
    apt-get -y install cuda-toolkit-12-3

    # Add to PATH
    echo 'export PATH=/usr/local/cuda/bin:$PATH' >> ~/.bashrc
    echo 'export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH' >> ~/.bashrc
    source ~/.bashrc
fi

# 5. Install FFmpeg with NVENC support
log_info "Installing FFmpeg with NVENC support..."
if command -v ffmpeg &> /dev/null; then
    FFMPEG_NVENC=$(ffmpeg -encoders 2>/dev/null | grep nvenc | wc -l)
    if [ "$FFMPEG_NVENC" -gt 0 ]; then
        log_info "FFmpeg with NVENC already installed ✅"
        ffmpeg -version | head -1
    else
        log_warn "FFmpeg found but without NVENC support. Reinstalling..."
        INSTALL_FFMPEG=true
    fi
else
    log_info "FFmpeg not found. Installing..."
    INSTALL_FFMPEG=true
fi

if [ "$INSTALL_FFMPEG" = true ]; then
    # Download pre-compiled FFmpeg with NVENC
    cd /tmp
    wget https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-linux64-gpl.tar.xz
    tar -xf ffmpeg-master-latest-linux64-gpl.tar.xz
    cp ffmpeg-master-latest-linux64-gpl/bin/* /usr/local/bin/
    cp ffmpeg-master-latest-linux64-gpl/lib/* /usr/local/lib/ 2>/dev/null || true
    ldconfig

    # Verify NVENC support
    FFMPEG_NVENC=$(ffmpeg -encoders 2>/dev/null | grep nvenc | wc -l)
    if [ "$FFMPEG_NVENC" -gt 0 ]; then
        log_info "FFmpeg with NVENC installed successfully ✅"
    else
        log_error "FFmpeg NVENC installation failed!"
        exit 1
    fi
fi

# 6. System optimizations
log_info "Applying system optimizations..."

# Increase file descriptor limits
echo "* soft nofile 65536" >> /etc/security/limits.conf
echo "* hard nofile 65536" >> /etc/security/limits.conf
echo "root soft nofile 65536" >> /etc/security/limits.conf
echo "root hard nofile 65536" >> /etc/security/limits.conf

# Set current session limits
ulimit -n 65536

# Memory and kernel optimizations
echo "vm.swappiness=10" >> /etc/sysctl.conf
echo "vm.vfs_cache_pressure=50" >> /etc/sysctl.conf
echo "net.core.rmem_max = 134217728" >> /etc/sysctl.conf
echo "net.core.wmem_max = 134217728" >> /etc/sysctl.conf
sysctl -p

# GPU performance mode
nvidia-smi -pm 1  # Enable persistence mode
nvidia-smi -ac 1215,2100  # Set memory and GPU clocks to max (if supported)

# 7. System optimization complete
log_info "System optimization completed"

# 8. Final verification
log_info "Running final verification..."
echo ""
echo "=== SYSTEM VERIFICATION ==="

# GPU check
log_info "GPU Status:"
nvidia-smi --query-gpu=name,temperature.gpu,utilization.gpu,memory.used,memory.total --format=csv

# FFmpeg check
log_info "FFmpeg NVENC Encoders:"
ffmpeg -encoders 2>/dev/null | grep nvenc

# CUDA check
log_info "CUDA Status:"
nvidia-smi

echo ""
echo "=========================================="
log_info "Environment setup completed successfully! ✅"
echo "=========================================="
echo ""
log_info "Ready for RTX 5090 concurrent stream testing! 🚀"