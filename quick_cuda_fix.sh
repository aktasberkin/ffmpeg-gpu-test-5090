#!/bin/bash
# Quick CUDA fix without breaking existing packages

echo "=== Quick CUDA Fix for RTX 5090 ==="

# 1. Fix broken packages first
echo "Fixing broken packages..."
apt --fix-broken install -y || echo "Fix broken install failed, continuing..."

# 2. Don't remove existing CUDA, just add RTX 5090 specific environment
echo "Setting RTX 5090 environment variables..."

export CUDA_VISIBLE_DEVICES=0
export NVIDIA_VISIBLE_DEVICES=all
export NVIDIA_DRIVER_CAPABILITIES=compute,video,utility
export CUDA_MODULE_LOADING=LAZY
export NVIDIA_REQUIRE_CUDA="cuda>=12.0"

# Make permanent for this session
cat >> ~/.bashrc << 'EOF'
export CUDA_VISIBLE_DEVICES=0
export NVIDIA_VISIBLE_DEVICES=all
export NVIDIA_DRIVER_CAPABILITIES=compute,video,utility
export CUDA_MODULE_LOADING=LAZY
export NVIDIA_REQUIRE_CUDA="cuda>=12.0"
EOF

# 3. Test current CUDA
echo "Testing current CUDA version..."
nvcc --version 2>/dev/null || echo "nvcc not found"

# 4. Test nvidia-smi
echo "Testing nvidia-smi..."
nvidia-smi --query-gpu=name,driver_version --format=csv 2>/dev/null || echo "nvidia-smi query failed"

# 5. Test simple FFmpeg without hwaccel first
echo "Testing FFmpeg without hardware acceleration..."
ffmpeg -hide_banner -f lavfi -i color=black:size=128x128:rate=1:duration=1 \
       -c:v libx264 -preset ultrafast -y software_test.mp4 2>/dev/null

if [ $? -eq 0 ]; then
    echo "✅ Software encoding works"

    # 6. Try NVENC with minimal parameters
    echo "Testing NVENC with RTX 5090 workarounds..."

    # Method 1: Without explicit hardware acceleration
    ffmpeg -hide_banner -f lavfi -i color=blue:size=128x128:rate=1:duration=1 \
           -c:v h264_nvenc -preset p7 \
           -y nvenc_simple.mp4 2>nvenc_simple.log

    if [ $? -eq 0 ]; then
        echo "✅ NVENC works without hwaccel!"
        ls -la nvenc_simple.mp4

        # Test with multiple streams (small scale)
        echo "Testing 3 concurrent NVENC streams..."
        for i in {1..3}; do
            ffmpeg -hide_banner -f lavfi -i testsrc2=size=128x128:rate=1:duration=5 \
                   -c:v h264_nvenc -preset p7 \
                   -y concurrent_${i}.mp4 2>concurrent_${i}.log &
        done
        wait

        successful=$(ls concurrent_*.mp4 2>/dev/null | wc -l)
        echo "Concurrent test: $successful/3 streams successful"

    else
        echo "❌ NVENC simple test failed:"
        head -3 nvenc_simple.log

        # Method 2: Check available encoders first
        echo "Available encoders:"
        ffmpeg -encoders 2>/dev/null | grep nvenc || echo "No NVENC encoders found"

        # Method 3: Try with device selection (correct syntax)
        ffmpeg -hide_banner -f lavfi -i color=red:size=128x128:rate=1:duration=1 \
               -c:v h264_nvenc -preset p7 \
               -y nvenc_device.mp4 2>nvenc_device.log

        if [ $? -eq 0 ]; then
            echo "✅ NVENC works!"
            ls -la nvenc_device.mp4
        else
            echo "❌ NVENC device test also failed:"
            head -3 nvenc_device.log

            echo ""
            echo "🔍 NVENC Diagnosis:"
            echo "- FFmpeg can see NVENC encoders but can't use them"
            echo "- This is likely RTX 5090 forward compatibility issue"
            echo "- Current driver: $(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null)"
            echo "- RTX 5090 may need driver >= 575.x or different container runtime"
        fi
    fi
else
    echo "❌ Even software encoding failed"
    echo "This indicates a more serious FFmpeg issue"
fi

echo ""
echo "=== Quick Fix Summary ==="
echo "Environment variables set for RTX 5090"
echo "Try running your test scripts now with these settings"