#!/bin/bash
# Debug script to understand why processes exit immediately

echo "=== RTX 5090 Debug Test ==="

# Check if input file exists and is valid
INPUT_FILE="test_1080p_30fps.mp4"
if [ ! -f "$INPUT_FILE" ]; then
    echo "❌ Input file not found: $INPUT_FILE"
    exit 1
fi

echo "✅ Input file exists: $(ls -lh $INPUT_FILE)"

# Test basic FFmpeg NVENC
echo ""
echo "=== Testing basic NVENC functionality ==="
ffmpeg -hwaccel cuda -f lavfi -i testsrc2=size=640x480:rate=30:duration=5 \
       -c:v h264_nvenc -preset p1 -y test_basic.mp4

if [ $? -eq 0 ]; then
    echo "✅ Basic NVENC test passed"
else
    echo "❌ Basic NVENC test failed"
    exit 1
fi

# Test single stream transcoding
echo ""
echo "=== Testing single stream transcoding ==="
ffmpeg -hwaccel cuda -i "$INPUT_FILE" \
       -c:v h264_nvenc -preset p1 \
       -vf scale_cuda=1280:720 -r 30 \
       -t 10 -y test_single.mp4

if [ $? -eq 0 ]; then
    echo "✅ Single stream test passed"
else
    echo "❌ Single stream test failed"
    exit 1
fi

# Test HLS output
echo ""
echo "=== Testing HLS output ==="
mkdir -p debug_output
ffmpeg -hwaccel cuda -stream_loop -1 -i "$INPUT_FILE" \
       -c:v h264_nvenc -preset p1 \
       -vf scale_cuda=1280:720 -r 30 \
       -f hls -hls_time 6 -hls_list_size 5 \
       -t 20 debug_output/test.m3u8 \
       > debug_single.log 2>&1

if [ $? -eq 0 ]; then
    echo "✅ HLS test passed"
    echo "Generated files:"
    ls -la debug_output/
else
    echo "❌ HLS test failed"
    echo "Error log:"
    cat debug_single.log
    exit 1
fi

# Test concurrent streams (small scale)
echo ""
echo "=== Testing 3 concurrent streams ==="
mkdir -p debug_concurrent

for i in {1..3}; do
    ffmpeg -hwaccel cuda -stream_loop -1 -i "$INPUT_FILE" \
           -c:v h264_nvenc -preset p1 \
           -surfaces 16 -async_depth 1 \
           -vf scale_cuda=1280:720 -r 30 \
           -f hls -hls_time 6 -hls_list_size 5 \
           -t 30 debug_concurrent/stream${i}.m3u8 \
           > debug_concurrent/stream${i}.log 2>&1 &

    echo "Started stream $i (PID: $!)"
done

echo "Waiting for concurrent streams to complete..."
wait

echo "Concurrent test results:"
for i in {1..3}; do
    if [ -f "debug_concurrent/stream${i}.m3u8" ]; then
        echo "✅ Stream $i completed successfully"
        echo "   Segments: $(ls debug_concurrent/stream${i}_*.ts 2>/dev/null | wc -l)"
    else
        echo "❌ Stream $i failed"
        echo "   Error log:"
        head -10 debug_concurrent/stream${i}.log 2>/dev/null || echo "   No log file"
    fi
done

# Check GPU usage during test
echo ""
echo "=== GPU Status ==="
nvidia-smi --query-gpu=name,utilization.gpu,memory.used,memory.total --format=csv

echo ""
echo "=== Debug test completed ==="