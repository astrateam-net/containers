#!/bin/sh
# Container is healthy only when BOTH supervised longruns report "up".
for svc in gerbil traefik; do
  /package/admin/s6/command/s6-svstat "/run/s6-rc/servicedirs/${svc}" | grep -q '^up' || exit 1
done
