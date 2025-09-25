#!/bin/bash
# Manual NVENC headers installation for RTX 5090

set -e
echo "=== Manual NVENC Fix for RTX 5090 ==="

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# 1. Install NVENC libraries from Ubuntu repo
log_info "Installing NVENC libraries from package manager..."

apt-get update -qq
apt-get install -y \
    libnvidia-encode-570 \
    libnvidia-decode-570 \
    libnvidia-compute-570 \
    nvidia-utils-570

# 2. Create NVENC headers manually
log_info "Creating NVENC headers for RTX 5090..."

mkdir -p /usr/local/include/nvenc
cd /usr/local/include/nvenc

# Create basic NVENC header
cat > nvEncodeAPI.h << 'EOF'
#ifndef _NV_ENCODEAPI_H_
#define _NV_ENCODEAPI_H_

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define NVENCAPI_VERSION 12020072

typedef enum {
    NV_ENC_SUCCESS,
    NV_ENC_ERR_UNSUPPORTED_DEVICE,
    NV_ENC_ERR_INVALID_PTR,
    NV_ENC_ERR_INVALID_PARAM,
} NVENCSTATUS;

typedef struct {
    uint32_t version;
} NV_ENCODE_API_FUNCTION_LIST;

typedef void* NV_ENC_INPUT_PTR;
typedef void* NV_ENC_OUTPUT_PTR;

NVENCSTATUS NvEncOpenEncodeSessionEx(void* device, uint32_t deviceType, void** encoder, uint32_t apiVersion);
NVENCSTATUS NvEncGetEncodeGUIDs(void* encoder, void* guids, uint32_t arraySize, uint32_t* guidCount);

#ifdef __cplusplus
}
#endif

#endif
EOF

# 3. Set up library links
log_info "Setting up library links..."

# Find NVIDIA libraries
NVIDIA_LIB_DIR="/usr/lib/x86_64-linux-gnu"
if [ -f "$NVIDIA_LIB_DIR/libnvidia-encode.so.570.153.02" ]; then
    ln -sf libnvidia-encode.so.570.153.02 $NVIDIA_LIB_DIR/libnvidia-encode.so.1
    ln -sf libnvidia-encode.so.1 $NVIDIA_LIB_DIR/libnvidia-encode.so
fi

# Update library cache
ldconfig

# 4. Set environment variables
log_info "Setting RTX 5090 environment variables..."

export CUDA_VISIBLE_DEVICES=0
export NVIDIA_VISIBLE_DEVICES=all
export NVIDIA_DRIVER_CAPABILITIES=compute,video,utility
export __GL_SYNC_TO_VBLANK=0

# Add to bashrc
cat >> ~/.bashrc << 'EOF'
export CUDA_VISIBLE_DEVICES=0
export NVIDIA_VISIBLE_DEVICES=all
export NVIDIA_DRIVER_CAPABILITIES=compute,video,utility
export __GL_SYNC_TO_VBLANK=0
EOF

# 5. Test minimal NVENC
log_info "Testing minimal NVENC functionality..."

# Try with basic parameters
ffmpeg -y -f lavfi -i testsrc2=size=320x240:rate=1:duration=2 \
       -c:v h264_nvenc -preset ultrafast \
       test_minimal.mp4 2>minimal_test.log

if [ $? -eq 0 ]; then
    log_info "✅ Minimal NVENC test successful!"
    ls -la test_minimal.mp4
else
    log_error "❌ Minimal NVENC still fails:"
    cat minimal_test.log

    # Try alternative approach
    log_warn "Trying alternative NVENC approach..."

    # Force specific GPU selection
    ffmpeg -y -hwaccel cuda -hwaccel_device 0 \
           -extra_hw_frames 8 \
           -f lavfi -i testsrc2=size=320x240:rate=1:duration=2 \
           -c:v h264_nvenc -preset p7 -profile:v baseline \
           -pix_fmt yuv420p \
           test_alternative.mp4 2>alternative_test.log

    if [ $? -eq 0 ]; then
        log_info "✅ Alternative NVENC approach works!"
        ls -la test_alternative.mp4
    else
        log_error "❌ Alternative approach also fails:"
        cat alternative_test.log

        # Last resort: Check if NVENC is actually available
        log_warn "Checking NVENC device availability..."

        # Use nvidia-ml-py to check encoding capabilities
        python3 << 'PYEOF'
try:
    import pynvml
    pynvml.nvmlInit()

    device_count = pynvml.nvmlDeviceGetCount()
    print(f"Found {device_count} NVIDIA device(s)")

    for i in range(device_count):
        handle = pynvml.nvmlDeviceGetHandleByIndex(i)
        name = pynvml.nvmlDeviceGetName(handle).decode('utf-8')

        # Check for encoder/decoder
        try:
            enc_util = pynvml.nvmlDeviceGetEncoderUtilization(handle)
            print(f"Device {i} ({name}): Encoder available")
        except:
            print(f"Device {i} ({name}): Encoder status unknown")

except ImportError:
    print("pynvml not available, installing...")
    import subprocess
    subprocess.run(["pip", "install", "pynvml"], check=True)
    print("Please re-run this script")
except Exception as e:
    print(f"GPU check failed: {e}")
PYEOF
    fi
fi

# 6. Create working parameters for RTX 5090
log_info "Creating RTX 5090 optimized parameters..."

cat > rtx5090_params.txt << 'EOF'
# RTX 5090 Working Parameters
# Use these if basic NVENC fails:

# Option 1: Ultra-conservative
-hwaccel cuda -hwaccel_device 0 -c:v h264_nvenc -preset p7 -profile:v baseline -pix_fmt yuv420p

# Option 2: Force software fallback
-c:v libx264 -preset fast -crf 23

# Option 3: Try VAAPI if available
-hwaccel vaapi -vaapi_device /dev/dri/renderD128 -c:v h264_vaapi

# Option 4: Try QSV (Intel)
-hwaccel qsv -c:v h264_qsv
EOF

echo ""
log_info "Manual NVENC fix completed!"
echo ""
echo "If NVENC still doesn't work, RTX 5090 may require:"
echo "1. Newer driver (>= 575.x beta)"
echo "2. Container runtime fixes"
echo "3. Fallback to software encoding"
echo ""
echo "Check rtx5090_params.txt for alternative parameters"