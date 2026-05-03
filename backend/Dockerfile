# Sakinah backend — Hugging Face Spaces Docker image.
#
# Image layout:
#   - Python 3.11-slim base (~50 MB)
#   - OS deps for OpenCV / Pillow / hsemotion (~100 MB)
#   - Python deps including PyTorch CPU wheels (~700 MB)
#   - The backend source itself (small)
# Total compressed image is ~1.2 GB; uncompressed ~2.5 GB. Well within
# Hugging Face Spaces' free-tier 16 GB RAM and the 50 GB image quota.
#
# On first request the runtime will download:
#   - HSEmotion enet_b2_8 ONNX (~30 MB)
#   - DistilRoBERTa-emotion (~270 MB)
#   - sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2 (~120 MB)
# Cached under /tmp/huggingface so subsequent boots are fast.

FROM python:3.11-slim

# OS dependencies for OpenCV / Pillow / hsemotion-onnx.
RUN apt-get update && apt-get install -y --no-install-recommends \
    libglib2.0-0 \
    libgl1 \
    libsm6 \
    libxext6 \
    libxrender1 \
    libgomp1 \
 && rm -rf /var/lib/apt/lists/*

# HF Spaces best practice: run as a non-root user so the writable
# layer is bounded to /home/user. UID 1000 matches HF's expectations.
RUN useradd -m -u 1000 user
USER user
ENV PATH="/home/user/.local/bin:$PATH"

WORKDIR /app

# HuggingFace + Torch caches under /tmp so the writable layer doesn't
# blow up. HF Spaces persist /tmp between cold starts on the same
# replica, so first-request model downloads stay warm.
ENV HF_HOME=/tmp/huggingface
ENV TRANSFORMERS_CACHE=/tmp/huggingface
ENV TORCH_HOME=/tmp/torch

# Force UTF-8 stdout/stderr so emoji in journal entries don't crash the
# request handler. Unbuffered output makes Space build logs readable.
ENV PYTHONIOENCODING=utf-8
ENV PYTHONUNBUFFERED=1

# Install Python deps. CPU torch wheels — the GPU wheels are ~3 GB and
# HF Spaces free tier doesn't offer GPU anyway.
COPY --chown=user requirements.txt requirements.txt
RUN pip install --no-cache-dir --user \
    --index-url https://download.pytorch.org/whl/cpu \
    --extra-index-url https://pypi.org/simple/ \
    -r requirements.txt

# Copy the backend source. .dockerignore keeps __pycache__, .venv,
# secret files etc. out of the image.
COPY --chown=user . /app

# HF Spaces routes external traffic to port 7860.
ENV PORT=7860
EXPOSE 7860

# Single Uvicorn worker — the multi-modal pipeline holds large models in
# memory and a second worker would double the RAM footprint without
# improving throughput on the free tier.
CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port ${PORT}"]
