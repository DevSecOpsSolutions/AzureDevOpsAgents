# Base image: Ubuntu 24.04 LTS
FROM ubuntu:24.04

# Set target architecture for Azure DevOps agent
ENV TARGETARCH="linux-x64"

# Set non-interactive mode for apt-get
ENV DEBIAN_FRONTEND=noninteractive

# Configure apt to assume "yes" by default
RUN echo "APT::Get::Assume-Yes \"true\";" > /etc/apt/apt.conf.d/90assumeyes

# Install essential system packages and build tools
RUN apt-get update && apt-get upgrade -y && apt-get install -y --no-install-recommends \
    curl \
    git \
    jq \
    libicu74 \
    unzip \
    apt-utils \
    iputils-ping \
    libcurl4 \
    libunwind8 \
    netcat-openbsd \
    libssl3 \
    liblttng-ust1 \
    libkrb5-3 \
    zlib1g \
    libc-bin \
    libseccomp2 \
    nftables \
    iptables \
		sudo \
		gnupg2 \
		software-properties-common \
		nano \
		ca-certificates \
		apt-transport-https \
		lsb-release \
		cron \
		systemd \
		wget \
    ssh \
    sshpass \
	&& rm -rf /var/lib/apt/lists/*

# Install Azure CLI
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash && rm -rf /var/lib/apt/lists/*

# Add Docker GPG key
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# Add Docker repository matching the image architecture and Ubuntu release
RUN echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo \"$VERSION_CODENAME\") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine for Docker-in-Docker support
RUN apt-get update && apt-get install -y --no-install-recommends docker-ce docker-ce-cli containerd.io && rm -rf /var/lib/apt/lists/*

# Install Docker Compose v2.24.0
RUN curl -L "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose && chmod +x /usr/local/bin/docker-compose

# Add Node.js 20.x LTS repository
RUN curl -sL https://deb.nodesource.com/setup_20.x | bash -

# Install Node.js and Python pip
RUN apt-get update && apt-get install -y --no-install-recommends nodejs python3-pip && rm -rf /var/lib/apt/lists/*

# Add Microsoft package repository for .NET (optional - for build tasks)
RUN wget https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb -O packages-microsoft-prod.deb && \
    dpkg -i packages-microsoft-prod.deb && \
    rm packages-microsoft-prod.deb

# Install .NET 8.0 SDK for build tasks (agent will handle its own .NET runtime)
RUN apt-get update && \
    apt-get install -y dotnet-sdk-8.0 && \
    rm -rf /var/lib/apt/lists/*

# Create crontab file for root
RUN touch /var/spool/cron/crontabs/root && \
    chmod 600 /var/spool/cron/crontabs/root && \
    chown root:crontab /var/spool/cron/crontabs/root

# Schedule service health monitoring and Docker cleanup (every minute)
RUN (crontab -l 2>/dev/null || true; echo '* * * * * /azp/service_health.sh >> /var/log/service_health.log 2>&1') | crontab - && \
    (crontab -l 2>/dev/null || true; echo '* * * * * /azp/dockercleanup.sh') | crontab -

# Set working directory
WORKDIR /azp

# Azure DevOps agent version
ARG AGENT_VERSION=4.271.0

# Download and extract Azure DevOps agent
RUN curl -LsS "https://download.agent.dev.azure.com/agent/${AGENT_VERSION}/vsts-agent-linux-x64-${AGENT_VERSION}.tar.gz" | tar -xz

# Copy agent startup script
COPY ./start.sh .

# Copy service health monitoring script
COPY ./service_health.sh .

# Copy Docker cleanup script
COPY ./dockercleanup.sh .

# Make scripts executable
RUN chmod +x start.sh service_health.sh dockercleanup.sh

# Start the Azure DevOps agent
CMD ["./start.sh"]
