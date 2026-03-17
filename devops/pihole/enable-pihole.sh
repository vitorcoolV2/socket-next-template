#!/bin/bash

#!/bin/bash

.  ./dns_utils.sh
.  ./_0.pihole_lib.sh

ph down
ph disable
set_nmcli_resolver ("${PIHOLE_SPARK_DNS[@]}")


ph up
ph enable


echo "⏳ Waiting for Pi-hole..."
until curl -s http://$PIHOLE_DNS_IP/admin/ > /dev/null; do
    sleep 2
done

