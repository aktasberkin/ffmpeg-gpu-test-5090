#!/bin/bash
# RTX 5090 - 3 NVENC Encoder HLS Test (Docker/RunPod Compatible)

STREAMS_PER_ENCODER=20  # Start with lower number due to memory constraints
INPUT_FILE="test_1080p_30fps.mp4"
BASE_DIR="outputs"

# System resource limits (Docker compatible)
ulimit -n 4096              # File descriptor limit

# Create directories
mkdir -p $BASE_DIR/{encoder1,encoder2,encoder3,logs}

# Create test input if not exists (with memory-safe settings)
if [ ! -f "$INPUT_FILE" ]; then
    echo "Creating test input file..."
    ffmpeg -f lavfi -i testsrc2=size=1920x1080:rate=30:duration=60 \
           -c:v libx264 -preset ultrafast -crf 28 -threads 4 \
           -b:v 4M -maxrate 6M -bufsize 2M \
           $INPUT_FILE
fi

echo "Starting RTX 5090 - 3 Encoder HLS Test..."
echo "Each encoder processing $STREAMS_PER_ENCODER concurrent streams"

# Check available memory
FREE_MEM=$(free -m | awk 'NR==2{printf "%d", $7}')
echo "Available memory: ${FREE_MEM}MB"

# GPU monitoring (Docker compatible)
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
        # Add delay between process starts to prevent memory spike
        sleep 0.5

        ffmpeg -hwaccel cuda -hwaccel_device 0 \
            -stream_loop -1 -i "$INPUT_FILE" \
            -c:v h264_nvenc \
            -preset p4 \
            -surfaces 16 \
            -async_depth 1 \
            -rc_lookahead 0 \
            -spatial_aq 0 \
            -temporal_aq 0 \
            -multipass disabled \
            -b:v 1.5M \
            -maxrate 2M \
            -bufsize 1M \
            -vf scale_cuda=1280:720 \
            -r 30 \
            -g 60 \
            -sc_threshold 0 \
            -f hls \
            -hls_time 6 \
            -hls_list_size 5 \
            -hls_segment_filename "$test_dir/stream${i}_%03d.ts" \
            -hls_playlist_type vod \
            -t 120 \
            "$test_dir/stream${i}.m3u8" \
            >"$test_dir/stream${i}.log" 2>&1 &

        # Check if process started successfully
        if [ $? -ne 0 ]; then
            echo "Warning: Stream $i failed to start for encoder $encoder_id"
        fi
    done

    echo "Encoder $encoder_id: $STREAMS_PER_ENCODER processes started"
}

# Start all 3 encoders (Docker compatible - no systemd)
START_TIME=$(date +%s)

# Start encoders with different delays
start_encoder 1 &
ENCODER1_PID=$!
sleep 5

start_encoder 2 &
ENCODER2_PID=$!
sleep 5

start_encoder 3 &
ENCODER3_PID=$!

echo "All encoders started. Monitoring..."
echo "Encoder 1 PID: $ENCODER1_PID"
echo "Encoder 2 PID: $ENCODER2_PID"
echo "Encoder 3 PID: $ENCODER3_PID"

# Monitor progress
monitor_progress() {
    while true; do
        RUNNING_PROCESSES=$(ps aux | grep ffmpeg | grep -v grep | wc -l)
        COMPLETED_STREAMS=$(find $BASE_DIR -name "*.m3u8" 2>/dev/null | wc -l)
        echo "$(date): Running FFmpeg processes: $RUNNING_PROCESSES, Completed streams: $COMPLETED_STREAMS"

        if [ "$RUNNING_PROCESSES" -eq 0 ]; then
            echo "All processes completed"
            break
        fi
        sleep 10
    done
}

monitor_progress &
MONITOR_PROGRESS_PID=$!

# Wait for completion
wait $ENCODER1_PID $ENCODER2_PID $ENCODER3_PID

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Stop monitoring
kill $MONITOR_PID 2>/dev/null
kill $MEMORY_MONITOR_PID 2>/dev/null
kill $MONITOR_PROGRESS_PID 2>/dev/null

echo "Test completed in $DURATION seconds"
echo "Total streams attempted: $((STREAMS_PER_ENCODER * 3))"

# Count successful outputs
TOTAL_SUCCESS=0
for encoder in {1..3}; do
    successful=$(find $BASE_DIR/encoder$encoder -name "*.m3u8" 2>/dev/null | wc -l)
    echo "Encoder $encoder successful outputs: $successful/$STREAMS_PER_ENCODER"
    TOTAL_SUCCESS=$((TOTAL_SUCCESS + successful))
done

echo "Total successful streams: $TOTAL_SUCCESS/$((STREAMS_PER_ENCODER * 3))"

# Generate summary
cat > $BASE_DIR/test_summary.txt << EOF
=== RTX 5090 Test Summary ===
Duration: $DURATION seconds
Total Streams Attempted: $((STREAMS_PER_ENCODER * 3))
Total Successful Streams: $TOTAL_SUCCESS
Success Rate: $((TOTAL_SUCCESS * 100 / (STREAMS_PER_ENCODER * 3)))%
Streams per Encoder: $STREAMS_PER_ENCODER
Output Format: 720p@30fps HLS

Per Encoder Results:
EOF

for encoder in {1..3}; do
    successful=$(find $BASE_DIR/encoder$encoder -name "*.m3u8" 2>/dev/null | wc -l)
    echo "Encoder $encoder: $successful/$STREAMS_PER_ENCODER streams" >> $BASE_DIR/test_summary.txt
done

echo ""
echo "=== Test Summary ==="
cat $BASE_DIR/test_summary.txt

# Check for errors
echo ""
echo "=== Error Analysis ==="
ERROR_COUNT=$(grep -i "error\|failed" $BASE_DIR/encoder*/stream*.log 2>/dev/null | wc -l)
echo "Total errors found in logs: $ERROR_COUNT"

if [ "$ERROR_COUNT" -gt 0 ]; then
    echo "Sample errors:"
    grep -i "error\|failed" $BASE_DIR/encoder*/stream*.log 2>/dev/null | head -5
fi

echo ""
echo "Check $BASE_DIR/ for detailed outputs and logs"
echo "GPU metrics saved to: $BASE_DIR/gpu_metrics.log"