#!/bin/bash
# Test concurrent file access performance

echo "Testing concurrent file access limitations..."

# Create test file
ffmpeg -f lavfi -i testsrc2=size=1920x1080:rate=30:duration=60 -c:v libx264 -b:v 8M test_base.mp4

# Test 1: Single file, multiple reads
echo "Test 1: Same file 10x concurrent access"
time (
    for i in {1..10}; do
        ffmpeg -i test_base.mp4 -c:v libx264 -preset ultrafast output_same_$i.mp4 &
    done
    wait
)

# Test 2: Multiple identical files
echo "Test 2: Different files 10x concurrent access"
# Create copies
for i in {1..10}; do
    cp test_base.mp4 test_copy_$i.mp4
done

time (
    for i in {1..10}; do
        ffmpeg -i test_copy_$i.mp4 -c:v libx264 -preset ultrafast output_different_$i.mp4 &
    done
    wait
)

# Monitor I/O during tests
iostat -x 1 5 > io_stats.log &

echo "Test completed. Check io_stats.log for I/O performance"