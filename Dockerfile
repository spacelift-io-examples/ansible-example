FROM public.ecr.aws/spacelift/runner-ansible:10.2-azure-linux-amd64

USER root

RUN apk add sshpass

USER spacelift