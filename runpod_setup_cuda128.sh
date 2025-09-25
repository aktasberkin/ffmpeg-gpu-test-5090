#!/bin/bash
# Quick setup for RunPod PyTorch 2.8.0 CUDA 12.8.1 template

echo "=== RTX 5090 Setup on PyTorch Template ==="

# 1. Update environment for RTX 5090
echo "1. Setting RTX 5090 environment..."
export NVIDIA_DRIVER_CAPABILITIES=compute,video,utility
export NVIDIA_VISIBLE_DEVICES=all
export CUDA_VISIBLE_DEVICES=0
export NVIDIA_REQUIRE_CUDA="cuda>=12.8"

# 2. Check CUDA 12.8.1 compatibility
echo "2. Checking CUDA 12.8.1 status..."
nvcc --version | grep "release 12.8"
nvidia-smi --query-gpu=name,driver_version,cuda_version --format=csv

# 3. Install Video Codec SDK headers
echo "3. Installing NVENC headers for CUDA 12.8.1..."
cd /tmp
git clone https://github.com/FFmpeg/nv-codec-headers.git
cd nv-codec-headers
make install PREFIX=/usr/local
ldconfig

# 4. Update FFmpeg if needed
echo "4. Checking FFmpeg NVENC support..."
ffmpeg -hide_banner -encoders | grep nvenc

# If no NVENC, build FFmpeg with CUDA 12.8.1
if ! ffmpeg -hide_banner -encoders | grep -q nvenc; then
    echo "Building FFmpeg with CUDA 12.8.1 support..."
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
        --nvccflags="-gencode arch=compute_89,code=sm_89"

    make -j$(nproc)
    make install
    ldconfig
fi

# 5. Test RTX 5090 NVENC with CUDA 12.8.1
echo "5. Testing RTX 5090 with CUDA 12.8.1..."
ffmpeg -hide_banner \
    -f lavfi -i testsrc2=size=640x480:rate=30:duration=3 \
    -c:v h264_nvenc \
    -preset p1 \
    -b:v 2M \
    -surfaces 32 \
    -y cuda128_nvenc_test.mp4 2>cuda128_test.log

if [ $? -eq 0 ]; then
    echo "✅ RTX 5090 NVENC works with CUDA 12.8.1!"
    ls -la cuda128_nvenc_test.mp4

    # Test concurrent streams
    echo "6. Testing concurrent streams..."
    for i in {1..10}; do
        ffmpeg -hide_banner \
            -f lavfi -i testsrc2=size=320x240:rate=30:duration=5 \
            -c:v h264_nvenc -preset p1 -b:v 1M \
            -y concurrent_cuda128_${i}.mp4 2>/dev/null &
    done
    wait

    successful=$(ls concurrent_cuda128_*.mp4 2>/dev/null | wc -l)
    echo "Concurrent test: $successful/10 streams successful"

    if [ "$successful" -ge 8 ]; then
        echo "✅ RTX 5090 ready for large-scale testing!"
    fi

else
    echo "❌ NVENC test failed:"
    head -5 cuda128_test.log
fi

echo ""
echo "=== CUDA 12.8.1 Template Setup Complete ==="