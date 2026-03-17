#!/bin/bash

.  ./dns_utils.sh
.  ./_0.pihole_lib.sh

ph down
ph disable
set_nmcli_resolver ("${PIHOLE_SPARK_DNS[@]}")
