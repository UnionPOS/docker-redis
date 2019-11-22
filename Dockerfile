FROM unionpos/ubuntu:16.04

# grab gosu for easy step-down from root
COPY --from=unionpos/gosu:1.11 /gosu /usr/local/bin/

ENV REDIS_VERSION 5.0.5
ENV REDIS_DOWNLOAD_URL http://download.redis.io/releases/redis-5.0.5.tar.gz
ENV REDIS_DOWNLOAD_SHA 2139009799d21d8ff94fc40b7f36ac46699b9e1254086299f8d3b223ca54a375

# add our user and group first to make sure their IDs get assigned consistently, regardless of whatever dependencies get added
RUN groupadd -r redis && useradd -r -g redis redis

# for redis-sentinel see: http://redis.io/topics/sentinel
RUN set -ex \
	&& buildDeps=' \
	gcc \
	libc6-dev \
	make \
	wget \
	' \
	&& apt-get update \
	&& apt-get install -y $buildDeps --no-install-recommends \
	&& wget -O redis.tar.gz "$REDIS_DOWNLOAD_URL" \
	&& echo "$REDIS_DOWNLOAD_SHA *redis.tar.gz" | sha256sum -c - \
	&& mkdir -p /usr/src/redis \
	&& tar -xzf redis.tar.gz -C /usr/src/redis --strip-components=1 \
	&& rm redis.tar.gz \
	# disable Redis protected mode [1] as it is unnecessary in context of Docker
	# (ports are not automatically exposed when running inside Docker, but rather explicitly by specifying -p / -P)
	# [1]: https://github.com/antirez/redis/commit/edd4d555df57dc84265fdfb4ef59a4678832f6da
	&& grep -q '^#define CONFIG_DEFAULT_PROTECTED_MODE 1$' /usr/src/redis/src/server.h \
	&& sed -ri 's!^(#define CONFIG_DEFAULT_PROTECTED_MODE) 1$!\1 0!' /usr/src/redis/src/server.h \
	&& grep -q '^#define CONFIG_DEFAULT_PROTECTED_MODE 0$' /usr/src/redis/src/server.h \
	# for future reference, we modify this directly in the source instead of just supplying a default configuration flag because apparently "if you specify any argument to redis-server, [it assumes] you are going to specify everything"
	# see also https://github.com/docker-library/redis/issues/4#issuecomment-50780840
	# (more exactly, this makes sure the default behavior of "save on SIGTERM" stays functional by default)
	&& make -C /usr/src/redis -j "$(nproc)" \
	&& make -C /usr/src/redis install \
	&& rm -r /usr/src/redis \
	&& apt-get purge -y --auto-remove $buildDeps \
	&& rm -rf /var/lib/apt/lists/*

RUN mkdir /data && chown redis:redis /data
VOLUME /data
WORKDIR /data

COPY scripts/docker-entrypoint.sh /usr/local/bin/
ENTRYPOINT ["docker-entrypoint.sh"]

# EXPOSE 6379
CMD ["redis-server"]
