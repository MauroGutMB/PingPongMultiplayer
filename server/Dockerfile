# Compiles the lobby/match server to a native AOT executable, then ships it
# in a minimal runtime image (no Dart SDK, no shell).
FROM dart:stable AS build

WORKDIR /app

COPY pubspec.* ./
RUN dart pub get

COPY . .
RUN dart pub get --offline
RUN dart compile exe bin/server.dart -o bin/server

FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/bin/server /app/bin/server

EXPOSE 8080
ENV PORT=8080

ENTRYPOINT ["/app/bin/server"]
