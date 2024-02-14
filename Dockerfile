FROM arm64v8/ubuntu:focal
LABEL maintainer="VoidJuiceAlpha"
LABEL org.label-schema.schema-version="Latest"
LABEL org.label-schema.name="zoneminder"
LABEL org.label-schema.description="Zoneminder for ARM64"
LABEL org.label-schema.url="http://zoneminder.com"
LABEL org.label-schema.vcs-url="https://github.com/VoidJuiceAlpha/docker-zoneminder.git"

ENV TZ=America/New_York \
    PHP_MEMORY_LIMIT=512M \
    ZM_DB_HOST=zm \
    ZM_SERVER_HOST=zm \
    ZM_DB_NAME=zm \
    ZM_DB_USER=zmuser \
    ZM_DB_PASS=zmpass \
    ZM_DB_PORT=3306 \
    APACHE_RUN_USER=www-data \
    APACHE_RUN_GROUP=www-data \
    APACHE_LOG_DIR=/var/log/apache2

USER root

# Install pre-requisites
RUN echo $TZ > /etc/timezone  \
    && apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y -q --no-install-recommends \
        apt-transport-https gnupg curl wget ca-certificates locales \
        make gcc net-tools build-essential git \
        ntp dialog ntpdate \
        msmtp libyaml-perl libjson-perl libapache2-mod-perl2 \
        libvlc-dev libvlccore-dev vlc ffmpeg \
        apache2 php7.4 libapache2-mod-php php-mysql\
	devscripts sudo equivs \
	sphinx-doc python3-sphinx python3-sphinx-rtd-theme \
	dh-linktree dh-apache2 cmake libavcodec-dev \
	libavdevice-dev libavformat-dev libavutil-dev \
	libswresample-dev libswscale-dev arp-scan \
	libbz2-dev libcurl4-gnutls-dev libjpeg-turbo8-dev \
	libturbojpeg0-dev dput \
	libmysqlclient-dev libpolkit-gobject-1-dev libv4l-dev \
	libdate-manip-perl libdbd-mysql-perl libphp-serialization-perl \
	libsys-mmap-perl libdata-uuid-perl libssl-dev \
	libcrypt-eksblowfish-perl libdata-entropy-perl \
	libvncserver-dev libjwt-gnutls-dev \
	libgsoap-dev gsoap libmosquittopp-dev nlohmann-json3-dev \
	&& apt-get clean \
        && rm -rf /tmp/* /var/tmp/*  \
        && rm -rf /var/lib/apt/lists/*

# Install ZM
# RUN echo "deb http://ppa.launchpad.net/iconnor/zoneminder-1.36/ubuntu focal main" >> /etc/apt/sources.list  \
#   && apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 776FFB04 \
#    && apt-get update -y \
#    && apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y -q --no-install-recommends php-gd zoneminder \

# We're building this from source, son. 
# Directory setup
RUN mkdir /usr/src/zm_src 
# Grab the script, make it runable.
WORKDIR /usr/src/zm_src
RUN wget https://raw.githubusercontent.com/ZoneMinder/ZoneMinder/master/utils/do_debian_package.sh \
    && chmod a+x do_debian_package.sh \
    #You want to specify here what branch or snapshot you'd like to use. Currently set to pull the latest stable build.
    && ./do_debian_package.sh --distro=focal --branch=master --snapshot=stable --interactive=no --type=local
# Install the package
WORKDIR /usr/src/zm_src
RUN apt-get update \
	&& DEBIAN_FRONTEND=noninteractive apt-get install -y -q --no-install-recommends php-gd  ./"$(ls | grep zoneminder_1*.deb)" ./"$(ls | grep zoneminder-doc*.deb)"



# Cleanup!!!
RUN rm -rf -d /usr/src/zm_src/ \
    && apt-get clean \
    && rm -rf /tmp/* /var/tmp/*  \
    && rm -rf /var/lib/apt/lists/*



# Prepare some folders and files
RUN chown www-data /dev/shm \
    && mkdir -p /etc/service/apache2 /var/log/apache2 /var/log/zm /etc/backup_zm_conf \
    && mkdir -p /var/run/zm && chown www-data:www-data /var/run/zm \
    && mkdir -p /var/cache/zoneminder/{events,images,temp,cache} && chown -R root:www-data /var/cache/zoneminder && chmod -R 770 /var/cache/zoneminder \
    && chmod 740 /etc/zm/zm.conf && chown root:www-data /etc/zm/zm.conf \
    && chown -R www-data /var/log/apache2 \
    && echo "ServerName localhost" | tee /etc/apache2/conf-available/fqdn.conf \
    && ln -s /etc/apache2/conf-available/fqdn.conf /etc/apache2/conf-enabled/fqdn.conf \    
    && chown -R www-data:www-data /usr/share/zoneminder/ \
    && adduser www-data video \
    && cp -R /etc/zm/* /etc/backup_zm_conf/ \
#    && rm /etc/apache2/sites-enabled/000-default.conf \
    && sync 

# Cambozola
WORKDIR /usr/src 
RUN wget https://src.fedoraproject.org/lookaside/pkgs/cambozola/cambozola-latest.tar.gz/c4896a99702af61eead945ed58b5667b/cambozola-latest.tar.gz \
    && tar -xzvf /usr/src/cambozola-latest.tar.gz \
    && mv cambozola-0.936/dist/cambozola.jar /usr/share/zoneminder/www  \
    && rm /usr/src/cambozola-latest.tar.gz \
    && rm -R /usr/src/cambozola-0.936

# Perl Stuff and zmeventnotification.pl
WORKDIR /usr/bin
RUN wget https://raw.githubusercontent.com/pliablepixels/zmeventserver/master/zmeventnotification.pl \
    && chmod a+x zmeventnotification.pl \
    && mkdir -p /var/lib/zmeventnotification/push/ \
    && chown -R www-data:www-data /var/lib/zmeventnotification
RUN perl -MCPAN -e "install Digest::SHA1" \
    && perl -MCPAN -e "install Crypt::MySQL" \
    && perl -MCPAN -e "install Config::IniFiles" \
    && perl -MCPAN -e "install Net::WebSocket::Server" \
    && perl -MCPAN -e "install LWP::Protocol::https" \
    && perl -MCPAN -e "install Net::MQTT::Simple"
 #    && perl -MCPAN -e "install Devel::DumpTrace"

# Configure apache modules and sites
RUN a2enmod proxy proxy_balancer proxy_http ssl cgi rewrite php7.4 \
    && a2dissite default-ssl \
    && a2enconf zoneminder 
#    && update-rc.d zoneminder enable 

# Copy entrypoint script
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

WORKDIR /
VOLUME /var/cache/zoneminder /etc/zm /config /var/log/zm /var/lib/zoneminder/events
EXPOSE 80 9000 6802
ENTRYPOINT [ "/docker-entrypoint.sh" ]


