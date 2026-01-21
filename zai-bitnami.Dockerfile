FROM --platform=linux/amd64 docker.io/bitnami/mastodon:4.3.6-debian-12-r0

# Copy Zai-modified-Mastodon sources into layer
COPY app/javascript/images /opt/bitnami/mastodon/app/javascript/images
COPY config/locales /opt/bitnami/mastodon/config/locales
# modify user_welcome email
COPY app/views/user_mailer/welcome.html.haml /opt/bitnami/mastodon/app/views/user_mailer
# make sure to remove precompiled packs and assets (these are the one actually served) so that the entry point can run it for new images copied earlier
# RUN rm -rf /opt/bitnami/mastodon/public/packs /opt/bitnami/mastodon/public/assets

USER 1001
ENTRYPOINT [ "/opt/bitnami/scripts/mastodon/entrypoint.sh" ]
CMD [ "/opt/bitnami/scripts/mastodon/run.sh" ]