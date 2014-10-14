Postfix, Dovecot, OpenDKIM (through static user db)
========

## Usage

```bash
docker pull pocesar/docker-postfix-dovecot
docker run \
    -p 993:993 \
    -p 587:587 \
    -v /home/vmail:/home/vmail \
    -e MAILNAME="somedomain.com"
    -v /etc/postfix
    -v /etc/dovecot
    -v /etc/ssl
    -v /etc/opendkim
    -v /var/log/container:/var/log
    pocesar/docker-postfix-dovecot
    --email youremail@somedomain.com
    --email another@somedomain.com
```