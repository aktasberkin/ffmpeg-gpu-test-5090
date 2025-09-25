#!/bin/bash
# RTX 5090 - 3 NVENC Encoder HLS Test with Resource Optimization

STREAMS_PER_ENCODER=60
INPUT_FILE="test_1080p_30fps.mp4"
BASE_DIR="outputs"

# System resource limits
ulimit -n 4096              # File descriptor limit
ulimit -v 2097152           # 2GB virtual memory per process
ulimit -m 2097152           # 2GB physical memory per process

# Create directories
mkdir -p $BASE_DIR/{encoder1,encoder2,encoder3,logs}

# Create test input if not exists
if [ ! -f "$INPUT_FILE" ]; then
    echo "Creating test input file..."
    ffmpeg -f lavfi -i testsrc2=size=1920x1080:rate=30:duration=300 -c:v libx264 -b:v 8M $INPUT_FILE
fi

echo "Starting RTX 5090 - 3 Encoder HLS Test..."
echo "Each encoder processing $STREAMS_PER_ENCODER concurrent streams"

# GPU monitoring
nvidia-smi dmon -i 0 -s pucvmet -d 1 > $BASE_DIR/gpu_metrics.log &
MONITOR_PID=$!

# GPU memory monitoring
nvidia-smi --query-gpu=memory.used,memory.free --format=csv -l 1 > $BASE_DIR/gpu_memory.log &
MEMORY_MONITOR_PID=$!

start_encoder() {
    local encoder_id=$1
    local test_dir="$BASE_DIR/encoder$encoder_id"

    echo "Starting Encoder $encoder_id with $STREAMS_PER_ENCODER streams..."

    for i in $(seq 1 $STREAMS_PER_ENCODER); do
        ffmpeg -hwaccel cuda -hwaccel_device 0 \
            -stream_loop -1 -i "$INPUT_FILE" \
            -c:v h264_nvenc \
            -preset p1 \
            -surfaces 32 \
            -async_depth 2 \
            -rc_lookahead 0 \
            -spatial_aq 0 \
            -temporal_aq 0 \
            -b:v 2M \
            -maxrate 2.5M \
            -bufsize 2M \
            -vf scale_cuda=1280:720 \
            -r 30 \
            -g 60 \
            -sc_threshold 0 \
            -f hls \
            -hls_time 6 \
            -hls_list_size 0 \
            -hls_segment_filename "$test_dir/stream${i}_%03d.ts" \
            -hls_playlist_type vod \
            -t 180 \
            "$test_dir/stream${i}.m3u8" \
            >"$test_dir/stream${i}.log" 2>&1 &
    done

    echo "Encoder $encoder_id: $STREAMS_PER_ENCODER processes started"
}

# Start all 3 encoders with CPU core assignment and memory limits
START_TIME=$(date +%s)

# Encoder 1: Cores 0-15, 16GB memory limit
systemd-run --scope -p MemoryLimit=16G taskset -c 0-15 bash -c "$(declare -f start_encoder); start_encoder 1" &
ENCODER1_PID=$!

# Encoder 2: Cores 16-31, 16GB memory limit
systemd-run --scope -p MemoryLimit=16G taskset -c 16-31 bash -c "$(declare -f start_encoder); start_encoder 2" &
ENCODER2_PID=$!

# Encoder 3: Cores 32-47, 16GB memory limit
systemd-run --scope -p MemoryLimit=16G taskset -c 32-47 bash -c "$(declare -f start_encoder); start_encoder 3" &
ENCODER3_PID=$!

echo "All encoders started. Monitoring..."
echo "Encoder 1 PID: $ENCODER1_PID"
echo "Encoder 2 PID: $ENCODER2_PID"
echo "Encoder 3 PID: $ENCODER3_PID"

# Wait for completion
wait $ENCODER1_PID $ENCODER2_PID $ENCODER3_PID

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Stop monitoring
kill $MONITOR_PID 2>/dev/null
kill $MEMORY_MONITOR_PID 2>/dev/null

echo "Test completed in $DURATION seconds"
echo "Total streams processed: $((STREAMS_PER_ENCODER * 3))"
echo "Check $BASE_DIR/ for outputs and logs"

# Generate summary
echo "=== Test Summary ===" > $BASE_DIR/test_summary.txt
echo "Duration: $DURATION seconds" >> $BASE_DIR/test_summary.txt
echo "Total Streams: $((STREAMS_PER_ENCODER * 3))" >> $BASE_DIR/test_summary.txt
echo "Streams per Encoder: $STREAMS_PER_ENCODER" >> $BASE_DIR/test_summary.txt
echo "Output Format: 720p@30fps HLS" >> $BASE_DIR/test_summary.txt

# Count successful outputs
for encoder in {1..3}; do
    successful=$(find $BASE_DIR/encoder$encoder -name "*.m3u8" | wc -l)
    echo "Encoder $encoder successful outputs: $successful/$STREAMS_PER_ENCODER" >> $BASE_DIR/test_summary.txt
done

echo "Test summary saved to $BASE_DIR/test_summary.txt"