#!/bin/bash
set -e

if [ $GIT_REPO == "gitlab" ]; then
	GIT_URL="gitlab/gitlab"
	GIT_CONF="proxy_pass http:\/\/gitlab\/gitlab; \
\\n\\tproxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for; \
\\n\\tproxy_set_header Client-IP \$remote_addr;"
	sed -i "s/###GIT_REPO###/$GIT_REPO/g" /resources/configuration/sites-enabled/tools-context.conf
	sed -i "s/###GIT_CONF###/$GIT_CONF/g" /resources/configuration/sites-enabled/tools-context.conf
	jq ".core[].components[1] |= .+ {id: \"gitlab\", title: \"gitlab\", img: \"img\/gitlab.svg\", link: \"/gitlab\"}" /resources/release_note/plugins.json > /resources/release_note/pluginsgitlab.json
	mv /resources/release_note/pluginsgitlab.json /resources/release_note/plugins.json
elif [ $GIT_REPO == "gerrit" ]; then
	GIT_URL="gerrit:8080/gerrit"
	GIT_CONF="client_max_body_size 512m; \
\\n\\tproxy_pass http:\/\/gerrit:8080;"
	sed -i "s/###GIT_REPO###/$GIT_REPO/g" /resources/configuration/sites-enabled/tools-context.conf
	sed -i "s/###GIT_CONF###/$GIT_CONF/g" /resources/configuration/sites-enabled/tools-context.conf
	jq ".core[].components[1] |= .+ {id: \"gerrit\", title: \"gerrit\", img: \"img\/gerrit.jpg\", link: \"/gerrit/\"}" /resources/release_note/plugins.json > /resources/release_note/pluginsgerrit.json
	mv /resources/release_note/pluginsgerrit.json /resources/release_note/plugins.json
fi

cp -R /resources/configuration/* /etc/nginx/
cp -R /resources/release_note/* /usr/share/nginx/html/

# Auto populate the release note page with the blueprints
/resources/scripts/reload_release_notes.sh

# Copy and replace tokens
perl -p -i -e 's/###([^#]+)###/defined $ENV{$1} ? $ENV{$1} : $&/eg' < "/templates/configuration/nginx.conf" 2> /dev/null 1> "/etc/nginx/nginx.conf"

# wait for all downstream services to be up and running
# This is a temporary solution that allows NGINX to wait for all dependencies and after start, this should be removed when 
# the depends_on see https://github.com/docker/compose/pull/686 and https://github.com/docker/compose/issues/2682 is introduced
# on docker compose
SLEEP_TIME=2

declare -a DEPENDENCIES=( "kibana:5601" "jenkins:8080" "sonar:9000" "sensu-uchiwa:3000" "nexus:8081" "$GIT_URL")

for d in ${DEPENDENCIES[@]}; do 
  echo "waiting for $d to be available";
  # use wget as already installed... 
  # We are checking for response codes that are not of class 5xx the most common are below, the list does not 
  # try to be exaustive, it only consider the response code that will guarantee NGINX to start when all dependencies are 
  # available.
  until wget -S -O - http://$d 2>&1 | grep "HTTP/" | awk '{print $2}' | grep "200\|404\|403\|401\|301\|302" &> /dev/null
  do
      echo "$d unavailable, sleeping for ${SLEEP_TIME}"
      sleep "${SLEEP_TIME}"
  done
done

/usr/sbin/nginx
