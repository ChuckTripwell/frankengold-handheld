FROM docker.io/cachyos/cachyos-v3:latest AS cachyos

RUN rm -rf /lib/modules/*
RUN pacman -Sy --noconfirm linux-cachyos-deckify



FROM ghcr.io/ublue-os/bazzite-deck:stable

RUN rm -rf /lib/modules
COPY --from=cachyos /lib/modules /lib/modules

RUN bootc container lint
