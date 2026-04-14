# Clash + YACD 镜像；COPY 的 preprocess 在 Windows 检出 CRLF 时由下一 RUN 去 \r，避免 ENTRYPOINT 报 no such file
FROM dreamacro/clash

# control ui
ARG YACD_VERSION=v0.3.8
ARG YACD_DOWNLOAD_URL="https://github.com/haishanh/yacd/releases/download/${YACD_VERSION}/yacd.tar.xz"

RUN wget -O /tmp/yacd.tar.xz ${YACD_DOWNLOAD_URL} \
    && mkdir -p /ui \
    && tar -xvf /tmp/yacd.tar.xz -C /ui \
    && rm -rf /tmp/yacd.tar.xz \
    && sed -i 's|data-base-url="http://127.0.0.1:9090"|data-base-url="http://localhost:9099"|g' /ui/public/index.html \
    && echo '<script>(function(){const urlParams=new URLSearchParams(window.location.search);const h=urlParams.get("hostname")||urlParams.get("host")||window.location.hostname+":9099";const b=h.includes(":")?"http://"+h:"http://"+h+":9099";const a=document.getElementById("app");if(a)a.setAttribute("data-base-url",b);setTimeout(function(){const a=document.getElementById("app");if(a)a.setAttribute("data-base-url",b);},50);})();</script>' >> /ui/public/index.html

# init config.yaml (strip CRLF so ENTRYPOINT works when repo is checked out on Windows)
COPY preprocess.sh /usr/bin/preprocess.sh
RUN sed -i 's/\r$//' /usr/bin/preprocess.sh && chmod +x /usr/bin/preprocess.sh

ENTRYPOINT [ "/usr/bin/preprocess.sh" ]
