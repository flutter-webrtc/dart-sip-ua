FROM google/dart:1.24.3

WORKDIR /tool
RUN git clone https://github.com/cloudwebrtc/peg && \
    cd peg && \
    pub get && \
    pub global activate --source path .

WORKDIR /src
CMD ["dart", "/tool/peg/bin/peg.dart", "general", "/src/grammar.peg"]