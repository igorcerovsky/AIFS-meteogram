FROM python:3.11-slim

# Install system dependencies (fonts for matplotlib)
RUN apt-get update && apt-get install -y --no-install-recommends \
    fonts-dejavu-core \
    && rm -rf /var/lib/apt/lists/*

# Set up a new user with UID 1000 (recommended by Hugging Face Spaces)
RUN useradd -m -u 1000 user
USER user
ENV HOME=/home/user \
    PATH=/home/user/.local/bin:$PATH \
    PORT=7860 \
    PYTHONUNBUFFERED=1

WORKDIR $HOME/app

# Install Python requirements
COPY --chown=user:user server/requirements.txt requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# Copy application files
COPY --chown=user:user server/ server/
COPY --chown=user:user web/ web/
COPY --chown=user:user assets/ assets/

# Create local cache directory
RUN mkdir -p .cache

EXPOSE 7860

CMD ["python", "server/server.py", "7860"]
