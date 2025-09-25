# RunPod RTX 5090 Test Deployment Guide

## Step 1: RunPod Setup

### Launch Instance
1. Go to [RunPod.io](https://runpod.io)
2. Select **RTX 5090** instance
3. Choose template: **CUDA 12.1+ PyTorch** veya **Base Ubuntu**
4. Minimum specs:
   - **GPU**: RTX 5090 (32GB VRAM)
   - **CPU**: 16+ cores
   - **RAM**: 32GB+
   - **Storage**: 100GB+ SSD

### Connect to Instance
```bash
# SSH connection (RunPod provides this)
ssh -p [PORT] root@[HOST].runpod.io

# Or use RunPod web terminal
```

## Step 2: Environment Setup

### Upload Setup Script
```bash
# Option 1: Download from GitHub (if hosted)
wget https://raw.githubusercontent.com/your-repo/setup_runpod_environment.sh

# Option 2: Copy-paste content
nano setup_runpod_environment.sh
# Paste the script content
chmod +x setup_runpod_environment.sh
```

### Run Setup
```bash
# Execute setup script
./setup_runpod_environment.sh

# Monitor progress
tail -f /var/log/setup.log
```

## Step 3: Upload Test Scripts

### Transfer Files
```bash
# From local machine
scp -P [PORT] rtx5090_hls_test.sh root@[HOST].runpod.io:/workspace/rtx5090-test/

# Or create directly on RunPod
cd /workspace/rtx5090-test
nano rtx5090_hls_test.sh
# Paste optimized script content
chmod +x rtx5090_hls_test.sh
```

## Step 4: Run Tests

### Quick Verification
```bash
cd /workspace/rtx5090-test

# 1. Quick benchmark
./quick_benchmark.sh

# 2. Check GPU
nvidia-smi

# 3. Test FFmpeg NVENC
ffmpeg -encoders | grep nvenc
```

### Full Test Execution
```bash
# Start monitoring
./monitor_system.sh

# Run main test (in another terminal)
./rtx5090_hls_test.sh

# Monitor progress
tail -f outputs/logs/encoder1.log
tail -f gpu_metrics.log
```

## Step 5: Results Collection

### Monitor Real-time
```bash
# GPU utilization
watch -n 1 nvidia-smi

# Process count
watch -n 1 'ps aux | grep ffmpeg | wc -l'

# Output files
watch -n 5 'find outputs/ -name "*.m3u8" | wc -l'
```

### Collect Results
```bash
# Create results package
tar -czf rtx5090_test_results.tar.gz \
    outputs/ \
    gpu_metrics.log \
    gpu_memory.log \
    cpu_usage.log \
    io_stats.log

# Download results
# Use RunPod file manager or scp
```

## Expected Results

### Success Indicators
- ✅ 180 concurrent FFmpeg processes (60 per encoder)
- ✅ GPU utilization > 90%
- ✅ All 3 NVENC encoders active
- ✅ 180 .m3u8 files generated
- ✅ No dropped frames in logs

### Performance Metrics
- **Concurrent Streams**: 180 (target)
- **GPU Utilization**: 90%+
- **Memory Usage**: <30GB VRAM
- **Processing Speed**: Real-time (1x)
- **Output Quality**: 720p@30fps HLS

## Troubleshooting

### Common Issues
1. **NVENC not found**: Check CUDA/driver versions
2. **Out of memory**: Reduce streams per encoder
3. **File descriptor limit**: Check ulimit settings
4. **Slow performance**: Monitor I/O bottlenecks

### Debug Commands
```bash
# Check NVENC availability
nvidia-ml-py3 # Python GPU monitoring

# Monitor resources
htop
iotop -a
nvtop  # If available

# Check logs
grep -i error outputs/logs/*.log
dmesg | tail -20
```

## Cost Optimization

### RunPod Pricing (Estimated)
- **RTX 5090**: $2.50-4.00/hour
- **Test Duration**: 3-10 minutes
- **Total Cost**: $0.20-0.70 per test run

### Tips
1. Use **Spot instances** (cheaper)
2. Run tests during **off-peak hours**
3. **Terminate** instance immediately after test
4. **Snapshot** configured environment for future use

## Results Analysis

### Key Metrics to Collect
1. **Maximum concurrent streams achieved**
2. **GPU utilization percentage**
3. **Memory usage pattern**
4. **Processing latency**
5. **Error rate**
6. **Thermal throttling** (if any)

This will provide definitive data on RTX 5090's FFmpeg concurrent processing capabilities!