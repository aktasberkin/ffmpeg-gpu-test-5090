#!/bin/bash
# Fix NVIDIA Device Detection for RTX 5090

echo "=== Fix NVIDIA Device Detection ==="

# 1. Find the actual NVIDIA device
echo "1. Detecting NVIDIA devices..."
NVIDIA_DEVICES=$(ls /dev/nvidia[0-9] 2>/dev/null)

if [ -z "$NVIDIA_DEVICES" ]; then
    echo "❌ No numbered NVIDIA devices found"
    exit 1
else
    NVIDIA_DEV=$(echo $NVIDIA_DEVICES | head -n1)
    echo "✅ Found NVIDIA device: $NVIDIA_DEV"
fi

# 2. Set proper environment for the detected device
echo "2. Setting environment for $NVIDIA_DEV..."
DEVICE_NUM=$(echo $NVIDIA_DEV | grep -o '[0-9]')

export CUDA_VISIBLE_DEVICES=$DEVICE_NUM
export NVIDIA_VISIBLE_DEVICES=$DEVICE_NUM

echo "CUDA_VISIBLE_DEVICES=$CUDA_VISIBLE_DEVICES"
echo "NVIDIA_VISIBLE_DEVICES=$NVIDIA_VISIBLE_DEVICES"

# 3. Test PyTorch CUDA with correct device
echo "3. Testing PyTorch CUDA..."
python3 -c "
import torch
print('CUDA available:', torch.cuda.is_available())
if torch.cuda.is_available():
    print('Device count:', torch.cuda.device_count())
    print('Current device:', torch.cuda.current_device())
    print('Device name:', torch.cuda.get_device_name(0))
    print('Device capability:', torch.cuda.get_device_capability(0))

    # Test CUDA memory
    x = torch.randn(100, 100).cuda()
    print('✅ CUDA tensor operations work')
    print('GPU Memory allocated:', torch.cuda.memory_allocated(0) / 1024**2, 'MB')
else:
    print('❌ CUDA not available')
"

# 4. Test NVENC with correct device
echo "4. Testing NVENC..."

# First, test basic NVENC availability
ffmpeg -hide_banner -encoders 2>/dev/null | grep nvenc

# Test with working NVENC presets
PRESETS=("slow" "medium" "fast" "hp" "hq" "ll" "llhq")

for preset in "${PRESETS[@]}"; do
    echo "Testing NVENC preset: $preset"

    ffmpeg -hide_banner \
        -f lavfi -i testsrc2=size=320x240:rate=15:duration=2 \
        -c:v h264_nvenc \
        -preset $preset \
        -profile:v main \
        -b:v 500k \
        -y nvenc_test_${preset}.mp4 2>nvenc_${preset}.log

    if [ $? -eq 0 ]; then
        echo "✅ NVENC preset '$preset' works!"
        WORKING_PRESET=$preset
        ls -la nvenc_test_${preset}.mp4
        break
    else
        echo "❌ Preset '$preset' failed:"
        head -2 nvenc_${preset}.log
    fi
done

# 5. Test concurrent NVENC if we found a working preset
if [ ! -z "$WORKING_PRESET" ]; then
    echo "5. Testing concurrent NVENC streams with preset '$WORKING_PRESET'..."

    for i in {1..5}; do
        ffmpeg -hide_banner \
            -f lavfi -i testsrc2=size=320x240:rate=15:duration=3 \
            -c:v h264_nvenc \
            -preset $WORKING_PRESET \
            -profile:v main \
            -b:v 400k \
            -y concurrent_rtx5090_${i}.mp4 2>/dev/null &
    done
    wait

    successful=$(ls concurrent_rtx5090_*.mp4 2>/dev/null | wc -l)
    echo "RTX 5090 concurrent test: $successful/5 streams successful"

    if [ "$successful" -ge 3 ]; then
        echo "🚀 RTX 5090 NVENC is working!"
        echo "Ready for large-scale transcoding test"
        echo "Working preset: $WORKING_PRESET"
    fi
else
    echo "❌ No NVENC presets work"
    echo "Driver compatibility issue with RTX 5090"
fi

echo ""
echo "=== Fix Complete ==="