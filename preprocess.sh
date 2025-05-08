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
    
    wget -O /root/.config/clash/config.yaml "http://subconverter:25500/sub?target=clash&url=${ENCODED_URL}"
fi

# Switch to the container command
exec /clash -ext-ui /ui/public