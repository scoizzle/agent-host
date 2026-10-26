# syntax=docker/dockerfile:1
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
      git curl ca-certificates jq python3 tini procps util-linux \
 && rm -rf /var/lib/apt/lists/*

# Ubuntu 24.04 ships user "ubuntu" at uid 1000; replace it with "agent"
RUN userdel -r ubuntu 2>/dev/null || true; useradd -m -u 1000 -s /bin/bash agent \
 && mkdir -p /work && chown agent:agent /work

COPY --chmod=0755 bin/runner /usr/local/bin/runner
COPY --chmod=0755 entrypoint.sh /usr/local/bin/entrypoint.sh

USER agent
WORKDIR /home/agent
ENV PATH=/home/agent/.local/bin:/usr/local/bin:/usr/bin:/bin

# Cursor CLI -> ~/.local/bin/{agent,cursor-agent}. Skippable for CI self-test.
ARG INSTALL_CURSOR=1
RUN if [ "$INSTALL_CURSOR" = 1 ]; then curl -fsSL https://cursor.com/install | bash && ~/.local/bin/cursor-agent --version; fi

# Mount points for named volumes (pre-created so they're owned by agent)
RUN mkdir -p ~/.cursor ~/.config ~/.runner-runs /work

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["worker"]
