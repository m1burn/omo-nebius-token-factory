# VIOLATIONS PLANTED FOR QUALITY-SMOKE (do not fix):
# - DL3007: base image pinned to the :latest tag
# - DL3002: container's last user is the superuser (root)
FROM node:latest
WORKDIR /app
USER root
CMD ["node", "-e", "console.log('quality-smoke')"]
