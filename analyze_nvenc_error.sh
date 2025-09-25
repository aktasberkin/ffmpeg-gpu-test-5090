#!/bin/bash
# Analyze NVENC Error Details

echo "=== Detailed NVENC Error Analysis ==="

# 1. Check the exact error from NVENC
echo "1. Testing NVENC with verbose logging..."
ffmpeg -hide_banner -loglevel debug \
    -f lavfi -i testsrc2=size=128x128:rate=5:duration=1 \
    -c:v h264_nvenc \
    -preset slow \
    -y nvenc_debug_test.mp4 2>nvenc_debug.log

echo "NVENC error details:"
head -20 nvenc_debug.log

# 2. Check specific CUDA/NVENC initialization
echo -e "\n2. CUDA/NVENC library check..."
ldd /usr/local/bin/ffmpeg | grep -E "(cuda|nv)"

echo -e "\n3. NVIDIA libraries in container..."
find /usr -name "*cuda*" -type f 2>/dev/null | head -5
find /usr -name "*nvenc*" -type f 2>/dev/null | head -5

# 4. Try direct CUDA test
echo -e "\n4. Testing CUDA directly..."
/usr/local/cuda/extras/demo_suite/deviceQuery 2>/dev/null || echo "deviceQuery not available"

# 5. Check if it's a memory/resource issue
echo -e "\n5. GPU memory and resources..."
nvidia-smi --query-gpu=memory.total,memory.used,memory.free,utilization.gpu --format=csv 2>/dev/null || echo "nvidia-smi query failed"

# 6. Try alternative NVENC approach
echo -e "\n6. Testing NVENC with minimal resource usage..."
ffmpeg -hide_banner \
    -f lavfi -i color=black:size=64x64:duration=1 \
    -c:v h264_nvenc \
    -surfaces 1 \
    -forced-idr 1 \
    -rc constqp \
    -qp 30 \
    -y minimal_resource_test.mp4 2>minimal_resource.log

if [ $? -eq 0 ]; then
    echo "✅ Minimal resource NVENC works!"
    ls -la minimal_resource_test.mp4
else
    echo "❌ Even minimal resource NVENC failed:"
    head -10 minimal_resource.log
fi

# 7. Check PyTorch CUDA issue
echo -e "\n7. PyTorch CUDA detailed diagnosis..."
python3 -c "
import torch
import os

print('PyTorch version:', torch.__version__)
print('CUDA compiled version:', torch.version.cuda)
print('cuDNN version:', torch.backends.cudnn.version())

print('Environment variables:')
for key in ['CUDA_VISIBLE_DEVICES', 'NVIDIA_VISIBLE_DEVICES']:
    print(f'{key}:', os.environ.get(key, 'Not set'))

print('CUDA device availability:')
print('torch.cuda.is_available():', torch.cuda.is_available())

if not torch.cuda.is_available():
    print('CUDA unavailable reasons:')
    try:
        torch.cuda.current_device()
    except Exception as e:
        print('Error:', e)
"

# 8. Final diagnosis
echo -e "\n8. Final diagnosis summary..."
if [ -f nvenc_debug.log ]; then
    if grep -q "No NVENC capable devices found" nvenc_debug.log; then
        echo "🔍 Issue: NVENC hardware not detected by FFmpeg"
        echo "Possible causes:"
        echo "- Driver 570.153.02 vs RTX 5090 forward compatibility"
        echo "- NVENC API version mismatch"
        echo "- GPU not properly initialized"
    elif grep -q "out of memory" nvenc_debug.log; then
        echo "🔍 Issue: GPU memory problem"
    elif grep -q "failed to initialize" nvenc_debug.log; then
        echo "🔍 Issue: NVENC initialization failure"
    elif grep -q "unsupported" nvenc_debug.log; then
        echo "🔍 Issue: RTX 5090 not supported by current driver"
    fi
fi

echo -e "\n=== Analysis Complete ==="