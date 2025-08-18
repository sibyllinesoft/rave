FROM ubuntu:22.04

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV NODE_VERSION=20
ENV CLAUDE_CODE_VERSION=latest

# Install system dependencies (excluding nodejs/npm initially)
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    git \
    build-essential \
    python3 \
    python3-pip \
    docker.io \
    docker-compose \
    ca-certificates \
    gnupg \
    lsb-release \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Remove any existing Node.js packages to avoid conflicts
RUN apt-get update && apt-get remove -y nodejs npm libnode-dev || true \
    && apt-get autoremove -y \
    && apt-get autoclean

# Install Node.js 20 from NodeSource
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install Bun
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:$PATH"

# Install Claude Code CLI
RUN npm install -g @anthropic-ai/claude-code

# Create .claude directory for user configuration
RUN mkdir -p /root/.claude

# Clone claude-code-studio to ~/.claude (correct location)
RUN git clone https://github.com/arnaldo-delisio/claude-code-studio.git /tmp/claude-code-studio \
    && cp -r /tmp/claude-code-studio/* /root/.claude/ \
    && rm -rf /tmp/claude-code-studio

# Install Graphite CLI
RUN npm install -g @withgraphite/graphite-cli@stable

# Clone and setup Vibe Kanban
RUN git clone https://github.com/BloopAI/vibe-kanban.git /opt/vibe-kanban
WORKDIR /opt/vibe-kanban

# Install Vibe Kanban dependencies and build
RUN npm install && npm run build

# Create workspace directory
WORKDIR /workspace

# Copy configuration files
COPY scripts/ /opt/scripts/
COPY config/ /opt/config/

# Make scripts executable
RUN chmod +x /opt/scripts/*.sh

# Expose Vibe Kanban port
EXPOSE 3000

# Set the default command
CMD ["/opt/scripts/start.sh"]