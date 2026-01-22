FROM --platform=linux/amd64 docker.io/bitnamilegacy/mastodon:4.3.6-debian-12-r0

# Copy Zai-modified-Mastodon sources into layer
# COPY app/javascript/images /opt/bitnami/mastodon/app/javascript/images
# COPY config/locales /opt/bitnami/mastodon/config/locales
# COPY app/views/user_mailer/welcome.html.haml /opt/bitnami/mastodon/app/views/user_mailer

# Copy internal API files
COPY app/controllers/api/v1/internal /opt/bitnami/mastodon/app/controllers/api/v1/internal
COPY app/services/internal /opt/bitnami/mastodon/app/services/internal
COPY config/routes/api.rb /opt/bitnami/mastodon/config/routes/api.rb

USER 1001
ENTRYPOINT [ "/opt/bitnami/scripts/mastodon/entrypoint.sh" ]
CMD [ "/opt/bitnami/scripts/mastodon/run.sh" ]
