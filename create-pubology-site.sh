#!/bin/bash
# create directories for pubology.co.uk
# assumes you have cloned https://github.com/rjw1/pubology.co.uk
# into /home/pubology/web/vhosts

chown www-data /home/pubology/web/vhosts/pubology.co.uk
for dir in data indexes kml maps pubs
do
  mkdir -p /home/pubology/web/vhosts/pubology.co.uk/${dir}
  chown www-data /home/pubology/web/vhosts/pubology.co.uk/${dir}
done
