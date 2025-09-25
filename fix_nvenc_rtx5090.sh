#!/bin/bash
# Fix NVENC for RTX 5090 - Driver/SDK Compatibility

set -e
echo "=== Fixing NVENC for RTX 5090 ==="

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 1. Check current driver version
DRIVER_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader)
log_info "Current NVIDIA Driver: $DRIVER_VERSION"

# 2. Install latest NVENC headers for RTX 5090
log_info "Installing NVENC SDK headers for RTX 5090..."

# Download and install Video Codec SDK
cd /tmp
if [ ! -d "Video_Codec_SDK_12.2.72" ]; then
    # Try direct download (may require NVIDIA developer account)
    wget -q --no-check-certificate https://developer.download.nvidia.com/compute/nvenc/12.2/Video_Codec_SDK_12.2.72.zip || \
    curl -L -k -o Video_Codec_SDK_12.2.72.zip https://developer.download.nvidia.com/compute/nvenc/12.2/Video_Codec_SDK_12.2.72.zip || \
    log_warn "Direct download failed, trying alternative method..."
fi

if [ ! -f "Video_Codec_SDK_12.2.72.zip" ]; then
    # Alternative: Install from package manager
    log_info "Installing NVENC libraries from package manager..."

    # Add NVIDIA package repository
    wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
    dpkg -i cuda-keyring_1.1-1_all.deb
    apt-get update

    # Install NVENC development packages
    apt-get install -y \
        libnvidia-encode-570-dev \
        libnvidia-decode-570-dev \
        nvidia-cuda-dev \
        nvidia-cuda-toolkit

    # Install additional codec libraries
    apt-get install -y \
        libnvcuvid1 \
        libnvidia-encode1 \
        libnvidia-decode1
else
    # Extract SDK
    unzip -q Video_Codec_SDK_12.2.72.zip
    cd Video_Codec_SDK_12.2.72

    # Copy headers to system directories
    cp -r Interface/* /usr/local/cuda/include/ 2>/dev/null || \
    cp -r Interface/* /usr/include/

    # Update library paths
    echo "/usr/local/cuda/lib64" > /etc/ld.so.conf.d/cuda.conf
    ldconfig
fi

# 3. Fix container GPU access if needed
log_info "Configuring GPU access for containers..."

# Ensure NVIDIA runtime is properly configured
if [ -f /.dockerenv ]; then
    log_info "Running in container, checking NVIDIA runtime..."

    # Set NVIDIA visible devices
    export NVIDIA_VISIBLE_DEVICES=all
    export NVIDIA_DRIVER_CAPABILITIES=compute,video,utility

    # Verify GPU is accessible
    nvidia-smi > /dev/null || {
        log_error "GPU not accessible in container!"
        exit 1
    }
fi

# 4. Update FFmpeg with proper NVENC support
log_info "Rebuilding FFmpeg with RTX 5090 NVENC support..."

# Remove old FFmpeg
rm -f /usr/local/bin/ffmpeg

# Download latest FFmpeg with NVENC support
cd /tmp
wget -q https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-linux64-gpl.tar.xz
tar -xf ffmpeg-master-latest-linux64-gpl.tar.xz

# Install new FFmpeg
cp ffmpeg-master-latest-linux64-gpl/bin/* /usr/local/bin/
cp ffmpeg-master-latest-linux64-gpl/lib/* /usr/local/lib/ 2>/dev/null || true

# Update library cache
ldconfig

# 5. Set GPU compute mode
log_info "Configuring GPU compute mode..."
nvidia-smi -c 0  # Default compute mode
nvidia-smi -pm 1  # Persistence mode

# 6. Test NVENC availability
log_info "Testing NVENC after fixes..."

# Test 1: Check NVENC encoders
NVENC_COUNT=$(ffmpeg -encoders 2>/dev/null | grep nvenc | wc -l)
if [ "$NVENC_COUNT" -gt 0 ]; then
    log_info "✅ NVENC encoders found: $NVENC_COUNT"
    ffmpeg -encoders 2>/dev/null | grep nvenc
else
    log_error "❌ No NVENC encoders found"
fi

# Test 2: Try simple NVENC encoding
log_info "Testing NVENC encoding capability..."
ffmpeg -f lavfi -i testsrc2=size=640x480:rate=5:duration=2 \
       -c:v h264_nvenc -preset fast -y test_nvenc_fixed.mp4 2>/dev/null

if [ $? -eq 0 ]; then
    log_info "✅ NVENC encoding test successful!"
    ls -la test_nvenc_fixed.mp4
else
    log_error "❌ NVENC encoding still fails"

    # Try alternative NVENC parameters
    log_info "Trying alternative NVENC parameters..."
    ffmpeg -hwaccel cuda -hwaccel_device 0 \
           -f lavfi -i testsrc2=size=640x480:rate=5:duration=2 \
           -c:v h264_nvenc -preset p1 -profile:v high \
           -pixel_format yuv420p -y test_nvenc_alt.mp4 2>nvenc_error.log

    if [ $? -eq 0 ]; then
        log_info "✅ Alternative NVENC parameters work!"
    else
        log_error "❌ NVENC still failing. Error log:"
        cat nvenc_error.log

        # Last resort: Check if it's a RTX 5090 specific issue
        log_warn "Checking RTX 5090 specific issues..."

        # Set RTX 5090 specific environment variables
        export CUDA_VISIBLE_DEVICES=0
        export NVIDIA_REQUIRE_CUDA="cuda>=12.0"

        # Try with specific RTX 5090 workarounds
        ffmpeg -hide_banner -f lavfi -i testsrc2=size=320x240:rate=1:duration=1 \
               -init_hw_device cuda=gpu:0 \
               -filter_hw_device gpu \
               -c:v h264_nvenc -gpu 0 -y test_rtx5090.mp4 2>rtx5090_error.log

        if [ $? -eq 0 ]; then
            log_info "✅ RTX 5090 specific parameters work!"
        else
            log_error "❌ RTX 5090 NVENC issue persists:"
            cat rtx5090_error.log
        fi
    fi
fi

# 7. Final GPU status
log_info "Final GPU Status:"
nvidia-smi --query-gpu=name,driver_version,cuda_version,memory.total --format=csv

echo ""
log_info "NVENC fix attempt completed!"
echo "If NVENC still doesn't work, RTX 5090 may need:"
echo "1. Newer driver (>= 575.x)"
echo "2. Beta/developer NVENC SDK"
echo "3. Specific RTX 5090 container runtime"