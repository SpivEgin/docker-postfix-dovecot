#!/bin/bash

if [ ! $# = 1 ]
 then
  echo "Usage: $0 username@domain"
  exit 1
 else
  user=$(echo "$1" | cut -f1 -d "@")
  domain=$(echo "$1" | cut -s -f2 -d "@")

  if [[ -x $domain ]]
   then
    echo "No domain given\nUsage: $0 username@domain"
    exit 2
  fi

  dkim="/etc/opendkim/keys/$domain/"

  if [[ ! -x $dkim ]]
   then
    echo "Creating OpenDKIM folder $dkim"
    mkdir -p $dkim
    opendkim-genkey -s mail -d $domain −D $dkim --verbose
    chown opendkim:opendkim ${dkim}mail.private
    echo "*.$domain" >> /etc/opendkim/TrustedHosts
    echo "*@$domain mail._domainkey.$domain" >> /etc/opendkim/SigningTable
    echo "mail._domainkey.$domain $domain:mail:${dkim}mail.private" >> /etc/opendkim/KeyTable

    echo "mail._domainkey TXT v=DKIM1; k=rsa; p=$(cat ${dkim}mail.txt)"
  fi

  echo "Adding user $user@$domain to /etc/dovecot/users"
  echo "$user@$domain::5000:5000::/home/vmail/$domain/$user/:/bin/false::" >> /etc/dovecot/users

  # Create the needed Maildir directories
  echo "Creating user directory /home/vmail/$domain/$user"
  # maildirmake.dovecot does only chown on user directory, we'll create domain directory instead
  if [[ ! -x "/home/vmail/$domain" ]]
   then
    mkdir /home/vmail/$domain
    chown 5000:5000 /home/vmail/$domain
    chmod 700 /home/vmail/$domain
  fi
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
fi
echo "\nCreate a password for the new email user"
#SWAP THE FOLLOWING passwd LINES IF USING A UBUNTU VERSION PRIOR TO 12.04
#passwd=`dovecotpw`
passwd=$(pwgen)
passhash=$(doveadm pw -p $passwd -u $user)
echo "Adding password for $user@$domain to /etc/dovecot/passwd: $passwd"
if [[ ! -x /etc/dovecot/passwd ]]
 then
  touch /etc/dovecot/passwd
  chmod 640 /etc/dovecot/passwd
fi
echo  "$user@$domain:$passhash" >> /etc/dovecot/passwd

service postfix restart
service opendkim restart

tail /var/log/maillog

exit 0
