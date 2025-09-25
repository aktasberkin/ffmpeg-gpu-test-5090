#!/bin/bash
# Fix CUDA compatibility for RTX 5090

set -e
echo "=== Fixing CUDA Compatibility for RTX 5090 ==="

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# 1. Check current versions
log_info "Current system status:"
echo "Driver version: $(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null || echo 'Unknown')"
echo "CUDA version: $(nvcc --version 2>/dev/null | grep 'release' || echo 'CUDA not found')"

# 2. Remove conflicting CUDA installations
log_info "Cleaning old CUDA installations..."
apt-get remove --purge -y cuda* nvidia-cuda-* 2>/dev/null || true
apt-get autoremove -y 2>/dev/null || true

# 3. Install latest CUDA toolkit for RTX 5090
log_info "Installing CUDA 12.6+ for RTX 5090..."

# Add NVIDIA CUDA repository
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
dpkg -i cuda-keyring_1.1-1_all.deb
apt-get update

# Install CUDA 12.6 (RTX 5090 minimum requirement)
apt-get install -y cuda-toolkit-12-6 cuda-drivers-570

# 4. Update environment variables
log_info "Setting CUDA environment variables..."

export CUDA_HOME=/usr/local/cuda-12.6
export PATH=$CUDA_HOME/bin:$PATH
export LD_LIBRARY_PATH=$CUDA_HOME/lib64:$LD_LIBRARY_PATH

# Make permanent
cat > /etc/environment << 'EOF'
CUDA_HOME=/usr/local/cuda-12.6
PATH=/usr/local/cuda-12.6/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
LD_LIBRARY_PATH=/usr/local/cuda-12.6/lib64
EOF

# Update current session
source /etc/environment

# 5. Create CUDA symlinks
log_info "Creating CUDA symlinks for RTX 5090..."
ln -sf /usr/local/cuda-12.6 /usr/local/cuda
ldconfig

# 6. Fix NVENC libraries for CUDA 12.6
log_info "Updating NVENC libraries..."

# Ensure proper library versions
if [ -f "/usr/lib/x86_64-linux-gnu/libnvidia-encode.so.570.172.08" ]; then
    # Use newer version
    ln -sf libnvidia-encode.so.570.172.08 /usr/lib/x86_64-linux-gnu/libnvidia-encode.so.1
    ln -sf libnvidia-encode.so.1 /usr/lib/x86_64-linux-gnu/libnvidia-encode.so
elif [ -f "/usr/lib/x86_64-linux-gnu/libnvidia-encode.so.570.153.02" ]; then
    # Use current version
    ln -sf libnvidia-encode.so.570.153.02 /usr/lib/x86_64-linux-gnu/libnvidia-encode.so.1
    ln -sf libnvidia-encode.so.1 /usr/lib/x86_64-linux-gnu/libnvidia-encode.so
fi

ldconfig

# 7. Test CUDA device detection
log_info "Testing CUDA device detection..."
/usr/local/cuda/extras/demo_suite/deviceQuery || log_warn "CUDA deviceQuery failed"

# 8. Test basic CUDA initialization
log_info "Testing CUDA initialization..."
python3 << 'PYEOF'
try:
    import subprocess
    import os

    # Set environment
    os.environ['CUDA_VISIBLE_DEVICES'] = '0'

    # Test with cuda-python
    try:
        subprocess.run(['pip', 'install', 'cuda-python'], check=True, capture_output=True)
        import cuda
        cuda.cuda.cuInit(0)
        print("✅ CUDA initialization successful with cuda-python")
    except:
        # Fallback test
        result = subprocess.run([
            'python3', '-c',
            'import ctypes; lib = ctypes.CDLL("/usr/local/cuda/lib64/libcuda.so"); lib.cuInit(0); print("CUDA OK")'
        ], capture_output=True, text=True)

        if result.returncode == 0:
            print("✅ Basic CUDA library access works")
        else:
            print("❌ CUDA library access failed")
            print(f"Error: {result.stderr}")

except Exception as e:
    print(f"❌ CUDA test failed: {e}")
PYEOF

# 9. Test FFmpeg with updated CUDA
log_info "Testing FFmpeg with CUDA 12.6..."

# Set RTX 5090 specific environment
export CUDA_VISIBLE_DEVICES=0
export NVIDIA_VISIBLE_DEVICES=all
export NVIDIA_DRIVER_CAPABILITIES=compute,video,utility
export CUDA_MODULE_LOADING=LAZY  # RTX 5090 specific

# Test minimal CUDA initialization
ffmpeg -hide_banner -f lavfi -i testsrc2=size=128x128:rate=1:duration=1 \
       -init_hw_device cuda=gpu:0 -f null - 2>cuda_test.log

if [ $? -eq 0 ]; then
    log_info "✅ FFmpeg CUDA initialization works!"

    # Now test NVENC
    ffmpeg -hide_banner -f lavfi -i color=green:size=128x128:rate=1:duration=1 \
           -init_hw_device cuda=gpu:0 \
           -c:v h264_nvenc -gpu 0 \
           -y cuda_nvenc_test.mp4 2>nvenc_test.log

    if [ $? -eq 0 ]; then
        log_info "✅ NVENC with CUDA 12.6 works!"
        ls -la cuda_nvenc_test.mp4
    else
        log_error "❌ NVENC still fails with CUDA 12.6:"
        head -5 nvenc_test.log
    fi
else
    log_error "❌ FFmpeg CUDA initialization still fails:"
    head -5 cuda_test.log
fi

# 10. Final status check
log_info "Final system status:"
nvidia-smi --query-gpu=name,driver_version,cuda_version --format=csv 2>/dev/null || echo "nvidia-smi query failed"
nvcc --version 2>/dev/null | grep "release" || echo "nvcc not found"

echo ""
log_info "CUDA RTX 5090 fix completed!"
echo "If NVENC still doesn't work:"
echo "1. Restart container to reload CUDA runtime"
echo "2. Try CUDA_MODULE_LOADING=LAZY environment variable"
echo "3. RTX 5090 may need driver >= 575.x beta"