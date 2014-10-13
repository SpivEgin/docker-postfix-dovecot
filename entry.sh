#!/bin/bash

if [ -n "$MAILNAME" ]
then
  mailname="$MAILNAME"
elif [ "$FQDN" = "1" ]
then
  mailname=$(hostname -f)
fi

(
  service dovecot stop
  service postfix stop
  service opendkim stop
)

# VMAIL
groupadd -g 5000 vmail
useradd -u 5000 -g 5000 -s /bin/bash vmail

sed -i 's/#START/START/' /etc/default/saslauthd

(
  mkdir /etc/postfix/ssl
  cd /etc/postfix/ssl/
  openssl genrsa -des3 -rand /etc/hosts -out smtpd.key 1024
  chmod 600 smtpd.key
  openssl req -new -key smtpd.key -out smtpd.csr
  openssl x509 -req -days 3650 -in smtpd.csr -signkey smtpd.key -out smtpd.crt
  openssl rsa -in smtpd.key -out smtpd.key.unencrypted
  mv -f smtpd.key.unencrypted smtpd.key
  openssl req -new -x509 -extensions v3_ca -keyout cakey.pem -out cacert.pem -days 3650
)

postconf -e 'milter_protocol = 2'
postconf -e 'milter_default_action = accept'
postconf -e 'smtpd_milters = inet:localhost:12301'
postconf -e 'non_smtpd_milters = inet:localhost:12301'
postconf -e 'virtual_mailbox_domains = /etc/postfix/vhosts'
postconf -e 'virtual_mailbox_base = /home/vmail'
postconf -e 'virtual_mailbox_maps = hash:/etc/postfix/vmaps'
postconf -e 'virtual_minimum_uid = 1000'
postconf -e 'virtual_uid_maps = static:5000'
postconf -e 'virtual_gid_maps = static:5000'
postconf -e 'smtpd_sasl_auth_enable = yes'
postconf -e 'smtpd_sasl_security_options = noplaintext,noanonymous'
postconf -e 'smtpd_recipient_restrictions = permit_sasl_authenticated,permit_mynetworks,reject_unauth_destination'
postconf -e 'smtpd_sasl_type = dovecot'
postconf -e 'smtpd_sasl_path = private/auth-client'
postconf -e 'smtpd_tls_auth_only = yes'
postconf -e 'smtp_tls_security_level = may'
postconf -e 'smtpd_tls_security_level = may'
postconf -e 'smtp_use_tls = yes'
postconf -e 'local_recipient_maps ='
postconf -e 'smtpd_use_tls = yes'
postconf -e 'smtp_tls_note_starttls_offer = yes'
postconf -e 'smtpd_tls_key_file = /etc/postfix/ssl/smtpd.key'
postconf -e 'smtpd_tls_cert_file = /etc/postfix/ssl/smtpd.crt'
postconf -e 'smtpd_tls_CAfile = /etc/postfix/ssl/cacert.pem'
postconf -e 'smtpd_tls_loglevel = 1'
postconf -e 'smtpd_tls_received_header = yes'
postconf -e 'smtpd_tls_session_cache_timeout = 3600s'
postconf -e 'tls_random_source = dev:/dev/urandom'


test -f /etc/postfix/vhosts || touch /etc/postfix/vhosts
test -f /etc/postfix/vmaps || touch /etc/postfix/vmaps
test -f /etc/dovecot/users || touch /etc/dovecot/users

test -d /etc/opendkim/keys || mkdir -p /etc/opendkim/keys
test -f /etc/opendkim/TrustedHosts || touch /etc/opendkim/TrustedHosts
test -f /etc/opendkim/KeyTable || touch /etc/opendkim/KeyTable
test -f /etc/opendkim/SigningTable || touch /etc/opendkim/SigningTable

echo 'SOCKET="inet:12301@localhost"' >> /etc/default/opendkim
echo "mech_list: cram-md5" > /etc/postfix/sasl/smtpd.conf

while [ $# -gt 0 ]
do
    case "$1" in
      (--email)
        shift
        if [[ -z "$1" ]]
        then
          continue
        fi

        user=$(echo "$1" | cut -f1 -d "@")
        domain=$(echo "$1" | cut -s -f2 -d "@")

        if [[ -z $domain ]]
        then
          continue
        fi

        if [[ -z $mailname ]]
        then
          mailname="$domain"
        fi

        dkim="/etc/opendkim/keys/$domain"

        if [[ ! -d $dkim ]]
        then
          echo "Creating OpenDKIM folder $dkim"
          mkdir -p $dkim
          cd $dkim && opendkim-genkey -s mail -d $domain
          chown opendkim:opendkim $dkim/mail.private
          echo "*.$domain" >> /etc/opendkim/TrustedHosts
          echo "*@$domain mail._domainkey.$domain" >> /etc/opendkim/SigningTable
          echo "mail._domainkey.$domain $domain:mail:$dkim/mail.private" >> /etc/opendkim/KeyTable
          cat "$dkim/mail.txt"
        fi

        # maildirmake.dovecot does only chown on user directory, we'll create domain directory instead
        if [[ ! -d "/home/vmail/$domain" ]]
        then
          mkdir /home/vmail/$domain
          chown 5000:5000 /home/vmail/$domain
          chmod 700 /home/vmail/$domain
        fi

        if [[ ! -d "/home/vmail/$domain/$user" ]]
        then
          if [[ -z $(grep $user@$domain /etc/dovecot/users) ]]
          then
            echo "Adding user $user@$domain to /etc/dovecot/users"
            echo "$user@$domain::5000:5000::/home/vmail/$domain/$user/:/bin/false::" >> /etc/dovecot/users

            passwd=$(pwgen)
            passhash=$(doveadm pw -p $passwd -u $user)
            echo "Adding password for $user@$domain to /etc/dovecot/passwd: $passwd"
            if [[ ! -x /etc/dovecot/passwd ]]
            then
              touch /etc/dovecot/passwd
              chmod 640 /etc/dovecot/passwd
            fi
            echo "$user@$domain:$passhash" >> /etc/dovecot/passwd
          fi

          # Create the needed Maildir directories
          echo "Creating user directory /home/vmail/$domain/$user"

          /usr/bin/maildirmake.dovecot /home/vmail/$domain/$user 5000:5000
          # Also make folders for Drafts, Sent, Junk and Trash
          /usr/bin/maildirmake.dovecot /home/vmail/$domain/$user/.Drafts 5000:5000
          /usr/bin/maildirmake.dovecot /home/vmail/$domain/$user/.Sent 5000:5000
          /usr/bin/maildirmake.dovecot /home/vmail/$domain/$user/.Junk 5000:5000
          /usr/bin/maildirmake.dovecot /home/vmail/$domain/$user/.Trash 5000:5000

          # To add user to Postfix virtual map file and relode Postfix
          echo "Adding user to /etc/postfix/vmaps"
          echo "$1  $domain/$user/" >> /etc/postfix/vmaps
          postmap /etc/postfix/vmaps
          grep -e "$domain" /etc/postfix/vhosts || echo "$domain" >> /etc/postfix/vhosts
        else
          echo "$user@$domain already exists, skipping"
        fi
        ;;
    esac
  shift
done

postconf -e "myhostname=$mailname"

supervisord -n -c /etc/supervisor/conf.d/supervisord.conf
