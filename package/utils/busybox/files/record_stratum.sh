#!/bin/sh

# ntpd passes stratum through the environment.
# record it to allow external processes to check the status of ntpd.
echo $stratum > /var/ntp.stratum
