#!/bin/bash
# Build Custom RTX 5090 Template for RunPod

echo "=== Building RTX 5090 FFmpeg NVENC Template ==="

# 1. Build Docker image
echo "1. Building Docker image..."
docker build -t rtx5090-ffmpeg-nvenc -f runpod_custom_template.dockerfile .

if [ $? -eq 0 ]; then
    echo "✅ Docker image built successfully"

    # 2. Test image locally (if NVIDIA Docker is available)
    echo "2. Testing image..."
    docker run --rm --gpus all rtx5090-ffmpeg-nvenc:latest \
        ffmpeg -hide_banner -f lavfi -i testsrc2=size=320x240:rate=15:duration=2 \
        -c:v h264_nvenc -preset p7 -y test_output.mp4 2>/dev/null

    if [ $? -eq 0 ]; then
        echo "✅ NVENC test passed in container"
    else
        echo "⚠️  NVENC test failed (normal if no GPU locally)"
    fi

    # 3. Push to registry (optional)
    read -p "Push to Docker registry? (y/N): " push_confirm
    if [[ $push_confirm =~ ^[Yy]$ ]]; then
        echo "3. Pushing to registry..."
        # Replace with your registry
        docker tag rtx5090-ffmpeg-nvenc your-registry/rtx5090-ffmpeg-nvenc:latest
        docker push your-registry/rtx5090-ffmpeg-nvenc:latest
    fi

else
    echo "❌ Docker build failed"
    exit 1
fi

echo ""
echo "=== Custom Template Ready ==="
echo "Use this image in RunPod:"
echo "- Image: rtx5090-ffmpeg-nvenc:latest"
echo "- GPU: RTX 5090"
echo "- Container Disk: 50GB+"
echo "- Expose HTTP: 8888 (for monitoring)"