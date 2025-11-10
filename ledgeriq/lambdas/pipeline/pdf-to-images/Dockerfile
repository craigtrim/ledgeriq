# AWS Lambda Python 3.11 ARM64 base (keep your local tag if you have one)
FROM lambda-base:3.11-arm64

# Faster, quieter pip
ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONUNBUFFERED=1

# Install poppler for pdf2image (works on AL2023 or AL2)
RUN (command -v dnf >/dev/null 2>&1 && dnf -y install poppler-utils && dnf clean all) \
 || (yum -y install poppler-utils && yum clean all)

# Install Python deps directly (no requirements.txt)
# Pillow is required by pdf2image
RUN pip install --upgrade pip && \
    pip install pdf2image pillow

# Copy only what changes often last to keep cache
WORKDIR ${LAMBDA_TASK_ROOT}
COPY lambda_function.py .

# If your code references pdftoppm implicitly, this helps in some envs
ENV POPPLER_PATH=/usr/bin

# Lambda entrypoint
CMD [ "lambda_function.handler" ]
