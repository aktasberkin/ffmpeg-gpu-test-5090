# Claude Code - FFmpeg GPU Test 5090 Project

## 📋 Project Overview

Bu proje RTX 5090 GPU'nun FFmpeg ile concurrent stream transcoding performansını test etmek için geliştirilmiştir. Temel hedef: **2,400 kamera** concurrent olarak **1080p@30fps → 720p@30fps** transcoding yapabilme kapasitesini ölçmek.

## 🎯 Test Hedefleri

- **RTX 5090'ın 3 NVENC encoder**'ını parallel kullanma
- Her encoder **60+ concurrent stream** işleme
- **HLS output** (m3u8 + ts segments) oluşturma
- **GPU utilization** ve **memory usage** monitoring
- **Real-world performance** benchmarking

## 📁 Dosya Yapısı ve Açıklamaları

### 🔍 Research & Documentation
- [`nvidia-rtx-5090-research.md`](./nvidia-rtx-5090-research.md) - RTX 5090 GPU özellikleri, NVENC kapasitesi, teknik özellikler
- [`conversation-history.txt`](./conversation-history.txt) - Proje geliştirme süreci, tartışmalar, çözüm arayışları (uzun dosya)
- [`runpod_deployment_guide.md`](./runpod_deployment_guide.md) - RunPod cloud GPU deployment rehberi

### 🚀 Test Scripts
- [`rtx5090_hls_test.sh`](./rtx5090_hls_test.sh) - **Ana test script** (3 encoder, 180 concurrent stream)
- [`rtx5090_hls_test_docker.sh`](./rtx5090_hls_test_docker.sh) - Docker container uyumlu versiyon
- [`debug_test.sh`](./debug_test.sh) - Step-by-step debugging ve validation

### 🔧 Setup & Fix Scripts
- [`setup_runpod_environment.sh`](./setup_runpod_environment.sh) - RunPod ortam hazırlama (CUDA, FFmpeg, optimizations)
- [`fix_nvenc_rtx5090.sh`](./fix_nvenc_rtx5090.sh) - NVENC SDK compatibility düzeltmeleri
- [`manual_nvenc_fix.sh`](./manual_nvenc_fix.sh) - **Manuel NVENC header** kurulumu (RTX 5090 için)
- [`diagnose_nvenc.sh`](./diagnose_nvenc.sh) - NVENC sorun teşhis aracı

### 🧪 Utility Scripts
- [`test_file_access.sh`](./test_file_access.sh) - Concurrent file access performance testi

## 🎮 Hızlı Başlangıç

### 1. RunPod Setup
```bash
# RTX 5090 instance kirala
# Repository clone et
git clone https://github.com/aktasberkin/ffmpeg-gpu-test-5090.git
cd ffmpeg-gpu-test-5090

# Environment hazırla
./setup_runpod_environment.sh
```

### 2. NVENC Sorun Giderme
```bash
# NVENC durumu kontrol et
./diagnose_nvenc.sh

# NVENC düzelt
./manual_nvenc_fix.sh

# Test et
./debug_test.sh
```

### 3. Ana Test Çalıştır
```bash
# 180 concurrent stream test
./rtx5090_hls_test.sh

# Monitor GPU usage
watch -n 1 nvidia-smi
```

## ⚠️ Bilinen Sorunlar

### RTX 5090 NVENC Compatibility
**Sorun**: `OpenEncodeSessionEx failed: unsupported device (2)`
**Sebep**: RTX 5090 çok yeni, NVENC SDK headers eksik
**Çözüm**: [`manual_nvenc_fix.sh`](./manual_nvenc_fix.sh) çalıştır

### Container Runtime Issues
**Sorun**: `System has not been booted with systemd`
**Sebep**: RunPod container'da systemd yok
**Çözüm**: Script'ler container-compatible yapıldı

### Memory Allocation Errors
**Sorun**: `malloc of size X failed`
**Sebep**: Çok fazla concurrent process
**Çözüm**: Stream sayısı kademeli artırılmalı

## 📊 Beklenen Sonuçlar

### RTX 5090 Teorik Kapasite
- **3 NVENC Encoder** × **60-80 stream/encoder** = **180-240 concurrent stream**
- **GPU Memory**: 32GB GDDR7
- **Memory Bandwidth**: 1792 GB/s
- **NVENC Version**: 9. nesil

### Performance Metrikleri
- **Target**: 180 concurrent streams (60 per encoder)
- **Input**: 1080p@30fps (8Mbps per stream)
- **Output**: 720p@30fps (2-3Mbps per stream)
- **Format**: HLS (m3u8 + ts segments)

## 🔄 Development Workflow

### Commit Pattern
```bash
# Her değişiklikten sonra
git add .
git commit -m "Descriptive commit message with 🤖 Claude Code footer"
git push
```

### Testing Cycle
1. **Diagnose** → `./diagnose_nvenc.sh`
2. **Fix** → `./manual_nvenc_fix.sh`
3. **Debug** → `./debug_test.sh`
4. **Test** → `./rtx5090_hls_test.sh`
5. **Monitor** → `nvidia-smi`, `nvtop`

## 🎛️ Script Parameters

### Ana Test Ayarları
```bash
STREAMS_PER_ENCODER=60  # Her encoder için stream sayısı
INPUT_FILE="test_1080p_30fps.mp4"  # Test video dosyası
BASE_DIR="outputs"  # Output klasörü
```

### NVENC Optimizations
```bash
-surfaces 32          # GPU buffer count
-async_depth 2        # Async processing depth
-preset p1           # En hızlı preset
-rc_lookahead 0      # Memory tasarrufu
-spatial_aq 0        # GPU compute tasarrufu
```

## 🚨 Troubleshooting

### NVENC Çalışmıyor
1. Driver version: `nvidia-smi` (>=570.x gerekli)
2. Headers: `ls /usr/local/cuda/include/*nvenc*`
3. Libraries: `ldconfig -p | grep nvidia-encode`

### GPU Kullanımı Yok
1. Process durumu: `ps aux | grep ffmpeg`
2. GPU monitoring: `nvidia-smi dmon`
3. Error logs: `tail -f outputs/encoder*/stream*.log`

### Memory Issues
1. Available RAM: `free -h`
2. GPU Memory: `nvidia-smi --query-gpu=memory.used,memory.free --format=csv`
3. Process limits: `ulimit -a`

## 📈 Results Analysis

### Success Metrics
- ✅ **Concurrent Streams**: Target 180, achieved X
- ✅ **GPU Utilization**: Target >90%, achieved X%
- ✅ **Memory Usage**: <30GB VRAM used
- ✅ **Output Quality**: 720p@30fps HLS segments
- ✅ **Error Rate**: <1% dropped frames

### Log Files
```
outputs/
├── encoder1/           # Encoder 1 outputs
├── encoder2/           # Encoder 2 outputs
├── encoder3/           # Encoder 3 outputs
├── gpu_metrics.log     # GPU utilization data
├── gpu_memory.log      # Memory usage data
└── test_summary.txt    # Test sonuç özeti
```

## 🤖 Claude Code Integration

Bu proje [Claude Code](https://claude.ai/code) ile geliştirilmiştir. Her commit message'da proje damgası bulunur:

```
🤖 Generated with [Claude Code](https://claude.ai/code)
Co-Authored-By: Claude <noreply@anthropic.com>
```

## 📞 Support & Issues

Sorunlar için GitHub Issues kullanın:
- RTX 5090 NVENC compatibility
- RunPod container runtime issues
- Performance optimization requests

---

**Last Updated**: 2025-09-25
**Claude Code Version**: Sonnet 4 (claude-sonnet-4-20250514)