FROM jetpackio/devbox:latest

RUN sudo apt-get update && sudo apt-get install -y \
    procps

# Installing your devbox project
WORKDIR /code
COPY devbox.json devbox.json
COPY devbox.lock devbox.lock
RUN sudo chown -R "${DEVBOX_USER}:${DEVBOX_USER}" /code


RUN devbox run -- echo "Installed Packages."

CMD ["devbox", "shell"]
