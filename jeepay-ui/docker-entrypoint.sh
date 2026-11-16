#!/bin/sh
envsubst '${BACKEND_HOST},${PORT}' < /etc/nginx/templates/default.conf.template > /etc/nginx/conf.d/default.conf
exec nginx -g "daemon off;"
