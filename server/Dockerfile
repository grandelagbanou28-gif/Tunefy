FROM python:3.12-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install yt-dlp from official GitHub release
RUN curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp \
    && chmod +x /usr/local/bin/yt-dlp

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py .

EXPOSE 8080
# Shell form so $PORT is expanded: Render (and Railway/Fly) inject the port to
# bind; local runs fall back to 8080. Exec form would bake in a fixed port and
# fail the platform health check.
CMD uvicorn main:app --host 0.0.0.0 --port ${PORT:-8080}
