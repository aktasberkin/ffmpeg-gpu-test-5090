#!/bin/bash
# Fix PyTorch CUDA and NVENC Issues

echo "=== Fix PyTorch CUDA and NVENC Issues ==="

# 1. Check if container was started with --gpus all
echo "1. Checking GPU access in container..."
if [ ! -c "/dev/nvidia0" ]; then
    echo "❌ /dev/nvidia0 not found!"
    echo "Container needs to be started with: --gpus all"
    echo "Or in RunPod: Enable GPU passthrough"
    exit 1
else
    echo "✅ GPU device found: /dev/nvidia0"
fi

# 2. Fix PyTorch CUDA detection
echo "2. Fixing PyTorch CUDA detection..."

# Set CUDA environment properly
export CUDA_HOME=/usr/local/cuda-12.8
export PATH=$CUDA_HOME/bin:$PATH
export LD_LIBRARY_PATH=$CUDA_HOME/lib64:$LD_LIBRARY_PATH

# Force PyTorch to detect CUDA
export CUDA_VISIBLE_DEVICES=0
export NVIDIA_VISIBLE_DEVICES=all

# Test PyTorch CUDA again
python3 -c "
import torch
print('CUDA available:', torch.cuda.is_available())
print('Device count:', torch.cuda.device_count())
if torch.cuda.is_available():
    print('Current device:', torch.cuda.current_device())
    print('Device name:', torch.cuda.get_device_name(0))
    print('Device capability:', torch.cuda.get_device_capability(0))
"

# 3. Fix NVENC preset issue
echo "3. Testing correct NVENC presets..."

# Test with valid NVENC presets for older drivers
NVENC_PRESETS=("slow" "medium" "fast" "hp" "hq" "bd" "ll" "llhq" "llhp" "lossless" "losslesshp")

for preset in "${NVENC_PRESETS[@]}"; do
    echo "Testing preset: $preset"

    ffmpeg -hide_banner \
        -f lavfi -i color=blue:size=128x128:duration=1 \
        -c:v h264_nvenc \
        -preset $preset \
        -profile:v baseline \
        -y test_${preset}.mp4 2>test_${preset}.log

    if [ $? -eq 0 ]; then
        echo "✅ Preset '$preset' works!"
        WORKING_PRESET=$preset
        break
    else
        echo "❌ Preset '$preset' failed"
        head -2 test_${preset}.log
    fi
done

# 4. If we found a working preset, test concurrent streams
if [ ! -z "$WORKING_PRESET" ]; then
    echo "4. Testing concurrent streams with preset '$WORKING_PRESET'..."

    for i in {1..3}; do
        ffmpeg -hide_banner \
            -f lavfi -i testsrc2=size=320x240:rate=15:duration=3 \
            -c:v h264_nvenc \
            -preset $WORKING_PRESET \
            -profile:v main \
            -b:v 500k \
            -y concurrent_fixed_${i}.mp4 2>/dev/null &
    done
    wait

    successful=$(ls concurrent_fixed_*.mp4 2>/dev/null | wc -l)
    echo "Concurrent test result: $successful/3 streams successful"

    if [ "$successful" -ge 2 ]; then
        echo "✅ RTX 5090 NVENC is working!"
        echo "Working preset: $WORKING_PRESET"
        echo "Ready to test large-scale transcoding"
    fi

else
    echo "❌ No NVENC presets work with current driver 570.153.02"
    echo "This RTX 5090 + driver combination has compatibility issues"
    echo ""
    echo "Solutions:"
    echo "1. Ask RunPod to update RTX 5090 driver to 575+"
    echo "2. Use software encoding for now"
    echo "3. Try different RunPod template"
fi

echo ""
echo "=== Fix Complete ==="