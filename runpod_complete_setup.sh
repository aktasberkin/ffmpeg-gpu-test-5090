#!/bin/bash
# Complete RTX 5090 Setup for RunPod Fresh Container

echo "=== RTX 5090 Complete Setup for RunPod ==="

# 1. Update system and install essential packages
echo "1. Installing system packages..."
apt-get update -y
apt-get install -y \
    wget \
    curl \
    build-essential \
    pkg-config \
    yasm \
    nasm \
    cmake \
    git \
    htop \
    nvtop \
    unzip \
    software-properties-common

# 2. Install NVIDIA Video Codec SDK headers
echo "2. Installing NVIDIA Video Codec SDK..."
cd /tmp
git clone https://github.com/FFmpeg/nv-codec-headers.git
cd nv-codec-headers
make install PREFIX=/usr/local
cd /tmp && rm -rf nv-codec-headers

# 3. Download and compile FFmpeg with NVENC support
echo "3. Compiling FFmpeg with RTX 5090 NVENC support..."
cd /tmp
wget -q https://ffmpeg.org/releases/ffmpeg-7.1.tar.xz
tar -xf ffmpeg-7.1.tar.xz
cd ffmpeg-7.1

./configure \
    --enable-cuda-nvcc \
    --enable-cuvid \
    --enable-nvenc \
    --enable-nonfree \
    --enable-libnpp \
    --extra-cflags=-I/usr/local/cuda/include \
    --extra-ldflags=-L/usr/local/cuda/lib64 \
    --nvccflags="-gencode arch=compute_89,code=sm_89" \
    --enable-shared \
    --disable-static \
    --enable-gpl

if [ $? -eq 0 ]; then
    echo "✅ FFmpeg configure successful"
    make -j$(nproc)
    if [ $? -eq 0 ]; then
        echo "✅ FFmpeg build successful"
        make install
        ldconfig
        echo "✅ FFmpeg installed"
    else
        echo "❌ FFmpeg build failed"
        exit 1
    fi
else
    echo "❌ FFmpeg configure failed"
    exit 1
fi

# 4. Clean up build files
cd /workspace && rm -rf /tmp/ffmpeg-*

# 5. Set RTX 5090 environment variables
echo "4. Setting RTX 5090 environment..."
export NVIDIA_DRIVER_CAPABILITIES=compute,video,utility,display,graphics
export NVIDIA_VISIBLE_DEVICES=all
export CUDA_VISIBLE_DEVICES=0

# Make permanent
cat >> ~/.bashrc << 'EOF'
export NVIDIA_DRIVER_CAPABILITIES=compute,video,utility,display,graphics
export NVIDIA_VISIBLE_DEVICES=all
export CUDA_VISIBLE_DEVICES=0
EOF

# 6. Clone project repository
echo "5. Setting up project..."
if [ ! -d "/workspace/ffmpeg-gpu-test-5090" ]; then
    cd /workspace
    git clone https://github.com/aktasberkin/ffmpeg-gpu-test-5090.git
    cd ffmpeg-gpu-test-5090
    chmod +x *.sh
else
    cd /workspace/ffmpeg-gpu-test-5090
    git pull
    chmod +x *.sh
fi

# 7. Test installation
echo "6. Testing installation..."

# Test FFmpeg
echo "Testing FFmpeg installation..."
ffmpeg -version | head -3

# Test NVENC availability
echo "Testing NVENC encoders..."
ffmpeg -hide_banner -encoders 2>/dev/null | grep nvenc

# 8. Run comprehensive GPU test
echo "7. Running comprehensive RTX 5090 test..."
./fix_nvidia_device.sh

echo ""
echo "=== Setup Complete ==="
echo "🚀 RTX 5090 FFmpeg NVENC environment ready!"
echo ""
echo "Available scripts:"
echo "- ./fix_nvidia_device.sh       # Test NVENC functionality"
echo "- ./rtx5090_hls_test.sh       # Large scale HLS test"
echo "- ./debug_test.sh             # Step-by-step debugging"
echo ""
echo "Monitor GPU: watch -n 1 nvidia-smi"
echo "Monitor processes: nvtop"