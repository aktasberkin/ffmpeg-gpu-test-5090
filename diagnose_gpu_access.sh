#!/bin/bash
# Diagnose GPU Access and NVENC Issues

echo "=== GPU Access Diagnosis ==="

echo "1. GPU devices:"
ls -la /dev/nvidia* 2>/dev/null || echo "No nvidia devices found"

echo -e "\n2. NVIDIA driver info:"
cat /proc/driver/nvidia/version 2>/dev/null || echo "No nvidia driver info"

echo -e "\n3. GPU capabilities:"
nvidia-ml-py3 --version 2>/dev/null || echo "nvidia-ml-py3 not available"

echo -e "\n4. Container GPU access:"
nvidia-smi --query-gpu=index,name,memory.total,power.limit --format=csv 2>/dev/null || echo "nvidia-smi failed"

echo -e "\n5. NVENC library files:"
find /usr -name "*nvenc*" -type f 2>/dev/null | head -5

echo -e "\n6. NVIDIA compute capability:"
python3 -c "
try:
    import torch
    print('CUDA available:', torch.cuda.is_available())
    if torch.cuda.is_available():
        print('GPU name:', torch.cuda.get_device_name(0))
        print('CUDA capability:', torch.cuda.get_device_capability(0))
except Exception as e:
    print('PyTorch GPU test failed:', e)
" 2>/dev/null || echo "PyTorch not available"

echo -e "\n7. Force NVENC test with minimal settings:"
# Try the most basic NVENC test possible
ffmpeg -hide_banner \
    -f lavfi -i color=red:size=128x128:duration=1 \
    -c:v h264_nvenc \
    -preset ultrafast \
    -tune zerolatency \
    -profile:v baseline \
    -level 3.0 \
    -pix_fmt yuv420p \
    -y minimal_nvenc.mp4 2>minimal_nvenc.log

if [ $? -eq 0 ]; then
    echo "✅ Minimal NVENC works!"
    ls -la minimal_nvenc.mp4

    # Try slightly more complex
    echo -e "\n8. Testing with better settings:"
    ffmpeg -hide_banner \
        -f lavfi -i testsrc2=size=320x240:rate=10:duration=2 \
        -c:v h264_nvenc \
        -preset p6 \
        -profile:v main \
        -b:v 500k \
        -maxrate 600k \
        -bufsize 1200k \
        -y better_nvenc.mp4 2>better_nvenc.log

    if [ $? -eq 0 ]; then
        echo "✅ Better NVENC settings work!"
        ls -la better_nvenc.mp4

        # Try concurrent
        echo -e "\n9. Testing 2 concurrent streams:"
        ffmpeg -hide_banner -f lavfi -i testsrc2=size=160x120:rate=10:duration=3 \
               -c:v h264_nvenc -preset p6 -b:v 200k -y concurrent1.mp4 &
        ffmpeg -hide_banner -f lavfi -i testsrc2=size=160x120:rate=10:duration=3 \
               -c:v h264_nvenc -preset p6 -b:v 200k -y concurrent2.mp4 &
        wait

        concurrent_count=$(ls concurrent*.mp4 2>/dev/null | wc -l)
        echo "Concurrent success: $concurrent_count/2"

    else
        echo "❌ Better settings failed:"
        tail -5 better_nvenc.log
    fi

else
    echo "❌ Even minimal NVENC failed:"
    tail -10 minimal_nvenc.log

    echo -e "\n🔍 Error analysis:"
    if grep -q "No NVENC capable devices found" minimal_nvenc.log; then
        echo "- NVENC hardware not detected"
    elif grep -q "out of memory" minimal_nvenc.log; then
        echo "- GPU memory issue"
    elif grep -q "failed loading" minimal_nvenc.log; then
        echo "- NVENC library loading failed"
    fi
fi

echo -e "\n=== Diagnosis Complete ==="