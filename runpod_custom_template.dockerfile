# RTX 5090 FFmpeg NVENC Custom Template
FROM runpod/pytorch:2.8.0-py3.11-cuda12.8.1-cudnn-devel-ubuntu22.04

# Set RTX 5090 environment variables
ENV NVIDIA_DRIVER_CAPABILITIES=compute,video,utility
ENV NVIDIA_VISIBLE_DEVICES=all
ENV CUDA_VISIBLE_DEVICES=0
ENV NVIDIA_REQUIRE_CUDA="cuda>=12.8,driver>=570"
ENV CUDA_MODULE_LOADING=LAZY

# Update and install essential packages
RUN apt-get update && apt-get install -y \
    wget \
    build-essential \
    pkg-config \
    yasm \
    nasm \
    cmake \
    git \
    && rm -rf /var/lib/apt/lists/*

# Install NVIDIA Video Codec SDK headers for RTX 5090
RUN cd /tmp && \
    wget -q https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/libnvidia-encode-570_570.172.08-0ubuntu1_amd64.deb && \
    wget -q https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/libnvidia-decode-570_570.172.08-0ubuntu1_amd64.deb && \
    dpkg -i --force-depends *.deb || apt-get install -f -y && \
    rm -f *.deb

# Download and install Video Codec SDK headers
RUN cd /tmp && \
    git clone https://github.com/FFmpeg/nv-codec-headers.git && \
    cd nv-codec-headers && \
    make install PREFIX=/usr/local && \
    cd / && rm -rf /tmp/nv-codec-headers

# Compile FFmpeg with RTX 5090 optimized NVENC support
RUN cd /tmp && \
    wget -q https://ffmpeg.org/releases/ffmpeg-7.1.tar.xz && \
    tar -xf ffmpeg-7.1.tar.xz && \
    cd ffmpeg-7.1 && \
    ./configure \
        --enable-cuda-nvcc \
        --enable-cuvid \
        --enable-nvenc \
        --enable-nonfree \
        --enable-libnpp \
        --extra-cflags=-I/usr/local/cuda/include \
        --extra-ldflags=-L/usr/local/cuda/lib64 \
        --nvccflags="-gencode arch=compute_89,code=sm_89" \
        --disable-static \
        --enable-shared && \
    make -j$(nproc) && \
    make install && \
    ldconfig && \
    cd / && rm -rf /tmp/ffmpeg-*

# Create workspace directory
WORKDIR /workspace

# Copy project files
COPY . /workspace/

# Set executable permissions for scripts
RUN chmod +x /workspace/*.sh

# Test NVENC on container start
CMD ["/bin/bash", "-c", "echo 'RTX 5090 FFmpeg NVENC Container Ready' && /workspace/nvenc_570_workaround.sh && /bin/bash"]