FROM bash:5.2

WORKDIR /workspace

COPY tests/docker/run_worker.sh /usr/local/bin/run_worker.sh

RUN adduser --disabled-password --gecos "" tester
USER tester

ENTRYPOINT ["/usr/local/bin/run_worker.sh"]
