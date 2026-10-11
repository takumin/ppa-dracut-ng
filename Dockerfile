ARG BASE_IMAGE=docker.io/library/debian:13-slim

FROM ${BASE_IMAGE}

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install --no-install-recommends -y \
        build-essential \
        ca-certificates \
        devscripts \
        debhelper \
        fakeroot \
        quilt \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

ARG DEBFULLNAME="Takumi Takahashi"
ENV DEBFULLNAME=${DEBFULLNAME}

ARG DEBEMAIL="takumiiinn@gmail.com"
ENV DEBEMAIL=${DEBEMAIL}

WORKDIR /build
