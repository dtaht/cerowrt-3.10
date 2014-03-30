#!/bin/sh

MAX_STRATUM=16
SLEEPTIME=5

which ntpd >/dev/null || exit 1

if [ -f "/tmp/dnsmasq-checkntp.lock" ] ; then
    logger -t "dnsmasq-checkntp[$$]" "Another instance running with pid $(cat /tmp/dnsmasq-checkntp.lock). Exiting."
    exit 0
else
    echo $$ >/tmp/dnsmasq-checkntp.lock
    logger -t "dnsmasq-checkntp[$$]" "Started checkntp. Date says: $(date). Sleeping for $SLEEPTIME seconds."
    sleep $SLEEPTIME
fi

if ps | grep -q '/usr/sbin/ntp[d]' && [ -f "/var/ntp.stratum" ]; then
    stratum=$(cat /var/ntp.stratum)
    logger -t "dnsmasq-checkntp[$$]" "Found running ntpd and stratum file. Initial stratum: $stratum."
    while [ "$stratum" -ge "$MAX_STRATUM" ]; do
        sleep $SLEEPTIME
        stratum=$(cat /var/ntp.stratum)
        logger -t "dnsmasq-checkntp[$$]" "ntpd stratum: $stratum."
    done
else
    logger -t "dnsmasq-checkntp[$$]" "No running ntpd found, or no stratum file. Running ntpd -q."
    while ! ntpd -q -n -p pool.ntp.org; do
        logger -t "dnsmasq-checkntp[$$]" "Manual ntp sync failed; will try again in $SLEEPTIME seconds."
        sleep $SLEEPTIME
    done
fi

logger -t "dnsmasq-checkntp[$$]" "Time should be in sync. Sending SIGHUP to dnsmasq."
killall -SIGHUP dnsmasq
rm -f /tmp/dnsmasq-checkntp.lock
