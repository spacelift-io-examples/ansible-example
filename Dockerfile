FROM public.ecr.aws/spacelift/runner-ansible:10.2-azure-linux-amd64

USER root

RUN adduser --disabled-password --uid=1983 spacelift && apk add sshpass

USER spacelift