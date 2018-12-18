ARG ALPINE_VERSION=3.8

########################
# Build pagespeed psol #
########################
FROM alpine:$ALPINE_VERSION as pagespeed

# Check https://github.com/apache/incubator-pagespeed-mod/tags
ARG MOD_PAGESPEED_TAG=v1.13.35.2

RUN apk add --no-cache \
        apache2-dev \
        apr-dev \
        apr-util-dev \
        build-base \
        curl \
        gettext-dev \
        git \
        gperf \
        icu-dev \
        libjpeg-turbo-dev \
        libpng-dev \
        libressl-dev \
        pcre-dev \
        py-setuptools \
        zlib-dev \
    ;

WORKDIR /usr/src
RUN git clone -b ${MOD_PAGESPEED_TAG} \
              --recurse-submodules \
              --depth=1 \
              -c advice.detachedHead=false \
              -j`nproc` \
              https://github.com/apache/incubator-pagespeed-mod.git \
              modpagespeed \
    ;

WORKDIR /usr/src/modpagespeed

COPY patches/modpagespeed/*.patch ./

RUN for i in *.patch; do printf "\r\nApplying patch ${i%%.*}\r\n"; patch -p1 < $i || exit 1; done

WORKDIR /usr/src/modpagespeed/tools/gyp
RUN ./setup.py install

WORKDIR /usr/src/modpagespeed

RUN build/gyp_chromium --depth=. \
                       -D use_system_libs=1 \
    && \
    cd /usr/src/modpagespeed/pagespeed/automatic && \
    make psol BUILDTYPE=Release \
              CFLAGS+="-I/usr/include/apr-1" \
              CXXFLAGS+="-I/usr/include/apr-1 -DUCHAR_TYPE=uint16_t" \
              -j`nproc` \
    ;

RUN mkdir -p /usr/src/ngxpagespeed/psol/lib/Release/linux/x64 && \
    mkdir -p /usr/src/ngxpagespeed/psol/include/out/Release && \
    cp -R out/Release/obj /usr/src/ngxpagespeed/psol/include/out/Release/ && \
    cp -R pagespeed/automatic/pagespeed_automatic.a /usr/src/ngxpagespeed/psol/lib/Release/linux/x64/ && \
    cp -R net \
          pagespeed \
          testing \
          third_party \
          url \
          /usr/src/ngxpagespeed/psol/include/ \
    ;

##########################################
# Build Nginx with support for PageSpeed #
##########################################
FROM alpine:$ALPINE_VERSION AS nginx
ARG NGX_PAGESPEED_TAG=v1.13.35.2-stable
ARG RESTY_VERSION="1.13.6.1"
ARG RESTY_LUAROCKS_VERSION="2.4.3"
ARG RESTY_OPENSSL_VERSION="1.0.2k"
ARG RESTY_PCRE_VERSION="8.41"
ARG RESTY_J="1"
ARG RESTY_CONFIG_OPTIONS="\
    --with-file-aio \
    --with-http_addition_module \
    --with-http_auth_request_module \
    --with-http_dav_module \
    --with-http_flv_module \
    --with-http_geoip_module=dynamic \
    --with-http_gunzip_module \
    --with-http_gzip_static_module \
    --with-http_image_filter_module=dynamic \
    --with-http_mp4_module \
    --with-http_random_index_module \
    --with-http_realip_module \
    --with-http_secure_link_module \
    --with-http_slice_module \
    --with-http_ssl_module \
    --with-http_stub_status_module \
    --with-http_sub_module \
    --with-http_v2_module \
    --with-http_xslt_module=dynamic \
    --with-ipv6 \
    --with-mail \
    --with-mail_ssl_module \
    --with-md5-asm \
    --with-pcre-jit \
    --with-sha1-asm \
    --with-stream \
    --with-stream_ssl_module \
    --with-threads \
    --add-module=/tmp/ngxpagespeed \
    "
ARG RESTY_CONFIG_OPTIONS_MORE=""

# These are not intended to be user-specified
ARG _RESTY_CONFIG_DEPS="--with-openssl=/tmp/openssl-${RESTY_OPENSSL_VERSION} --with-pcre=/tmp/pcre-${RESTY_PCRE_VERSION}"

WORKDIR /tmp

RUN apk add --no-cache \
        apr-dev \
        apr-util-dev \
        build-base \
        ca-certificates \
        gd-dev \
        geoip-dev \
        git \
        gnupg \
        icu-dev \
        libjpeg-turbo-dev \
        libpng-dev \
        libxslt-dev \
        linux-headers \
        libressl-dev \
        pcre-dev \
        tar \
        zlib-dev \
    ;

RUN git clone -b ${NGX_PAGESPEED_TAG} \
              --recurse-submodules \
              --shallow-submodules \
              --depth=1 \
              -c advice.detachedHead=false \
              -j`nproc` \
              https://github.com/apache/incubator-pagespeed-ngx.git \
              ngxpagespeed \
    ;
COPY --from=pagespeed /usr/src/ngxpagespeed /tmp/ngxpagespeed/

RUN && curl -fSL https://www.openssl.org/source/openssl-${RESTY_OPENSSL_VERSION}.tar.gz -o openssl-${RESTY_OPENSSL_VERSION}.tar.gz \
    && tar xzf openssl-${RESTY_OPENSSL_VERSION}.tar.gz \
    && curl -fSL https://ftp.pcre.org/pub/pcre/pcre-${RESTY_PCRE_VERSION}.tar.gz -o pcre-${RESTY_PCRE_VERSION}.tar.gz \
    && tar xzf pcre-${RESTY_PCRE_VERSION}.tar.gz \
    && curl -fSL https://openresty.org/download/openresty-${RESTY_VERSION}.tar.gz -o openresty-${RESTY_VERSION}.tar.gz \
    && tar xzf openresty-${RESTY_VERSION}.tar.gz \
    && cd /tmp/openresty-${RESTY_VERSION} \
    && ./configure -j${RESTY_J} ${_RESTY_CONFIG_DEPS} ${RESTY_CONFIG_OPTIONS} ${RESTY_CONFIG_OPTIONS_MORE} \
    && make -j${RESTY_J} \
    && make -j${RESTY_J} install \
    && cd /tmp \
    && rm -rf \
        openssl-${RESTY_OPENSSL_VERSION} \
        openssl-${RESTY_OPENSSL_VERSION}.tar.gz \
        openresty-${RESTY_VERSION}.tar.gz openresty-${RESTY_VERSION} \
        pcre-${RESTY_PCRE_VERSION}.tar.gz pcre-${RESTY_PCRE_VERSION}

##########################################
# Combine everything with minimal layers #
##########################################
FROM alpine:$ALPINE_VERSION
LABEL maintainer="11415191465@qq.com" \
      version.mod-pagespeed="1.13.35.2" \
      version.ngx-pagespeed="1.13.35.2"

COPY --from=pagespeed /usr/bin/envsubst /usr/local/bin
COPY --from=nginx /usr/local/openresty /usr/local/openresty
COPY nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
COPY nginx.vh.default.conf /etc/nginx/conf.d/default.conf
ENV PATH=$PATH:/usr/local/openresty/luajit/bin:/usr/local/openresty/nginx/sbin:/usr/local/openresty/bin
RUN  ln -sf /dev/stdout /var/log/nginx/access.log 
RUN  ln -sf /dev/stderr /var/log/nginx/error.log

EXPOSE 80

STOPSIGNAL SIGQUIT

CMD ["/usr/local/openresty/bin/openresty", "-g", "daemon off;"]
