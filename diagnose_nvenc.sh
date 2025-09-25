#!/bin/bash
# NVENC Diagnosis Script for RTX 5090

echo "=== NVENC Diagnosis for RTX 5090 ==="
echo ""

# 1. GPU Information
echo "1. GPU Information:"
nvidia-smi --query-gpu=name,driver_version,cuda_version --format=csv,noheader

# 2. CUDA Context Test
echo ""
echo "2. CUDA Context Test:"
echo "import pycuda.autoinit; import pycuda.driver as cuda; print('CUDA Context OK')" | python3 2>/dev/null || echo "❌ CUDA context failed"

# 3. NVENC Capability Check
echo ""
echo "3. NVENC Hardware Capabilities:"
nvidia-smi nvml -q | grep -i enc || echo "NVENC info not available via nvml"

# 4. Detailed GPU Status
echo ""
echo "4. Detailed GPU Status:"
nvidia-smi -q -d SUPPORTED_CLOCKS,MEMORY,UTILIZATION,ECC,TEMPERATURE,POWER,CLOCK,COMPUTE

# 5. FFmpeg GPU Detection
echo ""
echo "5. FFmpeg GPU Detection:"
ffmpeg -f lavfi -i testsrc2=size=320x240:rate=1:duration=1 -f null - 2>&1 | grep -i "cuda\|nvenc" | head -5

# 6. Available Encoders
echo ""
echo "6. Available Hardware Encoders:"
ffmpeg -encoders 2>/dev/null | grep -E "(nvenc|vaapi|qsv|videotoolbox)"

# 7. Try Alternative Hardware Acceleration
echo ""
echo "7. Testing Alternative Hardware Acceleration:"

# Test VAAPI (if available)
echo "Testing VAAPI:"
ffmpeg -hwaccel vaapi -f lavfi -i testsrc2=size=320x240:rate=1:duration=1 -c:v h264_vaapi -y test_vaapi.mp4 2>/dev/null && echo "✅ VAAPI works" || echo "❌ VAAPI failed"

# 8. Test without hardware acceleration
echo ""
echo "8. Testing Software Encoding:"
ffmpeg -f lavfi -i testsrc2=size=320x240:rate=1:duration=1 -c:v libx264 -y test_software.mp4 2>/dev/null && echo "✅ Software encoding works" || echo "❌ Software encoding failed"

# 9. NVIDIA Driver and CUDA compatibility
echo ""
echo "9. Driver and CUDA Compatibility:"
echo "Driver Version: $(nvidia-smi --query-gpu=driver_version --format=csv,noheader)"
echo "CUDA Version: $(nvidia-smi --query-gpu=cuda_version --format=csv,noheader)"
echo "Required for RTX 5090: Driver >= 570, CUDA >= 12.6"

# Check if driver supports RTX 5090
DRIVER_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | cut -d. -f1)
if [ "$DRIVER_VERSION" -ge 570 ]; then
    echo "✅ Driver version OK for RTX 5090"
else
    echo "❌ Driver version may be insufficient for RTX 5090"
fi

# 10. NVENC SDK Test
echo ""
echo "10. NVENC SDK Compatibility:"
# Check for NVENC headers
if [ -d "/usr/local/cuda/include" ]; then
    if find /usr/local/cuda/include -name "*nvenc*" | grep -q nvenc; then
        echo "✅ NVENC headers found"
    else
        echo "❌ NVENC headers missing"
    fi
else
    echo "❌ CUDA headers directory not found"
fi

# 11. Container/Virtualization Check
echo ""
echo "11. Container/Virtualization Environment:"
if [ -f /.dockerenv ]; then
    echo "Running in Docker container"
    echo "Docker NVIDIA runtime: $(docker --version 2>/dev/null || echo 'not available')"
fi

# Check if nvidia-container-runtime is available
if command -v nvidia-container-cli &> /dev/null; then
    echo "✅ NVIDIA Container Runtime available"
else
    echo "❌ NVIDIA Container Runtime not found"
fi

# 12. Suggest Solutions
echo ""
echo "=== SUGGESTED SOLUTIONS ==="
echo ""
echo "Based on the error 'OpenEncodeSessionEx failed: unsupported device':"
echo ""
echo "1. **Driver Issue**: RTX 5090 needs driver >= 570.x"
echo "   Current: $(nvidia-smi --query-gpu=driver_version --format=csv,noheader)"
echo ""
echo "2. **NVENC SDK**: May need newer NVENC SDK"
echo "   Try: apt-get install libnvidia-encode-xxx (where xxx is driver version)"
echo ""
echo "3. **Container GPU Access**: Ensure container has proper GPU access"
echo "   Check: nvidia-smi works and shows RTX 5090"
echo ""
echo "4. **FFmpeg NVENC Build**: FFmpeg may need rebuild with newer NVENC SDK"
echo ""
echo "5. **Alternative**: Use software encoding for now:"
echo "   Replace 'h264_nvenc' with 'libx264' in test scripts"
echo ""
echo "=== END DIAGNOSIS ==="