FROM opendronemap/odm:gpu  AS build


RUN pip3 install  awscli


COPY entry.sh /

ENTRYPOINT [ "/entry.sh" ]

