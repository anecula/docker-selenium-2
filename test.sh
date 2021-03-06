#!/usr/bin/env bash
DEBUG=''
VERSION=${VERSION:-3.6.0-bromine}

if [ -n "$1" ] && [ $1 == 'debug' ]; then
  DEBUG='-debug'
fi

# Due to the dependency GNU sed, we're skipping this part when running
# on Mac OS X.
if [ "$(uname)" != 'Darwin' ] ; then
  echo 'Testing shell functions...'
  which bats > /dev/null 2>&1
  if [ $? -ne 0 ] ; then
    echo "Could not find 'bats'. Please install it first, e.g., following https://github.com/sstephenson/bats#installing-bats-from-source."
    exit 1
  fi
  NodeBase/test-functions.sh || exit 1
else
  echo 'Skipping shell functions test on Mac OS X.'
fi

echo Building test container image
docker build -t selenium/test:local ./Test

echo 'Starting Selenium Hub Container...'
HUB=$(docker run -d selenium/hub:${VERSION})
HUB_NAME=$(docker inspect -f '{{ .Name  }}' $HUB | sed s:/::)
echo 'Waiting for Hub to come online...'
docker logs -f $HUB &
sleep 2

echo 'Starting Selenium Chrome node...'
NODE_CHROME=$(docker run -d --link $HUB_NAME:hub  selenium/node-chrome$DEBUG:${VERSION})
echo 'Starting Selenium Firefox node...'
NODE_FIREFOX=$(docker run -d --link $HUB_NAME:hub selenium/node-firefox$DEBUG:${VERSION})
if [ -z $DEBUG ]; then
  echo 'Starting Selenium PhantomJS node...'
  NODE_PHANTOMJS=$(docker run -d --link $HUB_NAME:hub selenium/node-phantomjs:${VERSION})
fi
docker logs -f $NODE_CHROME &
docker logs -f $NODE_FIREFOX &
if [ -z $DEBUG ]; then
  docker logs -f $NODE_PHANTOMJS &
fi
echo 'Waiting for nodes to register and come online...'
sleep 2

function test_node {
  BROWSER=$1
  echo Running $BROWSER test...
  TEST_CMD="node smoke-$BROWSER.js"
  docker run -it --link $HUB_NAME:hub -e TEST_CMD="$TEST_CMD" selenium/test:local
  STATUS=$?
  TEST_CONTAINER=$(docker ps -aq | head -1)

  if [ ! $STATUS == 0 ]; then
    echo Failed
    exit 1
  fi

  if [ ! "${TRAVIS}" ==  "true" ]; then
    echo Removing the test container
    docker rm $TEST_CONTAINER
  fi

}

test_node chrome $DEBUG
test_node firefox $DEBUG
if [ -z $DEBUG ]; then
  test_node phantomjs $DEBUG
fi

if [ ! "${TRAVIS}" ==  "true" ]; then
  echo Tearing down Selenium Chrome Node container
  docker stop $NODE_CHROME
  docker rm $NODE_CHROME

  echo Tearing down Selenium Firefox Node container
  docker stop $NODE_FIREFOX
  docker rm $NODE_FIREFOX

  if [ -z $DEBUG ]; then
    echo Tearing down Selenium PhantomJS Node container
    docker stop $NODE_PHANTOMJS
    docker rm $NODE_PHANTOMJS
  fi

  echo Tearing down Selenium Hub container
  docker stop $HUB
  docker rm $HUB
fi

echo Done
