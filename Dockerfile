FROM ubuntu:trusty
MAINTAINER Paulo Cesar <email@pocesar.e4ward.com>

ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update -y -q && apt-get dist-upgrade -y -q

# VMAIL
RUN groupadd -g 5000 vmail
RUN useradd -m -u 5000 -g 5000 -s /bin/bash vmail

# Install packages
RUN  apt-get install -y -q pwgen postfix postfix-pcre dovecot-common dovecot-core dovecot-imapd opendkim opendkim-tools

ADD dovecot/dovecot.conf /etc/dovecot/dovecot.conf
ADD opendkim/opendkim.conf /etc/opendkim.conf

RUN mkdir -p /etc/opendkim/keys
RUN [ ! -e "/etc/opendkim/TrustedHosts" ] && touch /etc/opendkim/TrustedHosts
RUN [ ! -e "/etc/opendkim/KeyTable" ] && touch /etc/opendkim/KeyTable
RUN [ ! -e "/etc/opendkim/SigningTable" ] && touch /etc/opendkim/SigningTable
RUN cat $TRUSTED_HOSTS >> /etc/opendkim/TrustedHosts
RUN echo 'SOCKET="inet:12301@localhost"' >> /etc/default/opendkim
RUN postconf -e 'milter_protocol = 2'
RUN postconf -e 'milter_default_action = accept'
RUN postconf -e 'smtpd_milters = inet:localhost:12301'
RUN postconf -e 'non_smtpd_milters = inet:localhost:12301'
RUN postconf -e 'virtual_mailbox_domains = /etc/postfix/vhosts'
RUN postconf -e 'virtual_mailbox_base = /home/vmail'
RUN postconf -e 'virtual_mailbox_maps = hash:/etc/postfix/vmaps'
RUN postconf -e 'virtual_minimum_uid = 1000'
RUN postconf -e 'virtual_uid_maps = static:5000'
RUN postconf -e 'virtual_gid_maps = static:5000'
RUN sed -i 's/#submission/submission/' /etc/postfix/master.cf

# SMTPS
EXPOSE 465
# IMAP over SSL
EXPOSE 993
# Submission
EXPOSE 587

ADD entry.sh /entry.sh
RUN chmod +x /entry.sh

ENTRYPOINT ["/entry.sh"]

