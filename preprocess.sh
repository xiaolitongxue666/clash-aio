#!/bin/sh

if [ ! -f /root/.config/clash/config.yaml ]; then
    # Check if RAW_SUB_URL is already URL encoded
    # If it contains characters like ':', '/', '?', '&', '=', etc., it's likely not encoded
    if echo "${RAW_SUB_URL}" | grep -q '[:/\?&=]'; then
        # URL encode RAW_SUB_URL
        ENCODED_URL=$(echo "${RAW_SUB_URL}" | sed -e 's/%/%25/g' \
            -e 's/ /%20/g' \
            -e 's/!/%21/g' \
            -e 's/"/%22/g' \
            -e 's/#/%23/g' \
            -e 's/\$/%24/g' \
            -e 's/&/%26/g' \
            -e "s/'/%27/g" \
            -e 's/(/%28/g' \
            -e 's/)/%29/g' \
            -e 's/\*/%2A/g' \
            -e 's/+/%2B/g' \
            -e 's/,/%2C/g' \
            -e 's/\//%2F/g' \
            -e 's/:/%3A/g' \
            -e 's/;/%3B/g' \
            -e 's/=/%3D/g' \
            -e 's/?/%3F/g' \
            -e 's/@/%40/g' \
            -e 's/\[/%5B/g' \
            -e 's/\]/%5D/g')
    else
        # Already encoded, use as is
        ENCODED_URL="${RAW_SUB_URL}"
    fi
    
    # Determine subconverter host - use IP from env if provided, otherwise try hostname
    SUB_HOST="subconverter"
    if [ -n "${SUBCONVERTER_IP}" ]; then
        SUB_HOST="${SUBCONVERTER_IP}"
    elif ! getent hosts subconverter >/dev/null 2>&1; then
        # Try to find IP by scanning common network ranges
        for ip in 5 6 7 8 9 10; do
            if wget -q -O- --timeout=2 "http://10.89.0.$ip:25500/version" >/dev/null 2>&1; then
                SUB_HOST="10.89.0.$ip"
                break
            fi
        done
        if [ "$SUB_HOST" = "subconverter" ]; then
            for ip in 2 3 4 5 6; do
                if wget -q -O- --timeout=2 "http://172.21.0.$ip:25500/version" >/dev/null 2>&1; then
                    SUB_HOST="172.21.0.$ip"
                    break
                fi
            done
        fi
    fi
    
    # Retry logic for downloading config
    MAX_RETRIES=15
    RETRY=0
    while [ $RETRY -lt $MAX_RETRIES ]; do
        if wget -O /root/.config/clash/config.yaml "http://${SUB_HOST}:25500/sub?target=clash&url=${ENCODED_URL}" 2>/dev/null; then
            if [ -f /root/.config/clash/config.yaml ] && [ -s /root/.config/clash/config.yaml ]; then
                break
            fi
        fi
        RETRY=$((RETRY + 1))
        sleep 2
    done
fi

# Switch to the container command
exec /clash -ext-ui /ui/public