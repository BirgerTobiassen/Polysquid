FROM ubuntu:24.04

# squid-openssl is the Ubuntu package that compiles Squid with --with-openssl,
# enabling https_port with tls-cert= / tls-key= options.
RUN apt-get update \
 && apt-get install -y --no-install-recommends squid-openssl \
 && rm -rf /var/lib/apt/lists/*

EXPOSE 3128
CMD ["squid", "-NYC", "-f", "/etc/squid/squid.conf"]
