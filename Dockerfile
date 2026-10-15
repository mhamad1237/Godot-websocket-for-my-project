FROM debian:bookworm-slim
ARG GODOT_VERSION=4.3
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates wget unzip libfontconfig1 libx11-6 libxcursor1 libxinerama1 libxi6 libxrandr2 libgl1 libasound2 && rm -rf /var/lib/apt/lists/*
RUN wget -q "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" -O /tmp/godot.zip && unzip -q /tmp/godot.zip -d /tmp && mv "/tmp/Godot_v${GODOT_VERSION}-stable_linux.x86_64" /usr/local/bin/godot && chmod +x /usr/local/bin/godot && rm /tmp/godot.zip
WORKDIR /game
COPY . .
RUN godot --headless --path /game --import || true
EXPOSE 9080
CMD ["godot", "--headless", "--path", "/game", "res://scenes/server_boot.tscn", "--", "--server"]
