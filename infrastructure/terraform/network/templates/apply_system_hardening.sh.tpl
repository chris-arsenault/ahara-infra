#!/bin/bash
set -euxo pipefail

dnf -y install dnf-automatic chrony audit aide scap-security-guide

systemctl enable --now chronyd
systemctl enable --now auditd

cat >/etc/dnf/automatic.conf <<'EOC'
${DNF_AUTOMATIC_CONF}
EOC

systemctl enable --now dnf-automatic-install.timer

cat >/etc/profile.d/00-secure-umask.sh <<'EOC'
umask 027
EOC

cat >/etc/sysctl.d/90-hardening.conf <<'EOC'
${SYSCTL_HARDENING_CONF}
EOC

sysctl --system

if grep -q "^PasswordAuthentication" /etc/ssh/sshd_config; then
  sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
else
  echo "PasswordAuthentication no" >> /etc/ssh/sshd_config
fi

if grep -q "^PermitRootLogin" /etc/ssh/sshd_config; then
  sed -i 's/^PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
else
  echo "PermitRootLogin prohibit-password" >> /etc/ssh/sshd_config
fi

systemctl try-restart sshd || true

mkdir -p /etc/aide.conf.d

cat >/etc/aide.conf.d/amazon-linux.conf <<'EOC'
${AIDE_AMAZON_LINUX_CONF}
EOC

if [ ! -f /var/lib/aide/aide.db.gz ]; then
  aide --init
  mv /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz
fi

if [ -f /usr/share/xml/scap/ssg/content/ssg-amazon_linux-2023-ds.xml ]; then
  oscap xccdf eval \
    --profile xccdf_org.ssgproject.content_profile_stig \
    --report /var/log/oscap-stig.html \
    --results /var/log/oscap-stig.xml \
    --fetch-remote-resources \
    /usr/share/xml/scap/ssg/content/ssg-amazon_linux-2023-ds.xml || true
fi
