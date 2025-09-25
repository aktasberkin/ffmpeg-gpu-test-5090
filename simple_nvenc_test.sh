#!/bin/bash
# Simple NVENC test after partial installation

echo "=== Simple NVENC Test ==="

# Check what was installed
echo "1. Checking installed NVENC libraries:"
find /usr/lib/x86_64-linux-gnu -name "*nvidia-encode*" 2>/dev/null || echo "No encode libraries found"
find /usr/lib/x86_64-linux-gnu -name "*nvidia-decode*" 2>/dev/null || echo "No decode libraries found"

echo ""
echo "2. Checking library links:"
ls -la /usr/lib/x86_64-linux-gnu/libnvidia-encode* 2>/dev/null || echo "No encode library links"

echo ""
echo "3. Creating manual NVENC headers..."
mkdir -p /usr/local/include/nvenc
cat > /usr/local/include/nvenc/nvEncodeAPI.h << 'EOF'
#ifndef _NV_ENCODEAPI_H_
#define _NV_ENCODEAPI_H_
#include <stdint.h>
#define NVENCAPI_VERSION 12020072
typedef enum { NV_ENC_SUCCESS, NV_ENC_ERR_UNSUPPORTED_DEVICE } NVENCSTATUS;
typedef struct { uint32_t version; } NV_ENCODE_API_FUNCTION_LIST;
#endif
EOF

echo "✅ Headers created"

echo ""
echo "4. Setting environment variables..."
export CUDA_VISIBLE_DEVICES=0
export NVIDIA_VISIBLE_DEVICES=all
export NVIDIA_DRIVER_CAPABILITIES=compute,video,utility

echo ""
echo "5. Testing basic NVENC (very simple)..."
ffmpeg -hide_banner -f lavfi -i color=black:size=320x240:rate=1:duration=2 \
       -c:v h264_nvenc -preset ultrafast -profile:v baseline \
       -pix_fmt yuv420p -y simple_test.mp4 2>simple_error.log

if [ $? -eq 0 ]; then
    echo "✅ NVENC test successful!"
    ls -la simple_test.mp4
else
    echo "❌ NVENC still fails. Error:"
    head -10 simple_error.log

    echo ""
    echo "6. Trying alternative approach with explicit GPU..."
    ffmpeg -hide_banner -hwaccel cuda -hwaccel_device 0 \
           -f lavfi -i color=red:size=320x240:rate=1:duration=2 \
           -c:v h264_nvenc -gpu 0 -preset p7 \
           -y alternative_test.mp4 2>alt_error.log

    if [ $? -eq 0 ]; then
        echo "✅ Alternative approach works!"
        ls -la alternative_test.mp4
    else
        echo "❌ Alternative also fails:"
        head -5 alt_error.log

        echo ""
        echo "7. Last resort: Check available encoders..."
        ffmpeg -hide_banner -encoders 2>/dev/null | grep nvenc

        if [ $? -eq 0 ]; then
            echo "NVENC encoders are detected but not working"
        else
            echo "NVENC encoders not detected at all"
        fi
    fi
fi

echo ""
echo "=== Test completed ==="
echo "If NVENC failed, RTX 5090 may need beta drivers or different approach."