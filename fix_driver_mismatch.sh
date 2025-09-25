#!/bin/bash
# RTX 5090 Driver/Library Mismatch Fix

echo "=== RTX 5090 Driver/Library Mismatch Fix ==="

echo "1. Current driver status:"
nvidia-smi || echo "nvidia-smi failed"

echo -e "\n2. Current NVML library:"
find /usr -name "*nvidia-ml*" 2>/dev/null | head -5

echo -e "\n3. Current CUDA libraries:"
find /usr -name "*cuda*" 2>/dev/null | grep -E "(nvenc|nvcuvid)" | head -5

echo -e "\n4. Container runtime check:"
ls -la /dev/nvidia* 2>/dev/null || echo "No nvidia devices found"

echo -e "\n5. Force reinstall nvidia runtime libraries:"
apt-get remove --purge -y libnvidia-encode-* libnvidia-decode-* 2>/dev/null || true

# Install specific version matching the driver
apt-get install -y \
    libnvidia-encode-570 \
    libnvidia-decode-570 \
    nvidia-utils-570

echo -e "\n6. Fix FFmpeg-NVENC linkage:"
# Create symlinks if missing
ln -sf /usr/lib/x86_64-linux-gnu/libnvidia-encode.so.570.* /usr/lib/x86_64-linux-gnu/libnvidia-encode.so.1
ln -sf /usr/lib/x86_64-linux-gnu/libnvidia-decode.so.570.* /usr/lib/x86_64-linux-gnu/libnvidia-decode.so.1

echo -e "\n7. Update library cache:"
ldconfig

echo -e "\n8. Test NVENC availability:"
ffmpeg -hide_banner -hwaccels 2>/dev/null || echo "hwaccels query failed"
ffmpeg -hide_banner -encoders 2>/dev/null | grep nvenc || echo "No NVENC encoders"

echo -e "\n9. Test hardware-accelerated decode + encode:"
# Use CUDA for decode, NVENC for encode
ffmpeg -hide_banner \
    -hwaccel cuda \
    -f lavfi -i testsrc2=size=640x480:rate=30:duration=2 \
    -c:v h264_nvenc \
    -preset p1 \
    -b:v 1M \
    -y hwaccel_test.mp4 2>hwaccel_test.log

if [ $? -eq 0 ]; then
    echo "✅ Hardware-accelerated encoding SUCCESS!"
    ls -la hwaccel_test.mp4
else
    echo "❌ Hardware-accelerated encoding FAILED:"
    head -5 hwaccel_test.log

    echo -e "\n10. Alternative: Direct NVENC test (no hwaccel):"
    ffmpeg -hide_banner \
        -f lavfi -i testsrc2=size=640x480:rate=30:duration=2 \
        -c:v h264_nvenc \
        -preset p1 \
        -surfaces 16 \
        -y direct_nvenc_test.mp4 2>direct_nvenc_test.log

    if [ $? -eq 0 ]; then
        echo "✅ Direct NVENC encoding SUCCESS!"
        ls -la direct_nvenc_test.mp4
    else
        echo "❌ All NVENC tests FAILED:"
        echo "Driver issue requires container restart with proper nvidia runtime"
    fi
fi

echo -e "\n=== Fix Summary ==="
echo "If tests still fail, the container needs:"
echo "1. Proper --gpus all flag"
echo "2. nvidia-container-runtime"
echo "3. Driver version >= 575.x for RTX 5090"