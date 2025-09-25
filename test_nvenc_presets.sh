#!/bin/bash
# Test different NVENC presets and parameters for RTX 5090

echo "=== RTX 5090 NVENC Preset Testing ==="

echo "1. Available NVENC presets for h264_nvenc:"
ffmpeg -hide_banner -h encoder=h264_nvenc 2>/dev/null | grep -A 20 "preset"

echo ""
echo "2. Testing valid NVENC presets..."

# Test valid presets for newer NVENC
PRESETS=("p1" "p2" "p3" "p4" "p5" "p6" "p7" "fast" "slow" "default")

for preset in "${PRESETS[@]}"; do
    echo "Testing preset: $preset"

    ffmpeg -hide_banner -f lavfi -i testsrc2=size=320x240:rate=1:duration=1 \
           -c:v h264_nvenc -preset $preset \
           -pix_fmt yuv420p -y test_${preset}.mp4 2>test_${preset}.log

    if [ $? -eq 0 ]; then
        echo "✅ Preset $preset works!"
        ls -la test_${preset}.mp4
        break
    else
        echo "❌ Preset $preset failed"
        head -3 test_${preset}.log | grep -v "Input\|Duration\|Stream"
    fi
done

echo ""
echo "3. Testing without hardware acceleration..."
ffmpeg -hide_banner -f lavfi -i testsrc2=size=320x240:rate=1:duration=1 \
       -c:v h264_nvenc -preset p1 \
       -pix_fmt yuv420p -y test_no_hwaccel.mp4 2>no_hwaccel.log

if [ $? -eq 0 ]; then
    echo "✅ NVENC without hwaccel works!"
    ls -la test_no_hwaccel.mp4
else
    echo "❌ NVENC without hwaccel failed:"
    head -5 no_hwaccel.log | grep -E "(error|Error|failed|Failed)"
fi

echo ""
echo "4. Testing CUDA device compatibility..."
# Check CUDA device compute capability
nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null || echo "Cannot query compute capability"

echo ""
echo "5. Testing minimal NVENC parameters..."
ffmpeg -hide_banner -f lavfi -i color=blue:size=128x128:rate=1:duration=1 \
       -c:v h264_nvenc \
       -y minimal_test.mp4 2>minimal.log

if [ $? -eq 0 ]; then
    echo "✅ Minimal NVENC parameters work!"
    ls -la minimal_test.mp4
else
    echo "❌ Even minimal parameters fail:"
    cat minimal.log | grep -E "(error|Error|failed|Failed)"
fi

echo ""
echo "6. Checking NVENC initialization..."
ffmpeg -hide_banner -init_hw_device cuda=gpu:0 -f null -i /dev/null 2>init_test.log
if [ $? -eq 0 ]; then
    echo "✅ CUDA device initialization works"
else
    echo "❌ CUDA device initialization fails:"
    cat init_test.log | grep -E "(error|Error|failed|Failed)"
fi

echo ""
echo "=== Test Summary ==="
if ls test_*.mp4 >/dev/null 2>&1; then
    echo "✅ Some NVENC tests succeeded!"
    echo "Working files:"
    ls -la test_*.mp4 minimal_test.mp4 2>/dev/null
else
    echo "❌ All NVENC tests failed"
    echo "RTX 5090 may need:"
    echo "1. Newer CUDA toolkit (>= 12.6)"
    echo "2. Beta driver (>= 575.x)"
    echo "3. Different container runtime"
fi