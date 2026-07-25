FROM --platform=linux/amd64 docker.io/bitnamilegacy/mastodon:4.3.6-debian-12-r0

# Copy Zai-modified-Mastodon sources into layer
COPY app/javascript/images /opt/bitnami/mastodon/app/javascript/images
COPY config/locales /opt/bitnami/mastodon/config/locales
COPY app/views/user_mailer/welcome.html.haml /opt/bitnami/mastodon/app/views/user_mailer

# Copy all modified app directories
COPY app/controllers /opt/bitnami/mastodon/app/controllers
COPY app/models /opt/bitnami/mastodon/app/models
COPY app/services /opt/bitnami/mastodon/app/services
COPY app/presenters /opt/bitnami/mastodon/app/presenters
COPY app/serializers /opt/bitnami/mastodon/app/serializers

# Copy database migrations and schema
COPY db/migrate /opt/bitnami/mastodon/db/migrate
COPY db/schema.rb /opt/bitnami/mastodon/db/schema.rb

# Copy config and additional resources
COPY config/routes /opt/bitnami/mastodon/config/routes
COPY lib/tasks /opt/bitnami/mastodon/lib/tasks

USER 1001
ENTRYPOINT [ "/opt/bitnami/scripts/mastodon/entrypoint.sh" ]
CMD [ "/opt/bitnami/scripts/mastodon/run.sh" ]
