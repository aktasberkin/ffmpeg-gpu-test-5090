#!/bin/bash
# RTX 5090 Container Runtime Fix

echo "=== RTX 5090 Container Runtime Fix ==="

# 1. Force remove broken CUDA packages
echo "1. Cleaning broken CUDA packages..."
apt-get remove --purge -y cuda-* libnvidia-* nvidia-* || true
apt-get autoremove -y
apt-get autoclean

# 2. Install only minimal NVIDIA runtime for RTX 5090
echo "2. Installing minimal NVIDIA runtime..."
apt-get update
apt-get install -y --no-install-recommends \
    nvidia-driver-575 \
    libnvidia-encode-575 \
    libnvidia-decode-575

# 3. Set RTX 5090 specific environment
echo "3. Setting RTX 5090 environment..."
export NVIDIA_DRIVER_CAPABILITIES=compute,video,utility
export NVIDIA_VISIBLE_DEVICES=all
export CUDA_VISIBLE_DEVICES=0
export NVIDIA_REQUIRE_CUDA="cuda>=12.0,driver>=575"

# Make persistent
cat >> ~/.bashrc << 'EOF'
export NVIDIA_DRIVER_CAPABILITIES=compute,video,utility
export NVIDIA_VISIBLE_DEVICES=all
export CUDA_VISIBLE_DEVICES=0
export NVIDIA_REQUIRE_CUDA="cuda>=12.0,driver>=575"
EOF

# 4. Test basic GPU access
echo "4. Testing GPU access..."
if [ -c "/dev/nvidia0" ]; then
    echo "✅ GPU device accessible"
else
    echo "❌ No GPU device found - container needs --gpus all"
fi

# 5. Test FFmpeg NVENC without CUDA hwaccel
echo "5. Testing FFmpeg NVENC (software decode, hardware encode)..."
ffmpeg -hide_banner \
    -f lavfi -i testsrc2=size=320x240:rate=10:duration=3 \
    -c:v h264_nvenc \
    -preset p7 \
    -b:v 500k \
    -surfaces 8 \
    -y minimal_nvenc.mp4 2>minimal_nvenc.log

if [ $? -eq 0 ]; then
    echo "✅ NVENC encoding works!"
    ls -la minimal_nvenc.mp4

    # Test multiple streams
    echo "6. Testing concurrent NVENC streams..."
    for i in {1..5}; do
        ffmpeg -hide_banner \
            -f lavfi -i testsrc2=size=320x240:rate=10:duration=2 \
            -c:v h264_nvenc -preset p7 -b:v 300k \
            -y concurrent_${i}.mp4 2>/dev/null &
    done
    wait

    successful=$(ls concurrent_*.mp4 2>/dev/null | wc -l)
    echo "Concurrent streams: $successful/5 successful"

    if [ "$successful" -ge 3 ]; then
        echo "✅ RTX 5090 NVENC working for multiple streams!"
        echo "Ready for large-scale testing"
    fi

else
    echo "❌ NVENC still failing:"
    head -3 minimal_nvenc.log

    echo ""
    echo "🔧 Container needs proper RTX 5090 support:"
    echo "- RunPod instance with RTX 5090"
    echo "- Docker runtime: --gpus all"
    echo "- Driver version 575+ on host"
    echo "- nvidia-container-runtime properly configured"
fi

echo ""
echo "=== Container Fix Complete ==="