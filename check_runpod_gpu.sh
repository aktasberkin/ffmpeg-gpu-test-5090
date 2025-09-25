#!/bin/bash
# Check RunPod GPU Setup

echo "=== RunPod GPU Setup Check ==="

echo "1. Available devices:"
ls -la /dev/nvidia* /dev/dri/* 2>/dev/null || echo "No GPU devices found"

echo -e "\n2. GPU processes:"
ps aux | grep -i nvidia || echo "No nvidia processes"

echo -e "\n3. Environment variables:"
env | grep -i nvidia

echo -e "\n4. CUDA installation:"
which nvcc || echo "nvcc not found"
which nvidia-smi || echo "nvidia-smi not found"

echo -e "\n5. Container runtime:"
if [ -f /.dockerenv ]; then
    echo "Running in Docker container"

    # Check if container has GPU access
    if [ -d "/proc/driver/nvidia" ]; then
        echo "✅ NVIDIA driver accessible"
    else
        echo "❌ NVIDIA driver NOT accessible"
    fi

    # Check docker runtime
    if command -v docker &> /dev/null; then
        echo "Docker available in container"
    else
        echo "Docker not available (normal)"
    fi
else
    echo "Not running in Docker container"
fi

echo -e "\n6. RunPod specific checks:"
if [ -f "/etc/runpod-release" ]; then
    echo "RunPod container detected"
    cat /etc/runpod-release
else
    echo "RunPod release info not found"
fi

echo -e "\n🔧 Solutions if no GPU found:"
echo "1. Stop current pod"
echo "2. Create new pod with GPU instance type (RTX 5090)"
echo "3. Ensure 'GPU Pod' not 'CPU Pod' is selected"
echo "4. Use template: runpod/pytorch:2.8.0-py3.11-cuda12.8.1-cudnn-devel-ubuntu22.04"
echo "5. Set environment variables as suggested"

echo -e "\n=== Check Complete ==="