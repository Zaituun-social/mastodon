FROM --platform=linux/amd64 docker.io/bitnamilegacy/mastodon:4.4.3-debian-12-r11

# Apply the Zai fork's delta against upstream Mastodon.
#
# .zai-overlay/ mirrors the Mastodon tree and contains ONLY the files this fork
# actually changed. Generate it before building:
#
#   ./bin/zai-overlay && docker build -f zai-bitnami.Dockerfile .
#
# Do not replace this with directory-wide COPYs (app/controllers, app/models,
# lib/tasks, ...). Those also copy unmodified upstream files from this checkout
# over the base image's own code; because the checkout and the image are
# different Mastodon builds, that breaks the image at boot. See bin/zai-overlay
# for the three boot failures this has already caused.
COPY .zai-overlay/ /opt/bitnami/mastodon/

USER 1001
ENTRYPOINT [ "/opt/bitnami/scripts/mastodon/entrypoint.sh" ]
CMD [ "/opt/bitnami/scripts/mastodon/run.sh" ]
