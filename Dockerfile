# Base stage for building gems
FROM        ruby:2.7.4-bullseye as bundle
RUN      echo "deb http://archive.debian.org/debian bullseye non-free contrib main" > /etc/apt/sources.list \
         && apt-get update && apt-get upgrade -y build-essential \
         && apt-get install -y --no-install-recommends \
            cmake \
            make \
            libc6 \
            pkg-config \
            zip \
            git \
            libyaz-dev \
         && rm -rf /var/lib/apt/lists/* \
         && apt-get clean

COPY        Gemfile ./Gemfile
COPY        Gemfile.lock ./Gemfile.lock

#RUN         gem install bundler -v "$(grep -A 1 "BUNDLED WITH" Gemfile.lock | tail -n 1)" \
#RUN gem install nokogiri -v 1.15.7

RUN         gem install bundler -v2.4.22 \
         && bundle update
RUN       bundle config set force_ruby_platform true \
          && gem install nokogiri --platform=ruby -v 1.15.7
#         && bundle config build.nokogiri --use-system-libraries


# Download binaries in parallel
FROM        ruby:2.7.4-bullseye as download
RUN         curl -L https://github.com/jwilder/dockerize/releases/download/v0.6.1/dockerize-linux-amd64-v0.6.1.tar.gz | tar xvz -C /usr/bin/
RUN         curl https://chromedriver.storage.googleapis.com/2.46/chromedriver_linux64.zip -o /usr/local/bin/chromedriver \
         && chmod +x /usr/local/bin/chromedriver
RUN         curl https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb -o /chrome.deb
RUN         mkdir -p /tmp/ffmpeg && cd /tmp/ffmpeg \
         && curl https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz | tar xJ \
         && cp `find . -type f -executable` /usr/bin/

# Base stage for building final images
FROM      ruby:2.7.4-bullseye as base

RUN       echo "deb http://archive.debian.org/debian bullseye non-free contrib main" > /etc/apt/sources.list \
          && apt-get update && apt-get install -y --force-yes --no-install-recommends zstd curl gnupg2 nodejs \
          && curl -O https://mediaarea.net/repo/deb/repo-mediaarea_1.0-26_all.deb \
          && ar x repo-mediaarea_1.0-26_all.deb \
          && zstd -d < control.tar.zst | xz > control.tar.xz \
          && zstd -d < data.tar.zst | xz > data.tar.xz \
          && ar -m -c -a sdsd /tmp/repo-mediaarea_1.0-26_all.deb debian-binary control.tar.xz data.tar.xz \
          && dpkg -i /tmp/repo-mediaarea_1.0-26_all.deb \
          && wget -O yarnpkg.gpg.pub https://dl.yarnpkg.com/debian/pubkey.gpg \
          && apt-key add yarnpkg.gpg.pub \
          && echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list


RUN       echo "deb http://archive.debian.org/debian bullseye non-free contrib main" > /etc/apt/sources.list \
&&         apt-get update && apt-get install -y --no-install-recommends --allow-unauthenticated \
            nodejs \
            yarn \
            lsof \
            x264 \
            sendmail \
            git \
            libxml2-dev \
            libxslt-dev \
            libpq-dev \
            mediainfo \
            openssh-client \
            zip \
            dumb-init \
            libyaz-dev \
         && ln -s /usr/bin/lsof /usr/sbin/

RUN         curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash \
            && \. "$HOME/.nvm/nvm.sh" \
            && nvm install 14 \
            && npm install --global yarn \
            && yarn --version
RUN         useradd -m -U app \
         && su -s /bin/bash -c "mkdir -p /home/app/avalon" app
WORKDIR     /home/app/avalon

COPY        --from=download /usr/bin/ff* /usr/bin/


# Build production gems
FROM        bundle as bundle-prod
RUN         bundle install --without development test --with aws production postgres


# Install node modules
FROM        node:14.18.0-bullseye-slim as node-modules
RUN          echo "deb http://archive.debian.org/debian bullseye non-free contrib main" > /etc/apt/sources.list \
            && apt-get update && apt-get install -y --no-install-recommends build-essential gcc git python2 ca-certificates
COPY        package.json .
COPY        yarn.lock .
RUN          yarn install

# Build production assets
FROM        base as assets
COPY        --from=bundle-prod --chown=app:app /usr/local/bundle /usr/local/bundle
COPY        --chown=app:app . .
COPY        --from=node-modules --chown=app:app /node_modules ./node_modules

USER        app
ENV         RAILS_ENV=production
RUN         curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash \
            && \. "$HOME/.nvm/nvm.sh" \
            && nvm install 14 \
            && npm install globalthis \
            && npm install --global yarn \
            yarn --version
RUN         bundle install \
            &&  SECRET_KEY_BASE=$(ruby -r 'securerandom' -e 'puts SecureRandom.hex(64)') bundle exec rake webpacker:compile

RUN         SECRET_KEY_BASE=$(ruby -r 'securerandom' -e 'puts SecureRandom.hex(64)') bundle exec rake assets:precompile
RUN         cp config/controlled_vocabulary.yml.example config/controlled_vocabulary.yml

