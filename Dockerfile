FROM ubuntu:20.04

# To make it easier for build and release pipelines to run apt-get,
# configure apt to not require confirmation (assume the -y argument by default)
ENV DEBIAN_FRONTEND=noninteractive
RUN echo "APT::Get::Assume-Yes \"true\";" > /etc/apt/apt.conf.d/90assumeyes

RUN apt-get update && apt-get install -y --no-install-recommends \
    apt-utils \
    curl \
    jq \
    unzip \
    git \
    iputils-ping \
    libcurl4 \
    libunwind8 \
    netcat \
    libssl1.0 \
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

RUN curl -LsS https://aka.ms/InstallAzureCLIDeb | bash && rm -rf /var/lib/apt/lists/*


RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
RUN add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"

RUN apt-get update && apt-get install -y --no-install-recommends docker-ce docker-ce-cli containerd.io

RUN apt-get update

RUN curl -sL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | tee /etc/apt/trusted.gpg.d/microsoft.gpg > /dev/null
	
RUN echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ `lsb_release -cs` main" | tee /etc/apt/sources.list.d/azure-cli.list

RUN apt-get update && apt-get install -y azure-cli

RUN curl -L "https://github.com/docker/compose/releases/download/v2.1.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
RUN chmod +x /usr/local/bin/docker-compose

RUN curl -sL https://deb.nodesource.com/setup_12.x | sudo -E bash -
RUN apt-get update 
RUN apt install -y --no-install-recommends nodejs

RUN wget https://packages.microsoft.com/config/ubuntu/20.04/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
RUN dpkg -i packages-microsoft-prod.deb
RUN apt-get update && \
    apt-get install -y apt-transport-https && \
    apt-get update && \
    apt-get install -y dotnet-sdk-5.0 && \
	  apt-get install -y aspnetcore-runtime-5.0 && apt-get install python3-pip

    
RUN touch /var/spool/cron/crontabs/root
RUN chmod 600 root
RUN chown root:crontab root
RUN crontab -l | { cat; echo '* * * * * /azp/service_health.sh >> /var/log/service_health.log 2>&1';} | crontab -
RUN crontab -l | { cat; echo '* * * * * /azp/dockercleanup.sh';} | crontab -

ARG TARGETARCH=amd64
ARG AGENT_VERSION=2.195.0

WORKDIR /azp

RUN if [ "$TARGETARCH" = "amd64" ]; then \
      AZP_AGENTPACKAGE_URL=https://vstsagentpackage.azureedge.net/agent/${AGENT_VERSION}/vsts-agent-linux-x64-${AGENT_VERSION}.tar.gz; \
    else \
      AZP_AGENTPACKAGE_URL=https://vstsagentpackage.azureedge.net/agent/${AGENT_VERSION}/vsts-agent-linux-${TARGETARCH}-${AGENT_VERSION}.tar.gz; \
    fi; \
    curl -LsS "$AZP_AGENTPACKAGE_URL" | tar -xz

COPY ./start.sh .
COPY ./service_health.sh .
COPY ./dockercleanup.sh .

RUN chmod +x start.sh
RUN chmod +x service_health.sh
RUN chmod +x dockercleanup.sh

CMD ["./start.sh"]
